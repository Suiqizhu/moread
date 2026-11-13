import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../models/book.dart';
import '../services/importer.dart';
import '../services/library.dart';
import 'reader_screen.dart';

const List<List<Color>> _coverAccents = [
  [Color(0xFF33514A), Color(0xFF6D9488)],
  [Color(0xFF5B463B), Color(0xFF9C7A5C)],
  [Color(0xFF3C4A66), Color(0xFF7687AB)],
  [Color(0xFF573845), Color(0xFF9A6478)],
  [Color(0xFF3D4A3C), Color(0xFF7A8F6E)],
  [Color(0xFF4A3B57), Color(0xFF8B77A0)],
];

class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key});

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  bool _busy = false;

  Future<void> _import() async {
    if (_busy) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub'],
      allowMultiple: true,
      withData: false,
    );
    if (result == null || result.files.isEmpty) return;
    if (!mounted) return;

    setState(() => _busy = true);
    var ok = 0;
    final failures = <String>[];
    for (final f in result.files) {
      final path = f.path;
      if (path == null) {
        failures.add('${f.name}：无法读取文件');
        continue;
      }
      try {
        await Importer.importPath(path, displayName: f.name);
        ok++;
      } on ImportException catch (e) {
        failures.add('${f.name}：${e.message}');
      } catch (e) {
        failures.add('${f.name}：$e');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final msg = failures.isEmpty
        ? '已导入 $ok 本书'
        : '已导入 $ok 本，${failures.length} 本失败';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(failures.isEmpty ? msg : '$msg\n${failures.first}'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _open(Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
  }

  Future<void> _showActions(Book book) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                book.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('${(book.percent * 100).toStringAsFixed(1)}% · ${book.chapterCount} 章'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.menu_book_outlined),
              title: const Text('继续阅读'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _open(book);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('删除这本书', style: TextStyle(color: Colors.redAccent)),
              onTap: () async {
                Navigator.of(sheetContext).pop();
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('删除书籍'),
                    content: Text('将从书架移除《${book.title}》，本地文件也会删掉。'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(c).pop(false), child: const Text('取消')),
                      FilledButton(
                        style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                        onPressed: () => Navigator.of(c).pop(true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) await Library.instance.remove(book);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Library.instance,
      builder: (context, _) {
        final books = Library.instance.shelf;
        return Scaffold(
          body: CustomScrollView(
            slivers: [
              SliverAppBar(
                floating: true,
                snap: true,
                titleSpacing: 20,
                title: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('墨读', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: 1)),
                    Text(
                      books.isEmpty ? '把想读的书放进来' : '共 ${books.length} 本',
                      style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline),
                    ),
                  ],
                ),
                actions: [
                  IconButton(
                    tooltip: '导入书籍',
                    onPressed: _busy ? null : _import,
                    icon: _busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.add_circle_outline),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
              if (books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyShelf(onImport: _import),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 132,
                      childAspectRatio: 0.55,
                      crossAxisSpacing: 18,
                      mainAxisSpacing: 22,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final book = books[index];
                        return _BookTile(
                          book: book,
                          onTap: () => _open(book),
                          onLongPress: () => _showActions(book),
                        );
                      },
                      childCount: books.length,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({required this.book, required this.onTap, required this.onLongPress});

  final Book book;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final percent = (book.percent * 100).clamp(0, 100);
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: BookCover(book: book),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, height: 1.3),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: book.percent.clamp(0.0, 1.0),
                    minHeight: 2.5,
                    backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(book.finished ? Colors.amber : const Color(0xFF5E7F70)),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                book.finished ? '读完' : '${percent.toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.outline),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 书架封面：EPUB 有封面图就用图，否则用书名生成一张色卡。
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context) {
    final file = book.coverPath == null ? null : File(book.coverPath!);
    if (file != null && file.existsSync()) {
      return Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _generated(context),
      );
    }
    return _generated(context);
  }

  Widget _generated(BuildContext context) {
    final pair = _coverAccents[book.accentIndex % _coverAccents.length];
    final title = book.title.replaceAll(RegExp(r'《|》'), '');
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: pair,
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(width: 22, height: 3, color: Colors.white.withValues(alpha: 0.7)),
          const Spacer(),
          Text(
            title.length > 24 ? '${title.substring(0, 24)}…' : title,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          if (book.author.isNotEmpty)
            Text(
              book.author,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 10),
            ),
          const Spacer(),
          Text(
            '墨读',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 9, letterSpacing: 2),
          ),
        ],
      ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_stories_outlined, size: 44, color: scheme.primary.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 24),
          const Text('书架还是空的', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '支持 TXT 与 EPUB，导入后离线阅读，\n进度和排版设置都会记住。',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.6, color: scheme.outline),
          ),
          const SizedBox(height: 28),
          FilledButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.add),
            label: const Text('导入本地书籍'),
          ),
        ],
      ),
    );
  }
}
