import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/library.dart';
import '../services/pagination.dart';
import '../theme/reader_theme.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.book});

  final Book book;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> with WidgetsBindingObserver {
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
    _settings.addListener(_onSettingsChanged);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _saveTimer?.cancel();
    _saveNow();
    _settings.removeListener(_onSettingsChanged);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _saveNow();
    }
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
      if (old.hasClients) return;
      old.dispose();
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
    setState(() {
      _chapterIndex = index;
      _charOffset = toEnd ? (chapter.end - chapter.start) : 0;
      _cacheKey = '';
      if (_menuVisible) _settingsVisible = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _scheduleSave();
    });
  }

  void _onPageChanged(int index) {
    setState(() {
      _pageIndex = index;
      if (index >= 0 && index < _pages.length) _charOffset = _pages[index].start;
    });
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), _saveNow);
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating, duration: const Duration(seconds: 1)),
    );
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
                      _pages.isEmpty ? '1/1' : '${(_pageIndex + 1).clamp(1, _pages.length)}/${_pages.length}',
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

  void _setMenu(bool visible) {
    setState(() {
      _menuVisible = visible;
      if (!visible) _settingsVisible = false;
    });
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
            child: Container(
              width: double.infinity,
              color: theme.chrome,
              padding: EdgeInsets.fromLTRB(4, media.padding.top + 4, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.arrow_back, color: theme.chromeText, size: 22),
                  ),
                  const SizedBox(width: 4),
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
                ],
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
              width: double.infinity,
              color: theme.chrome,
              padding: EdgeInsets.fromLTRB(16, 10, 16, media.padding.bottom + 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_settingsVisible) _settingsPanel(theme) else _progressRow(theme, progress),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      _barAction(
                        theme,
                        icon: Icons.toc,
                        label: '目录',
                        onTap: () {
                          _setMenu(false);
                          _openChapters(theme);
                        },
                      ),
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
                          final darkIndex = ReaderTheme.all.indexWhere((t) => t.isDark);
                          final lightIndex = ReaderTheme.all.indexWhere((t) => !t.isDark);
                          _settings.setTheme(theme.isDark ? lightIndex : darkIndex);
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
          _pages.isEmpty ? '1' : '${(_pageIndex + 1).clamp(1, _pages.length)}',
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
          '${_pages.length}',
          style: TextStyle(fontSize: 11, color: theme.dim),
        ),
      ],
    );
  }

  Widget _settingsPanel(ReaderTheme theme) {
    final labelStyle = TextStyle(fontSize: 12, color: theme.dim);
    final valueStyle = TextStyle(fontSize: 12, color: theme.chromeText, fontWeight: FontWeight.w600);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            SizedBox(width: 44, child: Text('字号', style: labelStyle)),
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
                  value: _settings.fontSize,
                  min: 14,
                  max: 32,
                  divisions: 36,
                  onChanged: (v) => _settings.setFontSize(v),
                ),
              ),
            ),
            SizedBox(width: 26, child: Text(_settings.fontSize.round().toString(), style: valueStyle, textAlign: TextAlign.right)),
          ],
        ),
        Row(
          children: [
            SizedBox(width: 44, child: Text('行距', style: labelStyle)),
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
                      onTap: () => _settings.setTheme(i),
                      child: Container(
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
                        child: i == ReaderTheme.all.length - 1
                            ? Icon(Icons.dark_mode, size: 12, color: ReaderTheme.all[i].text)
                            : null,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            SizedBox(width: 44, child: Text('字体', style: labelStyle)),
            Expanded(
              child: Wrap(
                spacing: 8,
                children: [
                  for (final f in const [
                    ('system', '系统'),
                    ('serif', '宋体'),
                    ('sans', '黑体'),
                  ])
                    ChoiceChip(
                      label: Text(f.$2, style: TextStyle(fontSize: 11, color: theme.chromeText)),
                      selected: _settings.fontFamily == f.$1,
                      onSelected: (_) => _settings.setFontFamily(f.$1),
                      visualDensity: VisualDensity.compact,
                      selectedColor: theme.dim.withValues(alpha: 0.25),
                      backgroundColor: Colors.transparent,
                      side: BorderSide(color: theme.dim.withValues(alpha: 0.3)),
                      showCheckmark: false,
                    ),
                ],
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
        borderRadius: BorderRadius.circular(8),
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

  // ---------------------------------------------------------------- 目录

  void _openChapters(ReaderTheme theme) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.chrome,
      isScrollControlled: true,
      showDragHandle: false,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (sheetContext) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          minChildSize: 0.4,
          maxChildSize: 0.95,
          builder: (context, scrollController) {
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '目录 · ${_chapters.length} 章',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: theme.chromeText),
                        ),
                      ),
                      Text(
                        '${(_book.percent * 100).toStringAsFixed(1)}%',
                        style: TextStyle(fontSize: 12, color: theme.dim),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: theme.dim.withValues(alpha: 0.2)),
                Expanded(
                  child: ListView.builder(
                    controller: scrollController,
                    itemCount: _chapters.length,
                    itemBuilder: (context, index) {
                      final current = index == _chapterIndex;
                      return ListTile(
                        dense: true,
                        title: Text(
                          _chapters[index].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: current ? const Color(0xFF5E8F76) : theme.chromeText,
                            fontWeight: current ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                        trailing: current
                            ? const Icon(Icons.play_arrow_rounded, size: 16, color: Color(0xFF5E8F76))
                            : null,
                        onTap: () {
                          Navigator.of(sheetContext).pop();
                          _gotoChapter(index);
                        },
                      );
                    },
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
