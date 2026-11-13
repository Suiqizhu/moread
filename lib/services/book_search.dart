import '../models/book.dart';

/// 全文搜索的一条命中。
class SearchHit {
  const SearchHit({
    required this.chapter,
    required this.offset,
    required this.snippet,
    required this.chapterTitle,
  });

  final int chapter;

  /// 命中位置在章节内的字符偏移，可直接喂给阅读器跳转。
  final int offset;
  final String snippet;
  final String chapterTitle;
}

/// 纯 Dart 的全文搜索，方便单测，也不占 UI 线程太久（一次扫描几 MB 是毫秒级）。
class BookSearch {
  static List<SearchHit> find(
    String text,
    List<Chapter> chapters,
    String query, {
    int limit = 200,
  }) {
    final q = query.trim();
    if (q.isEmpty || text.isEmpty) return const [];
    final needle = q.toLowerCase();
    final hits = <SearchHit>[];

    for (var ci = 0; ci < chapters.length && hits.length < limit; ci++) {
      final chapter = chapters[ci];
      final start = chapter.start.clamp(0, text.length);
      final end = chapter.end.clamp(0, text.length);
      if (end <= start) continue;
      final body = text.substring(start, end);
      final haystack = body.toLowerCase();

      var from = 0;
      while (hits.length < limit) {
        final index = haystack.indexOf(needle, from);
        if (index < 0) break;
        hits.add(SearchHit(
          chapter: ci,
          offset: index,
          chapterTitle: chapter.title,
          snippet: _snippet(body, index, q.length),
        ));
        from = index + q.length;
      }
    }
    return hits;
  }

  static String _snippet(String body, int index, int length) {
    const before = 18;
    const after = 34;
    var start = index - before;
    var end = index + length + after;
    if (start < 0) start = 0;
    if (end > body.length) end = body.length;
    var s = body.substring(start, end);
    s = s.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (start > 0) s = '…$s';
    if (end < body.length) s = '$s…';
    return s;
  }
}
