import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/book.dart';

/// 本地书库：索引 + 正文 + 章节表都放在应用私有目录，卸载即清理。
///
/// 性能约定：[updateProgress] 是翻页热路径，只改内存并标脏，由定时器合并写盘，
/// 也不会 notifyListeners（否则书架会在阅读时不停重建）。
class Library extends ChangeNotifier {
  Library._();

  static final Library instance = Library._();

  Directory? _root;
  bool _ready = false;
  final List<Book> _books = [];

  bool _dirty = false;
  Timer? _flushTimer;
  Future<void>? _flushing;

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

  Book? get lastRead {
    Book? result;
    var best = 0;
    for (final b in _books) {
      final t = b.lastReadAt?.millisecondsSinceEpoch ?? 0;
      if (t > best) {
        best = t;
        result = b;
      }
    }
    return result;
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
    // 串行化写盘，避免两个写入交错覆盖。
    while (_flushing != null) {
      await _flushing;
    }
    final future = _writeIndex();
    _flushing = future;
    try {
      await future;
    } finally {
      _flushing = null;
    }
  }

  Future<void> _writeIndex() async {
    final f = await _indexFile();
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(_books.map((b) => b.toJson()).toList()), flush: true);
    await tmp.rename(f.path);
    _dirty = false;
  }

  /// 合并写盘：最多 3 秒落一次。
  void _markDirty() {
    _dirty = true;
    _flushTimer ??= Timer(const Duration(seconds: 3), () {
      _flushTimer = null;
      if (_dirty) flush();
    });
  }

  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (!_dirty) return;
    await saveIndex();
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

  /// 翻页时调用：只改内存，不通知界面。
  void updateProgress(
    Book book, {
    required int chapterIndex,
    required int charOffset,
    required double percent,
  }) {
    book
      ..chapterIndex = chapterIndex
      ..charOffset = charOffset
      ..percent = percent.clamp(0.0, 1.0)
      ..lastReadAt = DateTime.now();
    if (book.percent >= 0.999 && !book.finished) book.finished = true;
    _markDirty();
  }

  Future<void> toggleBookmark(Book book, {required int chapter, required int offset, required String title}) async {
    final existing = book.bookmarks.indexWhere((b) => b.chapter == chapter && (b.offset - offset).abs() < 1);
    if (existing >= 0) {
      book.bookmarks.removeAt(existing);
    } else {
      book.bookmarks.add(Bookmark(chapter: chapter, offset: offset, title: title, createdAt: DateTime.now()));
    }
    notifyListeners();
    await saveIndex();
  }

  bool hasBookmarkAt(Book book, int chapter, int offset) =>
      book.bookmarks.any((b) => b.chapter == chapter && (b.offset - offset).abs() < 1);

  Future<void> removeBookmark(Book book, Bookmark bookmark) async {
    book.bookmarks.remove(bookmark);
    notifyListeners();
    await saveIndex();
  }
}
