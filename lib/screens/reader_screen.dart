import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/library.dart';
import '../services/pagination.dart';
import '../theme/reader_theme.dart';
import '../widgets/reader_sheets.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
  static const MethodChannel _native = MethodChannel('moread/native');

  final ReaderSettings _settings = ReaderSettings.instance;
  late final Book _book = widget.book;

  String _text = '';
  List<Chapter> _chapters = const [];
  bool _loading = true;
  String? _error;

  int _chapterIndex = 0;
  int _charOffset = 0;
  List<PageChunk> _pages = const [];
  int _pageIndex = 0;
  String _cacheKey = '';
  int _pagesChapter = -1;
  PageController _controller = PageController();

  bool _menuVisible = false;
  bool _settingsVisible = false;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _setKeepAwake(true);
    _settings.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveNow();
    Library.instance.flush();
    _setKeepAwake(false);
    _settings.removeListener(_onSettingsChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveNow();
      Library.instance.flush();
    }
  }

  void _setKeepAwake(bool on) {
    // 阅读时别让屏幕自己灭；失败也不影响阅读。
    _native.invokeMethod<void>('keepAwake', on).catchError((_) {});
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final text = await Library.instance.readText(_book);
      final chapters = await Library.instance.loadChapters(_book);
      if (!mounted) return;
      if (text.isEmpty) {
        setState(() {
          _error = '这本书没有正文内容';
          _loading = false;
        });
        return;
      }
      setState(() {
        _text = text;
        _chapters = chapters.isEmpty ? [Chapter(title: '正文', start: 0, end: text.length)] : chapters;
        _chapterIndex = _book.chapterIndex.clamp(0, _chapters.length - 1).toInt();
        _charOffset = _book.charOffset;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  // ------------------------------------------------------------ 分页与翻页

  void _ensurePages(Size size) {
    if (_chapters.isEmpty || _text.isEmpty) return;
    final key =
        '${size.width.toStringAsFixed(1)}x${size.height.toStringAsFixed(1)}|${_settings.fontSize}|${_settings.lineHeight}|${_settings.fontFamily}|$_chapterIndex';
    if (key == _cacheKey) return;
    _cacheKey = key;

    final chapter = _chapters[_chapterIndex];
    final start = chapter.start.clamp(0, _text.length);
    final end = chapter.end.clamp(0, _text.length);
    final body = _text.substring(start, end);
    _pages = Paginator.paginate(
      text: body,
      style: _settings.textStyle(),
      size: size,
    );
    _pageIndex = Paginator.pageOfOffset(_pages, _charOffset.clamp(0, body.length));
    _pagesChapter = _chapterIndex;

    final old = _controller;
    _controller = PageController(initialPage: _pageIndex.clamp(0, _pages.length - 1));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!old.hasClients) old.dispose();
    });
  }

  void _turn(int delta) {
    if (_pages.isEmpty) return;
    if (delta > 0) {
      if (_pageIndex < _pages.length - 1) {
        _controller.nextPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      } else if (_chapterIndex < _chapters.length - 1) {
        _gotoChapter(_chapterIndex + 1);
      } else {
        _toast('已经是全书最后一页');
      }
    } else {
      if (_pageIndex > 0) {
        _controller.previousPage(duration: const Duration(milliseconds: 260), curve: Curves.easeOutCubic);
      } else if (_chapterIndex > 0) {
        _gotoChapter(_chapterIndex - 1, toEnd: true);
      }
    }
  }

  void _gotoChapter(int index, {bool toEnd = false}) {
    if (index < 0 || index >= _chapters.length) return;
    final chapter = _chapters[index];
    _applyPosition(index, toEnd ? (chapter.end - chapter.start) : 0);
  }

  void _applyPosition(int chapterIndex, int offset) {
    if (chapterIndex < 0 || chapterIndex >= _chapters.length) return;
    setState(() {
      _chapterIndex = chapterIndex;
      _charOffset = offset;
      _cacheKey = '';
      if (_menuVisible) _settingsVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleSave();
    });
  }

  void _onPageChanged(int index) {
    HapticFeedback.selectionClick();
    setState(() {
      _pageIndex = index;
      if (index >= 0 && index < _pages.length) _charOffset = _pages[index].start;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _saveNow);
  }

  void _saveNow() {
    if (_chapters.isEmpty || _pages.isEmpty || _pagesChapter != _chapterIndex) return;
    final page = _pages[_pageIndex.clamp(0, _pages.length - 1)];
    final chapter = _chapters[_chapterIndex];
    final absolute = chapter.start + page.start;
    final percent = _text.isEmpty ? 0.0 : (absolute / _text.length).clamp(0.0, 1.0);
    Library.instance.updateProgress(
      _book,
      chapterIndex: _chapterIndex,
      charOffset: page.start,
      percent: percent,
    );
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: const Duration(seconds: 1, milliseconds: 400),
        ),
      );
  }

  void _setMenu(bool visible) {
    if (_menuVisible == visible) return;
    HapticFeedback.lightImpact();
    setState(() {
      _menuVisible = visible;
      if (!visible) _settingsVisible = false;
    });
  }

  // ---------------------------------------------------------------- 界面

  @override
  Widget build(BuildContext context) {
    final theme = _settings.theme;
    return Scaffold(
      backgroundColor: theme.background,
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
        child: _loading
            ? _loadingView(theme)
            : _error != null
                ? _errorView(theme)
                : _readerView(theme),
      ),
    );
  }

  Widget _loadingView(ReaderTheme theme) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 26,
              height: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4, color: theme.dim),
            ),
            const SizedBox(height: 16),
            Text('正在排版…', style: TextStyle(color: theme.dim, fontSize: 13)),
          ],
        ),
      );

  Widget _errorView(ReaderTheme theme) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, color: theme.dim, size: 40),
              const SizedBox(height: 12),
              Text('打不开这本书\n$_error', textAlign: TextAlign.center, style: TextStyle(color: theme.dim, height: 1.6)),
              const SizedBox(height: 20),
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('返回书架')),
            ],
          ),
        ),
      );

  Widget _readerView(ReaderTheme theme) {
    final media = MediaQuery.of(context);
    const hPad = 22.0;
    final double topPad = (media.padding.top > 12 ? media.padding.top : 24.0) + 18;
    const bottomPad = 40.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final contentSize = Size(
          constraints.maxWidth - hPad * 2,
          constraints.maxHeight - topPad - bottomPad - media.padding.bottom,
        );
        _ensurePages(contentSize);

        return Stack(
          children: [
            Positioned.fill(
              child: PageView.builder(
                key: ValueKey(_cacheKey),
                controller: _controller,
                itemCount: _pages.length,
                onPageChanged: _onPageChanged,
                physics: const PageScrollPhysics(),
                itemBuilder: (context, index) => GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapUp: (details) {
                    final width = constraints.maxWidth;
                    final x = details.globalPosition.dx;
                    if (_menuVisible) {
                      _setMenu(false);
                    } else if (x < width * 0.3) {
                      _turn(-1);
                    } else if (x > width * 0.7) {
                      _turn(1);
                    } else {
                      _setMenu(true);
                    }
                  },
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(hPad, topPad, hPad, bottomPad + media.padding.bottom),
                    child: Text(
                      _pages[index].text,
                      style: _settings.textStyle(),
                      textAlign: TextAlign.justify,
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: hPad,
              right: hPad,
              bottom: media.padding.bottom + 12,
              child: IgnorePointer(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _chapters.isEmpty ? '' : _chapters[_chapterIndex].title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: theme.dim.withValues(alpha: 0.85)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      _pages.isEmpty
                          ? ''
                          : '${(_pageIndex + 1).clamp(1, _pages.length)}/${_pages.length} · ${_bookPercent().toStringAsFixed(1)}%',
                      style: TextStyle(fontSize: 11, color: theme.dim.withValues(alpha: 0.85)),
                    ),
                  ],
                ),
              ),
            ),
            _topBar(theme, media),
            _bottomBar(theme, media),
          ],
        );
      },
    );
  }

  double _bookPercent() {
    if (_text.isEmpty || _chapters.isEmpty || _pages.isEmpty) return _book.percent;
    final chapter = _chapters[_chapterIndex];
    final page = _pages[_pageIndex.clamp(0, _pages.length - 1)];
    return ((chapter.start + page.start) / _text.length).clamp(0.0, 1.0);
  }

  Widget _topBar(ReaderTheme theme, MediaQueryData media) {
    return Align(
      alignment: Alignment.topCenter,
      child: IgnorePointer(
        ignoring: !_menuVisible,
        child: AnimatedSlide(
          offset: _menuVisible ? Offset.zero : const Offset(0, -1.1),
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _menuVisible ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: Material(
              color: theme.chrome,
              elevation: 3,
              child: Padding(
                padding: EdgeInsets.fromLTRB(4, media.padding.top + 4, 8, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(Icons.arrow_back, color: theme.chromeText, size: 22),
                    ),
                    const SizedBox(width: 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _book.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: theme.chromeText),
                          ),
                          if (_chapters.isNotEmpty)
                            Text(
                              _chapters[_chapterIndex].title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: theme.dim),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '搜索',
                      onPressed: _openSearch,
                      icon: Icon(Icons.search, color: theme.chromeText, size: 22),
                    ),
                    IconButton(
                      tooltip: '书签',
                      onPressed: _openBookmarks,
                      icon: Icon(Icons.bookmarks_outlined, color: theme.chromeText, size: 21),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _bottomBar(ReaderTheme theme, MediaQueryData media) {
    final progress = _pages.isEmpty ? 0.0 : (_pageIndex + 1) / _pages.length;
    return Align(
      alignment: Alignment.bottomCenter,
      child: IgnorePointer(
        ignoring: !_menuVisible,
        child: AnimatedSlide(
          offset: _menuVisible ? Offset.zero : const Offset(0, 1.1),
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          child: AnimatedOpacity(
            opacity: _menuVisible ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            child: Container(
              decoration: BoxDecoration(
                color: theme.chrome,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
                boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 18, offset: Offset(0, -4))],
              ),
              padding: EdgeInsets.fromLTRB(16, 8, 16, media.padding.bottom + 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 32,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: theme.dim.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  if (_settingsVisible) _settingsPanel(theme) else _progressRow(theme, progress),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      _barAction(theme, icon: Icons.toc, label: '目录', onTap: _openChapters),
                      _barAction(theme, icon: Icons.search, label: '搜索', onTap: _openSearch),
                      _barAction(
                        theme,
                        icon: Icons.text_fields,
                        label: '排版',
                        active: _settingsVisible,
                        onTap: () => setState(() => _settingsVisible = !_settingsVisible),
                      ),
                      _barAction(
                        theme,
                        icon: theme.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                        label: theme.isDark ? '日间' : '夜间',
                        onTap: () {
                          final dark = ReaderTheme.all.indexWhere((t) => t.isDark);
                          final light = ReaderTheme.all.indexWhere((t) => !t.isDark);
                          _settings.setTheme(theme.isDark ? light : dark);
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _progressRow(ReaderTheme theme, double progress) {
    return Row(
      children: [
        Text(
          _pages.isEmpty ? '' : '${(_pageIndex + 1).clamp(1, _pages.length)}/${_pages.length}',
          style: TextStyle(fontSize: 11, color: theme.dim),
        ),
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 2,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              activeTrackColor: theme.chromeText,
              inactiveTrackColor: theme.dim.withValues(alpha: 0.25),
              thumbColor: theme.chromeText,
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (v) {
                if (_pages.isEmpty) return;
                final target = ((_pages.length - 1) * v).round().clamp(0, _pages.length - 1);
                if (target != _pageIndex) _controller.jumpToPage(target);
              },
            ),
          ),
        ),
        Text(
          '${(this._bookPercent()).toStringAsFixed(1)}%',
          style: TextStyle(fontSize: 11, color: theme.dim),
        ),
      ],
    );
  }

  Widget _settingsPanel(ReaderTheme theme) {
    final labelStyle = TextStyle(fontSize: 12, color: theme.dim);
    final valueStyle = TextStyle(fontSize: 12, color: theme.chromeText, fontWeight: FontWeight.w600);
    final sliderTheme = SliderTheme.of(context).copyWith(
      trackHeight: 2,
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
      activeTrackColor: theme.chromeText,
      inactiveTrackColor: theme.dim.withValues(alpha: 0.25),
      thumbColor: theme.chromeText,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(width: 44, child: Text('字号', style: labelStyle)),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _settings.setFontSize(_settings.fontSize - 1),
              icon: Icon(Icons.remove, size: 18, color: theme.chromeText),
            ),
            Expanded(
              child: SliderTheme(
                data: sliderTheme,
                child: Slider(
                  value: _settings.fontSize,
                  min: 14,
                  max: 32,
                  divisions: 18,
                  onChanged: (v) => _settings.setFontSize(v),
                ),
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              onPressed: () => _settings.setFontSize(_settings.fontSize + 1),
              icon: Icon(Icons.add, size: 18, color: theme.chromeText),
            ),
            SizedBox(
              width: 26,
              child: Text(_settings.fontSize.round().toString(), style: valueStyle, textAlign: TextAlign.right),
            ),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 44, child: Text('行距', style: labelStyle)),
            Expanded(
              child: SliderTheme(
                data: sliderTheme,
                child: Slider(
                  value: _settings.lineHeight,
                  min: 1.3,
                  max: 2.4,
                  divisions: 22,
                  onChanged: (v) => _settings.setLineHeight(v),
                ),
              ),
            ),
            SizedBox(
              width: 26,
              child: Text(_settings.lineHeight.toStringAsFixed(1), style: valueStyle, textAlign: TextAlign.right),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Row(
          children: [
            SizedBox(width: 44, child: Text('主题', style: labelStyle)),
            Expanded(
              child: Row(
                children: [
                  for (var i = 0; i < ReaderTheme.all.length; i++)
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        _settings.setTheme(i);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        margin: const EdgeInsets.only(right: 12),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: ReaderTheme.all[i].background,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: i == _settings.themeIndex ? theme.chromeText : theme.dim.withValues(alpha: 0.35),
                            width: i == _settings.themeIndex ? 2 : 1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            SizedBox(width: 44, child: Text('字体', style: labelStyle)),
            Expanded(
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'system', label: Text('系统')),
                  ButtonSegment(value: 'serif', label: Text('宋体')),
                  ButtonSegment(value: 'sans', label: Text('黑体')),
                ],
                selected: {_settings.fontFamily},
                onSelectionChanged: (s) => _settings.setFontFamily(s.first),
                showSelectedIcon: false,
                style: ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12, color: theme.chromeText)),
                  side: WidgetStatePropertyAll(BorderSide(color: theme.dim.withValues(alpha: 0.3))),
                  backgroundColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) return theme.dim.withValues(alpha: 0.22);
                    return Colors.transparent;
                  }),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _barAction(
    ReaderTheme theme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = false,
  }) {
    final color = active ? theme.chromeText : theme.dim;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: color)),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- 目录 / 搜索 / 书签

  Future<void> _openChapters() async {
    final index = await showChapterSheet(
      context,
      chapters: _chapters,
      current: _chapterIndex,
      theme: _settings.theme,
    );
    if (index != null && mounted) {
      setState(() => _menuVisible = false);
      _gotoChapter(index);
    }
  }

  Future<void> _openSearch() async {
    final hit = await showSearchSheet(
      context,
      text: _text,
      chapters: _chapters,
      theme: _settings.theme,
    );
    if (hit != null && mounted) {
      setState(() {
        _menuVisible = false;
        _settingsVisible = false;
      });
      _applyPosition(hit.chapter, hit.offset);
    }
  }

  Future<void> _openBookmarks() async {
    final chapter = _chapters[_chapterIndex];
    final offset = _pages.isEmpty ? _charOffset : _pages[_pageIndex.clamp(0, _pages.length - 1)].start;
    final marked = Library.instance.hasBookmarkAt(_book, _chapterIndex, offset);
    final result = await showBookmarkSheet(
      context,
      bookmarks: List<Bookmark>.unmodifiable(_book.bookmarks),
      theme: _settings.theme,
      currentMarked: marked,
    );
    if (!mounted || result == null) return;
    if (result.add) {
      await Library.instance.toggleBookmark(
        _book,
        chapter: _chapterIndex,
        offset: offset,
        title: chapter.title,
      );
      if (mounted) {
        setState(() {});
        _toast(marked ? '已移除书签' : '已添加书签');
      }
    } else if (result.remove != null) {
      await Library.instance.removeBookmark(_book, result.remove!);
      if (mounted) setState(() {});
    } else if (result.jump != null) {
      setState(() {
        _menuVisible = false;
        _settingsVisible = false;
      });
      _applyPosition(result.jump!.chapter, result.jump!.offset);
    }
  }
}
