import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/book.dart';
import 'library.dart';
import 'parser.dart';

/// 导入失败时抛出，界面直接展示 message。
class ImportException implements Exception {
  ImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

class Importer {
  /// 书名生成的封面配色循环。
  static const int accentCount = 6;

  /// 从任意可读路径导入一本书。
  static Future<Book> importPath(String path, {String? displayName}) async {
    final file = File(path);
    if (!await file.exists()) throw ImportException('文件不存在：$path');
    final bytes = await file.readAsBytes();
    return importBytes(bytes, displayName ?? path.split('/').last);
  }

  /// 直接导入内存里的文件内容（系统选择器只给 URI 时走这里）。
  ///
  /// 解析放到独立 isolate：几十 MB 的 EPUB 也不会卡住界面。
  static Future<Book> importBytes(Uint8List bytes, String name) async {
    if (bytes.isEmpty) throw ImportException('文件是空的');

    final ParsedBook parsed;
    try {
      parsed = await Isolate.run(() => BookParser.parse(bytes, name));
    } on FormatException catch (e) {
      throw ImportException(e.message);
    } on RemoteError catch (e) {
      throw ImportException('$e');
    }

    final text = parsed.text;
    if (text.trim().isEmpty) throw ImportException('没有解析到正文内容');

    final library = Library.instance;
    final id = '${DateTime.now().microsecondsSinceEpoch}';
    final dir = await library.booksDir();
    final textFile = File('${dir.path}/$id.txt');
    await textFile.writeAsString(text, flush: true);

    String? coverPath;
    final cover = parsed.cover;
    if (cover != null && cover.isNotEmpty) {
      final covers = await library.coversDir();
      final cf = File('${covers.path}/$id.${BookParser.guessImageExt(cover)}');
      await cf.writeAsBytes(cover, flush: true);
      coverPath = cf.path;
    }

    final title = parsed.title.trim();
    final book = Book(
      id: id,
      title: title.isEmpty ? _fallbackTitle(name) : title,
      author: parsed.author.trim(),
      path: textFile.path,
      charCount: text.length,
      chapterCount: parsed.chapters.length,
      addedAt: DateTime.now(),
      coverPath: coverPath,
      accentIndex: (title.isEmpty ? name : title).hashCode.abs() % accentCount,
    );
    await library.saveChapters(id, parsed.chapters);
    await library.add(book);
    return book;
  }

  static String _fallbackTitle(String fileName) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return base.trim().isEmpty ? '未命名' : base.trim();
  }
}
