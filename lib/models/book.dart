import 'dart:convert';

/// 一本书里的一个章节。[start] / [end] 是该章节在全书纯文本中的字符区间。
class Chapter {
  const Chapter({required this.title, required this.start, required this.end});

  final String title;
  final int start;
  final int end;

  int get length => end - start;

  Map<String, dynamic> toJson() => {'t': title, 's': start, 'e': end};

  static Chapter fromJson(Map<String, dynamic> j) =>
      Chapter(title: j['t'] as String? ?? '', start: (j['s'] as num).toInt(), end: (j['e'] as num).toInt());
}

/// 书签：记在「章节 + 章节内偏移」，换字号后仍能回到同一段文字。
class Bookmark {
  const Bookmark({required this.chapter, required this.offset, this.title = '', this.createdAt});

  final int chapter;
  final int offset;
  final String title;
  final DateTime? createdAt;

  Map<String, dynamic> toJson() => {
        'c': chapter,
        'o': offset,
        't': title,
        'at': createdAt?.millisecondsSinceEpoch,
      };

  static Bookmark fromJson(Map<String, dynamic> j) => Bookmark(
        chapter: (j['c'] as num?)?.toInt() ?? 0,
        offset: (j['o'] as num?)?.toInt() ?? 0,
        title: j['t'] as String? ?? '',
        createdAt: j['at'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['at'] as num).toInt()),
      );
}

/// 书架上的书。章节表单独落盘，索引里只放元数据，避免每次存进度都写大 JSON。
class Book {
  Book({
    required this.id,
    required this.title,
    this.author = '',
    required this.path,
    this.charCount = 0,
    this.chapterCount = 1,
    this.chapterIndex = 0,
    this.charOffset = 0,
    this.percent = 0,
    this.addedAt,
    this.lastReadAt,
    this.coverPath,
    this.accentIndex = 0,
    this.finished = false,
    List<Bookmark>? bookmarks,
  }) : bookmarks = bookmarks ?? <Bookmark>[];

  final String id;
  String title;
  String author;
  final String path;
  final int charCount;
  final int chapterCount;

  int chapterIndex;
  int charOffset;
  double percent;
  DateTime? addedAt;
  DateTime? lastReadAt;
  String? coverPath;
  int accentIndex;
  bool finished;

  /// 书签按插入顺序保存，界面上倒序展示。
  final List<Bookmark> bookmarks;

  bool get hasStarted => lastReadAt != null || percent > 0;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'author': author,
        'path': path,
        'charCount': charCount,
        'chapterCount': chapterCount,
        'chapterIndex': chapterIndex,
        'charOffset': charOffset,
        'percent': percent,
        'addedAt': addedAt?.millisecondsSinceEpoch,
        'lastReadAt': lastReadAt?.millisecondsSinceEpoch,
        'coverPath': coverPath,
        'accentIndex': accentIndex,
        'finished': finished,
        if (bookmarks.isNotEmpty) 'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
      };

  static Book fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String? ?? '未命名',
        author: j['author'] as String? ?? '',
        path: j['path'] as String,
        charCount: (j['charCount'] as num?)?.toInt() ?? 0,
        chapterCount: (j['chapterCount'] as num?)?.toInt() ?? 1,
        chapterIndex: (j['chapterIndex'] as num?)?.toInt() ?? 0,
        charOffset: (j['charOffset'] as num?)?.toInt() ?? 0,
        percent: (j['percent'] as num?)?.toDouble() ?? 0,
        addedAt: j['addedAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['addedAt'] as num).toInt()),
        lastReadAt:
            j['lastReadAt'] == null ? null : DateTime.fromMillisecondsSinceEpoch((j['lastReadAt'] as num).toInt()),
        coverPath: j['coverPath'] as String?,
        accentIndex: (j['accentIndex'] as num?)?.toInt() ?? 0,
        finished: j['finished'] as bool? ?? false,
        bookmarks: (j['bookmarks'] as List<dynamic>?)
                ?.map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
                .toList() ??
            <Bookmark>[],
      );
}

String encodeChapters(List<Chapter> list) =>
    jsonEncode(list.map((c) => <String, dynamic>{'t': c.title, 's': c.start, 'e': c.end}).toList());

List<Chapter> decodeChapters(String raw) {
  final data = jsonDecode(raw) as List<dynamic>;
  return data.map((e) => Chapter.fromJson(e as Map<String, dynamic>)).toList();
}
