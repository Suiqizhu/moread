import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:fast_gbk/fast_gbk.dart';
import 'package:xml/xml.dart';

import '../models/book.dart';

/// 一本解析完成的书（还没落盘）。
class ParsedBook {
  ParsedBook({
    required this.text,
    required this.chapters,
    required this.title,
    required this.author,
    this.cover,
  });

  final String text;
  final List<Chapter> chapters;
  final String title;
  final String author;
  final Uint8List? cover;
}

/// 纯 Dart 的书籍解析：不依赖 Flutter，方便用 dart 直接跑用例。
class BookParser {
  static final RegExp _chapterRe = RegExp(
    r'^[ \t\u3000]*(?:'
    r'第[0-9０-９零一二三四五六七八九十百千万两]{1,12}[章回节卷集部篇话更]'
    r'|[Cc]hapter\s*[0-9IVXLCivxlc]{1,6}'
    r'|序章|序言|楔子|引子|前言|后记|尾声|终章|大结局|番外'
    r')[^\n]{0,50}$',
    multiLine: true,
  );

  /// 按扩展名分发。
  static ParsedBook parse(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.epub')) {
      return parseEpub(bytes);
    }
    final text = normalize(decodeText(bytes));
    final (title, author) = splitName(_stripExt(fileName));
    return ParsedBook(
      text: text,
      chapters: splitChapters(text),
      title: title,
      author: author,
    );
  }

  // ---------------------------------------------------------------- TXT

  /// TXT 解码：优先 UTF-8，失败回退 GBK（中文 txt 最常见），再不行就容错 UTF-8。
  static String decodeText(Uint8List bytes) {
    if (bytes.length > 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final units = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        units.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(units);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {
      try {
        return gbk.decode(bytes);
      } catch (_) {
        return utf8.decode(bytes, allowMalformed: true);
      }
    }
  }

  static String normalize(String s) {
    var t = s.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    t = t.replaceAll('\u0000', '').replaceAll('\ufeff', '');
    t = t.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+$'), '')).join('\n');
    t = t.replaceAll(RegExp(r'\n{4,}'), '\n\n\n');
    return t;
  }

  /// 章节切分：识别「第X章 / Chapter N / 序章 / 番外」这类标题行。
  static List<Chapter> splitChapters(String text) {
    final matches = <(int, String)>[];
    for (final m in _chapterRe.allMatches(text)) {
      final line = m.group(0)!.trim();
      if (line.isEmpty) continue;
      // 标题行不会以句号、叹号收尾，借此排除正文里的误判
      if (RegExp(r'[。！？；，,]$').hasMatch(line)) continue;
      matches.add((m.start, line));
    }

    if (matches.length < 2) {
      return [Chapter(title: '正文', start: 0, end: text.length)];
    }

    final chapters = <Chapter>[];
    final headEnd = matches.first.$1;
    if (headEnd > 300) {
      chapters.add(Chapter(title: '序', start: 0, end: headEnd));
    }
    for (var i = 0; i < matches.length; i++) {
      final start = matches[i].$1;
      final end = i + 1 < matches.length ? matches[i + 1].$1 : text.length;
      if (end <= start) continue;
      chapters.add(Chapter(title: shortTitle(matches[i].$2), start: start, end: end));
    }
    return chapters;
  }

  static String shortTitle(String s) {
    final t = s.trim();
    if (t.length > 40) return '${t.substring(0, 40)}…';
    return t;
  }

  /// 文件名里的作者拆分：「书名 作者：某某」「《书名》作者」等。
  static (String, String) splitName(String raw) {
    final s = raw.replaceAll('《', '').replaceAll('》', '').trim();
    final patterns = [
      RegExp(r'^(.*?)[\s_\-—]+作者[:：]\s*(.+)$'),
      RegExp(r'^(.*?)\s*作者[:：]\s*(.+)$'),
      RegExp(r'^(.*?)\s+(?:by|著)\s*(.+)$', caseSensitive: false),
      RegExp(r'^(.*?)[\s_\-—]+([^\s]{2,8})$'),
    ];
    for (final p in patterns) {
      final m = p.firstMatch(s);
      if (m != null) {
        final t = m.group(1)?.trim() ?? '';
        final a = m.group(2)?.trim() ?? '';
        if (t.isNotEmpty && a.isNotEmpty && a.length <= 12) return (t, a);
      }
    }
    return (s, '');
  }

  static String _stripExt(String n) {
    final i = n.lastIndexOf('.');
    return i > 0 ? n.substring(0, i) : n;
  }

  // ---------------------------------------------------------------- EPUB

  static ParsedBook parseEpub(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw FormatException('EPUB 解压失败：$e');
    }

    ArchiveFile? entry(String path) {
      final clean = cleanPath(path);
      for (final f in archive.files) {
        if (!f.isFile) continue;
        if (cleanPath(f.name) == clean) return f;
      }
      return null;
    }

    final containerFile = entry('META-INF/container.xml');
    if (containerFile == null) throw const FormatException('不是有效的 EPUB（缺少 container.xml）');
    final containerXml = XmlDocument.parse(utf8.decode(containerFile.content, allowMalformed: true));
    String? rootPath;
    for (final e in containerXml.descendantElements) {
      if (e.name.local == 'rootfile') {
        final p = e.getAttribute('full-path');
        if (p != null && p.isNotEmpty) {
          rootPath = p;
          break;
        }
      }
    }
    if (rootPath == null) throw const FormatException('EPUB 缺少 OPF');

    final opfFile = entry(rootPath);
    if (opfFile == null) throw const FormatException('EPUB 缺少 OPF 文件');
    final opf = XmlDocument.parse(utf8.decode(opfFile.content, allowMalformed: true));
    final opfDir = dirname(cleanPath(rootPath));

    String? meta(String tag) {
      for (final e in opf.descendantElements) {
        if (e.name.local == tag) {
          final v = e.innerText.trim();
          if (v.isNotEmpty) return v;
        }
      }
      return null;
    }

    final title = meta('title') ?? '';
    final author = (meta('creator') ?? '').replaceAll(RegExp(r'\s+'), ' ');

    // manifest: id → (href, mediaType, properties)
    final manifest = <String, (String, String, String)>{};
    for (final item in opf.descendantElements.where((e) => e.name.local == 'item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      manifest[id] = (href, item.getAttribute('media-type') ?? '', item.getAttribute('properties') ?? '');
    }

    final spine = <String>[];
    for (final ref in opf.descendantElements.where((e) => e.name.local == 'itemref')) {
      if (ref.getAttribute('linear') == 'no') continue;
      final id = ref.getAttribute('idref');
      if (id != null && manifest.containsKey(id)) spine.add(id);
    }
    if (spine.isEmpty) throw const FormatException('EPUB 没有可读章节');

    final buffer = StringBuffer();
    final chapters = <Chapter>[];
    final used = <String>{};
    for (var i = 0; i < spine.length; i++) {
      final info = manifest[spine[i]]!;
      if (!info.$2.contains('html') && !info.$2.contains('xml') && !info.$2.contains('htm')) continue;
      final href = resolve(opfDir, Uri.decodeComponent(info.$1.split('#').first));
      final f = entry(href);
      if (f == null || used.contains(href)) continue;
      used.add(href);
      final raw = utf8.decode(f.content, allowMalformed: true);
      final body = htmlToText(raw);
      if (body.trim().isEmpty) continue;
      final heading = _headingOf(raw) ?? title;
      final start = buffer.length;
      buffer.write(body.trim());
      buffer.write('\n\n');
      final end = buffer.length;
      chapters.add(Chapter(
        title: heading.trim().isEmpty ? '第 ${i + 1} 节' : shortTitle(heading.trim()),
        start: start,
        end: end,
      ));
    }
    if (chapters.isEmpty) throw const FormatException('EPUB 里没有解析到文字');

    Uint8List? cover;
    try {
      String? coverHref;
      for (final e in manifest.entries) {
        if (e.value.$3.contains('cover-image')) {
          coverHref = e.value.$1;
          break;
        }
      }
      if (coverHref == null) {
        for (final m in opf.descendantElements.where((e) => e.name.local == 'meta')) {
          if (m.getAttribute('name') == 'cover') {
            final id = m.getAttribute('content');
            if (id != null && manifest.containsKey(id)) coverHref = manifest[id]!.$1;
          }
        }
      }
      if (coverHref != null) {
        final f = entry(resolve(opfDir, Uri.decodeComponent(coverHref)));
        if (f != null && f.content.isNotEmpty) cover = Uint8List.fromList(f.content);
      }
    } catch (_) {
      cover = null;
    }

    return ParsedBook(text: buffer.toString(), chapters: chapters, title: title, author: author, cover: cover);
  }

  static String? _headingOf(String html) {
    for (final tag in ['h1', 'h2', 'h3']) {
      final m = RegExp('<$tag[^>]*>([\\s\\S]*?)</$tag>', caseSensitive: false).firstMatch(html);
      if (m != null) {
        final t = htmlToText(m.group(1)!).trim().replaceAll('\n', ' ');
        if (t.isNotEmpty && t.length <= 60) return t;
      }
    }
    final t = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(html);
    if (t != null) {
      final s = htmlToText(t.group(1)!).trim();
      if (s.isNotEmpty && s.length <= 60) return s;
    }
    return null;
  }

  static String htmlToText(String html) {
    var s = html.replaceAll(RegExp(r'<!--[\s\S]*?-->'), '');
    s = s.replaceAll(RegExp(r'<(script|style|head)[\s\S]*?</\1>', caseSensitive: false), '');
    s = s.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
    s = s.replaceAll(RegExp(r'</(p|div|h[1-6]|li|blockquote|tr|section|article)>', caseSensitive: false), '\n\n');
    s = s.replaceAll(RegExp(r'<[^>]+>'), '');
    s = decodeEntities(s);
    s = s.replaceAll('\u00a0', ' ');
    final lines = s.split('\n').map((l) => l.replaceAll(RegExp(r'[ \t]+'), ' ').trim()).toList();
    final out = StringBuffer();
    var blank = 0;
    for (final l in lines) {
      if (l.isEmpty) {
        blank++;
        if (blank > 1) continue;
      } else {
        blank = 0;
      }
      out.writeln(l);
    }
    return out.toString().trim();
  }

  static const Map<String, String> _entities = {
    'amp': '&',
    'lt': '<',
    'gt': '>',
    'quot': '"',
    'apos': "'",
    'nbsp': ' ',
    'ldquo': '“',
    'rdquo': '”',
    'lsquo': '‘',
    'rsquo': '’',
    'hellip': '…',
    'mdash': '—',
    'ndash': '–',
    'middot': '·',
    'times': '×',
    'bull': '•',
    'ensp': ' ',
    'emsp': '　',
  };

  static String decodeEntities(String s) => s.replaceAllMapped(
        RegExp(r'&(#x?[0-9a-fA-F]+|[a-zA-Z]+);'),
        (m) {
          final body = m.group(1)!;
          if (body.startsWith('#')) {
            final isHex = body.startsWith('#x') || body.startsWith('#X');
            final code = int.tryParse(body.substring(isHex ? 2 : 1), radix: isHex ? 16 : 10);
            if (code != null && code > 0 && code < 0x110000) {
              try {
                return String.fromCharCode(code);
              } catch (_) {
                return m.group(0)!;
              }
            }
            return m.group(0)!;
          }
          return _entities[body.toLowerCase()] ?? m.group(0)!;
        },
      );

  static String cleanPath(String p) {
    final parts = <String>[];
    for (final seg in p.replaceAll('\\', '/').split('/')) {
      if (seg.isEmpty || seg == '.') continue;
      if (seg == '..') {
        if (parts.isNotEmpty) parts.removeLast();
      } else {
        parts.add(seg);
      }
    }
    return parts.join('/');
  }

  static String dirname(String p) {
    final i = p.lastIndexOf('/');
    return i < 0 ? '' : p.substring(0, i);
  }

  static String resolve(String base, String rel) {
    if (rel.startsWith('/')) return cleanPath(rel);
    return cleanPath(base.isEmpty ? rel : '$base/$rel');
  }

  static String guessImageExt(Uint8List b) {
    if (b.length > 3 && b[0] == 0xFF && b[1] == 0xD8) return 'jpg';
    if (b.length > 8 && b[0] == 0x89 && b[1] == 0x50) return 'png';
    if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) return 'webp';
    return 'jpg';
  }
}
