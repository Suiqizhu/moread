import 'package:flutter/painting.dart';

/// 一页正文及其在章节文本里的字符区间。
class PageChunk {
  const PageChunk(this.text, this.start, this.end);

  final String text;
  final int start;
  final int end;
}

/// 用 TextPainter 的真实排版结果切页，保证跟屏幕上的 Text 渲染一致。
class Paginator {
  /// 每次只测量这么多字符，避免整章反复排版造成卡顿。
  static const int _window = 8000;

  static List<PageChunk> paginate({
    required String text,
    required TextStyle style,
    required Size size,
  }) {
    if (text.isEmpty) return const [PageChunk('', 0, 0)];
    final width = size.width <= 0 ? 320.0 : size.width;
    final height = size.height <= 0 ? 480.0 : size.height;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    );

    final pages = <PageChunk>[];
    var start = 0;
    while (start < text.length) {
      final end = (start + _window).clamp(0, text.length);
      final chunk = text.substring(start, end);
      painter.text = TextSpan(text: chunk, style: style);
      painter.layout(maxWidth: width);

      var cut = end;
      if (painter.height > height + 0.5) {
        // 找出最后一行的下边界，从下一行行首切开，避免半个字被截断。
        double y = 0;
        var fitted = 0;
        for (final line in painter.computeLineMetrics()) {
          if (y + line.height > height + 0.5) break;
          y += line.height;
          fitted++;
        }
        if (fitted == 0) {
          cut = start + 1;
        } else {
          final pos = painter.getPositionForOffset(Offset(0, y + 1));
          cut = (start + pos.offset).clamp(start + 1, end);
        }
      }

      pages.add(PageChunk(text.substring(start, cut), start, cut));
      start = cut;
    }
    if (pages.isEmpty) pages.add(const PageChunk('', 0, 0));
    return pages;
  }

  static int pageOfOffset(List<PageChunk> pages, int offset) {
    for (var i = 0; i < pages.length; i++) {
      if (offset < pages[i].end) return i;
    }
    return pages.length - 1;
  }
}
