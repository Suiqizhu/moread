import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:moread/models/book.dart';
import 'package:moread/services/pagination.dart';

void main() {
  testWidgets('Paginator 切页不丢字、不越界', (tester) async {
    final text = List.generate(60, (i) => '第 $i 段：${'墨读' * 20}').join('\n\n');
    final pages = Paginator.paginate(
      text: text,
      style: const TextStyle(fontSize: 16, height: 1.8),
      size: const Size(320, 400),
    );
    expect(pages.length, greaterThan(1));
    expect(pages.map((p) => p.text).join(), text);
    expect(pages.first.start, 0);
    expect(pages.last.end, text.length);
    for (var i = 1; i < pages.length; i++) {
      expect(pages[i].start, pages[i - 1].end);
    }
  });

  testWidgets('PageChunk 的 offset 能定位回页码', (tester) async {
    final text = List.generate(30, (i) => '段落 $i ${'字' * 40}').join('\n');
    final pages = Paginator.paginate(
      text: text,
      style: const TextStyle(fontSize: 18, height: 1.6),
      size: const Size(300, 300),
    );
    expect(Paginator.pageOfOffset(pages, 0), 0);
    expect(Paginator.pageOfOffset(pages, text.length), pages.length - 1);
    for (var i = 0; i < pages.length; i++) {
      expect(Paginator.pageOfOffset(pages, pages[i].start), i);
    }
  });

  test('Book 序列化往返', () {
    final book = Book(
      id: 'abc',
      title: '测试书',
      author: '作者',
      path: '/tmp/a.txt',
      charCount: 1234,
      chapterCount: 12,
      percent: 0.42,
      lastReadAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
    );
    final restored = Book.fromJson(book.toJson());
    expect(restored.title, '测试书');
    expect(restored.author, '作者');
    expect(restored.chapterCount, 12);
    expect(restored.percent, 0.42);
    expect(restored.lastReadAt!.millisecondsSinceEpoch, 1700000000000);
  });
}
