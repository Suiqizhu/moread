// 纯 Dart 自测：不依赖 Flutter，可直接 `dart run tool/selftest.dart`。
import 'dart:io';
import 'dart:typed_data';

import 'package:moread/models/book.dart';
import 'package:moread/services/book_search.dart';
import 'package:moread/services/parser.dart';

int passed = 0;
int failed = 0;

void check(bool ok, String name, [String? detail]) {
  if (ok) {
    passed++;
    stdout.writeln('  ok   $name');
  } else {
    failed++;
    stdout.writeln('  FAIL $name${detail == null ? '' : ' → $detail'}');
  }
}

void main() {
  final dir = Directory('test/fixtures');

  stdout.writeln('TXT (UTF-8)');
  final txt = File('${dir.path}/斗破苍穹 作者：天蚕土豆.txt').readAsBytesSync();
  final b1 = BookParser.parse(txt, '斗破苍穹 作者：天蚕土豆.txt');
  check(b1.title == '斗破苍穹', '书名从文件名拆出', b1.title);
  check(b1.author == '天蚕土豆', '作者从文件名拆出', b1.author);
  check(b1.chapters.length == 3, '识别 3 章', '${b1.chapters.length}');
  check(b1.chapters.first.title.contains('第一章'), '第一章标题', b1.chapters.first.title);
  check(b1.text.substring(b1.chapters[1].start, b1.chapters[1].end).contains('斗气大陆'), '章节区间正确');
  check(b1.chapters.last.end == b1.text.length, '最后一章到文末');
  check(b1.cover == null, 'TXT 无封面');

  stdout.writeln('TXT (GBK)');
  final gbkBytes = File('${dir.path}/gbk小说.txt').readAsBytesSync();
  final b2 = BookParser.parse(gbkBytes, 'gbk小说.txt');
  check(b2.text.contains('这是一本GBK编码的小说'), 'GBK 正确解码');
  check(b2.chapters.length == 2, 'GBK 文件识别 2 章', '${b2.chapters.length}');

  stdout.writeln('EPUB');
  final epub = BookParser.parseEpub(File('${dir.path}/测试书.epub').readAsBytesSync());
  check(epub.title == '测试书', 'OPF 书名', epub.title);
  check(epub.author == '测试作者', 'OPF 作者', epub.author);
  check(epub.chapters.length == 2, 'spine 两章', '${epub.chapters.length}');
  check(epub.chapters.first.title == '第一章 启程', '章节标题取 h1', epub.chapters.first.title);
  check(epub.text.contains('山道上起了雾'), '正文提取');
  check(epub.text.contains('“往北走三天，就到了。”'), 'br 转换与全角引号');
  check(epub.text.contains('& 就这样出发了…'), '实体解码', epub.text.split('\n').last);
  check(!epub.text.contains('color:red'), 'style 已剔除');
  check(epub.cover != null && epub.cover!.length > 4 && epub.cover![0] == 0xFF && epub.cover![1] == 0xD8, '封面字节');
  check(BookParser.guessImageExt(epub.cover!) == 'jpg', '封面类型识别');

  stdout.writeln('边界');
  final flat = BookParser.parse(Uint8List.fromList('没有章节标记的纯文本。'.codeUnits), '随笔.txt');
  check(flat.chapters.length == 1 && flat.chapters.first.title == '正文', '无章节时单章');
  check(BookParser.splitChapters('第三回合 他输了。\n很惨。').length == 1, '避免「第三回合」误判');
  check(BookParser.decodeEntities('&amp;&#20320;&#x4f60;') == '&你你', '实体与数字引用');
  check(BookParser.splitName('三体').$1 == '三体', '无作者的文件名');
  check(BookParser.htmlToText('<p>甲<br>乙</p>') == '甲\n乙', 'p/br 换行');
  final empty = BookParser.parse(Uint8List.fromList([]), 'empty.txt');
  check(empty.text.isEmpty, '空文件不崩');
  final book = Book(id: '1', title: '甲', author: '乙', path: '/tmp/x.txt', chapterCount: 3, percent: 0.5);
  final restored = Book.fromJson(book.toJson());
  check(restored.title == '甲' && restored.author == '乙' && restored.chapterCount == 3 && restored.percent == 0.5,
      'Book JSON 往返');

  stdout.writeln('全文搜索');
  final textBook = b1;
  final hits = BookSearch.find(textBook.text, textBook.chapters, '斗气');
  check(hits.length >= 2, '找到多处命中', '${hits.length}');
  check(hits.first.chapter == 0 || hits.first.chapter == 1, '命中带章节号');
  check(hits.first.snippet.contains('斗气'), '摘要包含关键词', hits.first.snippet);
  check(BookSearch.find(textBook.text, textBook.chapters, '不存在的词').isEmpty, '无结果返回空');
  check(BookSearch.find(textBook.text, textBook.chapters, '').isEmpty, '空查询返回空');
  final limited = BookSearch.find(textBook.text, textBook.chapters, '的', limit: 3);
  check(limited.length <= 3, 'limit 生效', '${limited.length}');
  final hitInSecond = BookSearch.find(textBook.text, textBook.chapters, '斗气大陆').first;
  final chapterText = textBook.text.substring(
      textBook.chapters[hitInSecond.chapter].start, textBook.chapters[hitInSecond.chapter].end);
  check(chapterText.startsWith(chapterText.substring(0, hitInSecond.offset)) &&
      chapterText.substring(hitInSecond.offset).startsWith('斗气大陆'), '偏移可定位到正文');

  stdout.writeln('书签');
  final withMarks = Book.fromJson(Book(
    id: '2',
    title: '带书签',
    path: '/tmp/y.txt',
    bookmarks: [Bookmark(chapter: 1, offset: 120, title: '第二章', createdAt: DateTime(2026, 1, 2))],
  ).toJson());
  check(withMarks.bookmarks.length == 1, '书签能序列化');
  check(withMarks.bookmarks.first.offset == 120 && withMarks.bookmarks.first.chapter == 1, '书签字段完整');
  final noMarks = Book.fromJson({'id': '3', 'title': '旧数据', 'path': '/tmp/z.txt'});
  check(noMarks.bookmarks.isEmpty, '旧书库数据兼容');

  stdout.writeln('\n$passed passed, $failed failed');
  if (failed > 0) exitCode = 1;
}
