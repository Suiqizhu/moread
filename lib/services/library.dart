import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';

/// 本地书库：索引 + 正文 + 章节表都放在应用私有目录，卸载即清理。
class Library extends ChangeNotifier {
  Library._();

  static final Library instance = Library._();

  Directory? _root;
  bool _ready = false;
  final List<Book> _books = [];

  bool get ready => _ready;
  List<Book> get books => List.unmodifiable(_books);

  /// 已读书籍在前，其余按导入时间倒序。
  List<Book> get shelf {
    final list = [..._books];
    list.sort((a, b) {
      final la = a.lastReadAt?.millisecondsSinceEpoch ?? 0;
      final lb = b.lastReadAt?.millisecondsSinceEpoch ?? 0;
      if (la != lb) return lb.compareTo(la);
      final aa = a.addedAt?.millisecondsSinceEpoch ?? 0;
      final ab = b.addedAt?.millisecondsSinceEpoch ?? 0;
      return ab.compareTo(aa);
    });
    return list;
  }

  Future<Directory> get root async {
    if (_root != null) return _root!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/moread');
    await dir.create(recursive: true);
    _root = dir;
    return dir;
  }

  Future<File> _indexFile() async => File('${(await root).path}/library.json');

  Future<void> init() async {
    if (_ready) return;
    await root;
    final f = await _indexFile();
    if (await f.exists()) {
      try {
        final data = jsonDecode(await f.readAsString()) as List<dynamic>;
        _books
          ..clear()
          ..addAll(data.map((e) => Book.fromJson(e as Map<String, dynamic>)));
      } catch (_) {
        // 索引损坏就当成空书库，不阻断启动。
      }
    }
    // 清理已经不存在的条目（正文文件被手动删掉的情况）。
    _books.removeWhere((b) => !File(b.path).existsSync());
    _ready = true;
    notifyListeners();
  }

  Future<void> saveIndex() async {
    final f = await _indexFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_books.map((b) => b.toJson()).toList()), flush: true);
    await tmp.rename(f.path);
  }

  Future<Directory> booksDir() async {
    final d = Directory('${(await root).path}/books');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<Directory> coversDir() async {
    final d = Directory('${(await root).path}/covers');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  Future<File> chaptersFile(String id) async => File('${(await booksDir()).path}/$id.chapters.json');

  Future<List<Chapter>> loadChapters(Book book) async {
    final f = await chaptersFile(book.id);
    if (!await f.exists()) {
      return [Chapter(title: '正文', start: 0, end: book.charCount)];
    }
    return decodeChapters(await f.readAsString());
  }

  Future<void> saveChapters(String id, List<Chapter> chapters) async {
    final f = await chaptersFile(id);
    await f.writeAsString(encodeChapters(chapters), flush: true);
  }

  Future<String> readText(Book book) => File(book.path).readAsString();

  Future<void> add(Book book) async {
    _books.removeWhere((b) => b.id == book.id);
    _books.add(book);
    notifyListeners();
    await saveIndex();
  }

  Future<void> remove(Book book) async {
    _books.removeWhere((b) => b.id == book.id);
    notifyListeners();
    for (final p in [book.path, (await chaptersFile(book.id)).path, if (book.coverPath != null) book.coverPath!]) {
      final f = File(p);
      if (await f.exists()) {
        try {
          await f.delete();
        } catch (_) {}
      }
    }
    await saveIndex();
  }

  /// 保存阅读进度（高频调用，调用方负责节流）。
  Future<void> updateProgress(Book book, {required int chapterIndex, required int charOffset, required double percent}) async {
    book
      ..chapterIndex = chapterIndex
      ..charOffset = charOffset
      ..percent = percent.clamp(0.0, 1.0)
      ..lastReadAt = DateTime.now();
    if (book.percent >= 0.999) book.finished = true;
    // 先落盘再通知，避免在页面销毁/构建过程中触发书架重建。
    await saveIndex();
    notifyListeners();
  }
}
