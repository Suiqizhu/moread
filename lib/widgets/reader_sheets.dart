import 'dart:async';
import 'dart:isolate';

import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/book_search.dart';
import '../theme/reader_theme.dart';

/// 书签面板的返回值：跳转 / 添加当前页 / 删除某条。
class BookmarkSheetResult {
  const BookmarkSheetResult.jump(Bookmark this.jump)
      : add = false,
        remove = null;

  const BookmarkSheetResult.add()
      : jump = null,
        add = true,
        remove = null;

  const BookmarkSheetResult.remove(Bookmark this.remove)
      : jump = null,
        add = false;

  final Bookmark? jump;
  final bool add;
  final Bookmark? remove;
}

Widget _handle(ReaderTheme theme) => Container(
      width: 32,
      height: 4,
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      decoration: BoxDecoration(
        color: theme.dim.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    );

Widget _header(ReaderTheme theme, String title, String? trailing) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: theme.chromeText),
            ),
          ),
          if (trailing != null) Text(trailing, style: TextStyle(fontSize: 12, color: theme.dim)),
        ],
      ),
    );

ShapeBorder get _sheetShape => const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    );

/// 目录：定位到当前章节，点击跳转。
Future<int?> showChapterSheet(
  BuildContext context, {
  required List<Chapter> chapters,
  required int current,
  required ReaderTheme theme,
}) {
  return showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.chrome,
    shape: _sheetShape,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.82,
      child: _ChapterList(chapters: chapters, current: current, theme: theme),
    ),
  );
}

class _ChapterList extends StatefulWidget {
  const _ChapterList({required this.chapters, required this.current, required this.theme});

  final List<Chapter> chapters;
  final int current;
  final ReaderTheme theme;

  @override
  State<_ChapterList> createState() => _ChapterListState();
}

class _ChapterListState extends State<_ChapterList> {
  late final ScrollController _controller;

  @override
  void initState() {
    super.initState();
    // 打开就停在当前章节附近，不用手动翻几百章。
    final offset = (widget.current * 56.0 - 160).clamp(0.0, double.infinity);
    _controller = ScrollController(initialScrollOffset: offset);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      children: [
        _handle(theme),
        _header(theme, '目录', '共 ${widget.chapters.length} 章'),
        Divider(height: 1, color: theme.dim.withValues(alpha: 0.2)),
        Expanded(
          child: ListView.builder(
            controller: _controller,
            itemExtent: 56,
            itemCount: widget.chapters.length,
            itemBuilder: (context, index) {
              final isCurrent = index == widget.current;
              return InkWell(
                onTap: () => Navigator.of(context).pop(index),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.chapters[index].title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: isCurrent ? const Color(0xFF4E9A7C) : theme.chromeText,
                            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                          ),
                        ),
                      ),
                      if (isCurrent)
                        const Icon(Icons.volume_up_rounded, size: 16, color: Color(0xFF4E9A7C)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 全文搜索：输入后 250ms 防抖，在后台 isolate 里扫。
Future<SearchHit?> showSearchSheet(
  BuildContext context, {
  required String text,
  required List<Chapter> chapters,
  required ReaderTheme theme,
}) {
  return showModalBottomSheet<SearchHit>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.chrome,
    shape: _sheetShape,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.86,
      child: _SearchSheet(text: text, chapters: chapters, theme: theme),
    ),
  );
}

class _SearchSheet extends StatefulWidget {
  const _SearchSheet({required this.text, required this.chapters, required this.theme});

  final String text;
  final List<Chapter> chapters;
  final ReaderTheme theme;

  @override
  State<_SearchSheet> createState() => _SearchSheetState();
}

class _SearchSheetState extends State<_SearchSheet> {
  final TextEditingController _controller = TextEditingController();
  Timer? _debounce;
  List<SearchHit> _hits = const [];
  bool _searching = false;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _hits = const [];
        _searching = false;
      });
      return;
    }
    setState(() => _searching = true);
    _debounce = Timer(const Duration(milliseconds: 250), () => _run(value));
  }

  Future<void> _run(String value) async {
    final seq = ++_seq;
    final text = widget.text;
    final chapters = widget.chapters;
    final hits = await Isolate.run(() => BookSearch.find(text, chapters, value));
    if (!mounted || seq != _seq) return;
    setState(() {
      _hits = hits;
      _searching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return Column(
      children: [
        _handle(theme),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: TextField(
            controller: _controller,
            autofocus: true,
            onChanged: _onChanged,
            style: TextStyle(color: theme.chromeText, fontSize: 15),
            decoration: InputDecoration(
              hintText: '在全书里搜索',
              hintStyle: TextStyle(color: theme.dim, fontSize: 14),
              prefixIcon: Icon(Icons.search, color: theme.dim, size: 20),
              suffixIcon: _controller.text.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(Icons.close, size: 18, color: theme.dim),
                      onPressed: () {
                        _controller.clear();
                        _onChanged('');
                      },
                    ),
              filled: true,
              fillColor: theme.dim.withValues(alpha: 0.1),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
          ),
        ),
        if (_searching)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2, color: theme.chromeText, backgroundColor: theme.dim.withValues(alpha: 0.15)),
          ),
        if (!_searching && _controller.text.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                _hits.isEmpty ? '没有找到' : '找到 ${_hits.length} 处',
                style: TextStyle(fontSize: 12, color: theme.dim),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: _hits.length,
            itemBuilder: (context, index) {
              final hit = _hits[index];
              return ListTile(
                dense: true,
                title: Text(
                  hit.chapterTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: theme.dim),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(
                    _highlight(hit.snippet, _controller.text.trim(), theme),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                onTap: () => Navigator.of(context).pop(hit),
              );
            },
          ),
        ),
      ],
    );
  }

  TextSpan _highlight(String snippet, String query, ReaderTheme theme) {
    final base = TextStyle(fontSize: 13.5, height: 1.45, color: theme.chromeText);
    if (query.isEmpty) return TextSpan(text: snippet, style: base);
    final lower = snippet.toLowerCase();
    final q = query.toLowerCase();
    final index = lower.indexOf(q);
    if (index < 0) return TextSpan(text: snippet, style: base);
    return TextSpan(
      style: base,
      children: [
        TextSpan(text: snippet.substring(0, index)),
        TextSpan(
          text: snippet.substring(index, index + q.length),
          style: const TextStyle(color: Color(0xFF4E9A7C), fontWeight: FontWeight.w700),
        ),
        TextSpan(text: snippet.substring(index + q.length)),
      ],
    );
  }
}

/// 书签列表 + 添加当前页。
Future<BookmarkSheetResult?> showBookmarkSheet(
  BuildContext context, {
  required List<Bookmark> bookmarks,
  required ReaderTheme theme,
  required bool currentMarked,
}) {
  return showModalBottomSheet<BookmarkSheetResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: theme.chrome,
    shape: _sheetShape,
    builder: (context) => FractionallySizedBox(
      heightFactor: 0.62,
      child: Column(
        children: [
          _handle(theme),
          _header(theme, '书签', '${bookmarks.length} 条'),
          Divider(height: 1, color: theme.dim.withValues(alpha: 0.2)),
          ListTile(
            leading: Icon(currentMarked ? Icons.bookmark_remove_outlined : Icons.bookmark_add_outlined,
                color: theme.chromeText),
            title: Text(currentMarked ? '移除本页书签' : '添加当前页书签',
                style: TextStyle(fontSize: 14, color: theme.chromeText)),
            onTap: () => Navigator.of(context).pop(const BookmarkSheetResult.add()),
          ),
          Divider(height: 1, color: theme.dim.withValues(alpha: 0.2)),
          Expanded(
            child: bookmarks.isEmpty
                ? Center(
                    child: Text('还没有书签', style: TextStyle(fontSize: 13, color: theme.dim)),
                  )
                : ListView.builder(
                    itemCount: bookmarks.length,
                    itemBuilder: (context, index) {
                      final b = bookmarks[bookmarks.length - 1 - index];
                      return ListTile(
                        leading: Icon(Icons.bookmark, size: 18, color: theme.dim),
                        title: Text(
                          b.title.isEmpty ? '未命名位置' : b.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 14, color: theme.chromeText),
                        ),
                        subtitle: Text(
                          '第 ${b.chapter + 1} 章',
                          style: TextStyle(fontSize: 11, color: theme.dim),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.close, size: 16, color: theme.dim),
                          onPressed: () => Navigator.of(context).pop(BookmarkSheetResult.remove(b)),
                        ),
                        onTap: () => Navigator.of(context).pop(BookmarkSheetResult.jump(b)),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}
