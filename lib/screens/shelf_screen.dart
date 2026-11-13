import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/book.dart';
import '../services/importer.dart';
import '../services/library.dart';
import '../widgets/book_cover.dart';
import 'reader_screen.dart';

class ShelfScreen extends StatefulWidget {
  const ShelfScreen({super.key});

  @override
  State<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends State<ShelfScreen> {
  final Library _library = Library.instance;
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  bool _busy = false;
  String _busyLabel = '';
  bool _searching = false;
  String _query = '';
  int _sort = 0;
  final Set<String> _selected = <String>{};

  @override
  void initState() {
    super.initState();
    _library.addListener(_onLibraryChanged);
  }

  @override
  void dispose() {
    _library.removeListener(_onLibraryChanged);
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _onLibraryChanged() {
    if (mounted) setState(() {});
  }

  bool get _selectionMode => _selected.isNotEmpty;

  List<Book> get _visible {
    final q = _query.trim().toLowerCase();
    var list = _library.books.where((b) {
      if (q.isEmpty) return true;
      return b.title.toLowerCase().contains(q) || b.author.toLowerCase().contains(q);
    }).toList();
    switch (_sort) {
      case 1: // 导入时间
        list.sort((a, b) => (b.addedAt?.millisecondsSinceEpoch ?? 0).compareTo(a.addedAt?.millisecondsSinceEpoch ?? 0));
      case 2: // 书名
        list.sort((a, b) => a.title.compareTo(b.title));
      default: // 最近阅读
        list.sort((a, b) {
          final la = a.lastReadAt?.millisecondsSinceEpoch ?? 0;
          final lb = b.lastReadAt?.millisecondsSinceEpoch ?? 0;
          if (la != lb) return lb.compareTo(la);
          return (b.addedAt?.millisecondsSinceEpoch ?? 0).compareTo(a.addedAt?.millisecondsSinceEpoch ?? 0);
        });
    }
    return list;
  }

  Future<void> _import() async {
    if (_busy) return;
    final picked = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['txt', 'epub'],
      dialogTitle: '选择 TXT / EPUB',
    );
    if (picked.isEmpty || !mounted) return;

    setState(() {
      _busy = true;
      _busyLabel = picked.length > 1 ? '正在导入 1/${picked.length}' : '正在导入';
    });

    var ok = 0;
    final failures = <String>[];
    for (var i = 0; i < picked.length; i++) {
      final f = picked[i];
      if (mounted) setState(() => _busyLabel = '正在导入 ${i + 1}/${picked.length}');
      try {
        final path = f.path;
        if (path != null) {
          await Importer.importPath(path, displayName: f.name);
        } else {
          await Importer.importBytes(await f.readAsBytes(), f.name);
        }
        ok++;
      } on ImportException catch (e) {
        failures.add('${f.name}：${e.message}');
      } catch (e) {
        failures.add('${f.name}：$e');
      }
    }
    if (!mounted) return;
    setState(() => _busy = false);

    final message = failures.isEmpty
        ? '已导入 $ok 本书'
        : '已导入 $ok 本，${failures.length} 本失败：${failures.first}';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _open(Book book) async {
    if (_selectionMode) {
      _toggleSelect(book);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ReaderScreen(book: book)),
    );
    // 阅读进度只在内存里更新，回到书架时主动刷新一次。
    if (mounted) setState(() {});
  }

  void _toggleSelect(Book book) {
    HapticFeedback.selectionClick();
    setState(() {
      if (!_selected.remove(book.id)) _selected.add(book.id);
    });
  }

  void _exitSelection() {
    setState(_selected.clear);
  }

  Future<void> _deleteSelected() async {
    final books = _library.books.where((b) => _selected.contains(b.id)).toList();
    if (books.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除 ${books.length} 本书？'),
        content: Text('将从书架移除：${books.map((b) => '《${b.title}》').take(3).join('、')}'
            '${books.length > 3 ? ' 等' : ''}，本地文件也会一起删掉。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final b in books) {
      await _library.remove(b);
    }
    if (mounted) {
      setState(_selected.clear);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('已删除 ${books.length} 本书')));
    }
  }

  PreferredSizeWidget _buildAppBar() {
    final scheme = Theme.of(context).colorScheme;
    if (_searching) {
      return AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            setState(() {
              _searching = false;
              _query = '';
              _searchCtrl.clear();
            });
            FocusScope.of(context).unfocus();
          },
        ),
        titleSpacing: 0,
        title: TextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          autofocus: true,
          textInputAction: TextInputAction.search,
          decoration: const InputDecoration(
            hintText: '搜索书名或作者',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v),
        ),
        actions: [
          if (_query.isNotEmpty)
            IconButton(
              tooltip: '清除',
              icon: const Icon(Icons.close),
              onPressed: () {
                _searchCtrl.clear();
                setState(() => _query = '');
              },
            ),
        ],
      );
    }

    if (_selectionMode) {
      return AppBar(
        leading: IconButton(icon: const Icon(Icons.close), onPressed: _exitSelection),
        title: Text('已选择 ${_selected.length} 项'),
        actions: [
          IconButton(
            tooltip: '全选',
            icon: const Icon(Icons.select_all),
            onPressed: () => setState(() {
              final all = _visible.map((b) => b.id);
              if (_selected.length == all.length) {
                _selected.clear();
              } else {
                _selected
                  ..clear()
                  ..addAll(all);
              }
            }),
          ),
          IconButton(
            tooltip: '删除',
            icon: const Icon(Icons.delete_outline),
            color: scheme.error,
            onPressed: _deleteSelected,
          ),
          const SizedBox(width: 4),
        ],
      );
    }

    return AppBar(
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('墨读'),
          Text(
            _library.books.isEmpty ? '把想读的书放进来' : '共 ${_library.books.length} 本',
            style: TextStyle(fontSize: 12, color: scheme.outline, fontWeight: FontWeight.w400),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: '搜索',
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() => _searching = true);
            WidgetsBinding.instance.addPostFrameCallback((_) => _searchFocus.requestFocus());
          },
        ),
        PopupMenuButton<int>(
          tooltip: '排序',
          icon: const Icon(Icons.sort),
          initialValue: _sort,
          onSelected: (v) => setState(() => _sort = v),
          itemBuilder: (context) => const [
            PopupMenuItem(value: 0, child: Text('最近阅读')),
            PopupMenuItem(value: 1, child: Text('导入时间')),
            PopupMenuItem(value: 2, child: Text('书名')),
          ],
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final books = _visible;
    final continueBook = _library.lastRead;

    return Scaffold(
      appBar: _buildAppBar(),
      floatingActionButton: _searching || _selectionMode
          ? null
          : FloatingActionButton.extended(
              onPressed: _busy ? null : _import,
              icon: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_busy ? _busyLabel : '导入'),
            ),
      body: _library.books.isEmpty
          ? _EmptyShelf(onImport: _import)
          : CustomScrollView(
              slivers: [
                if (_busy)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: scheme.primary),
                          ),
                          const SizedBox(width: 10),
                          Text(_busyLabel, style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                    ),
                  ),
                if (continueBook != null && !_searching)
                  SliverToBoxAdapter(child: _ContinueCard(book: continueBook, onTap: () => _open(continueBook))),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  sliver: books.isEmpty
                      ? SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 80),
                            child: Center(
                              child: Text('没有找到「$_query」',
                                  style: TextStyle(color: scheme.outline)),
                            ),
                          ),
                        )
                      : SliverGrid(
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 118,
                            childAspectRatio: 0.56,
                            crossAxisSpacing: 14,
                            mainAxisSpacing: 18,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final book = books[index];
                              return _BookTile(
                                book: book,
                                selected: _selected.contains(book.id),
                                onTap: () => _selectionMode ? _toggleSelect(book) : _open(book),
                                onLongPress: () => _toggleSelect(book),
                              );
                            },
                            childCount: books.length,
                          ),
                        ),
                ),
              ],
            ),
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final percent = book.percent.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                SizedBox(width: 52, height: 70, child: BookCover(book: book, borderRadius: 8)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('继续阅读',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.6,
                          )),
                      const SizedBox(height: 3),
                      Text(book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: percent,
                          minHeight: 3,
                          backgroundColor: scheme.surfaceContainerHighest,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '第 ${book.chapterIndex + 1}/${book.chapterCount} 章 · ${(percent * 100).toStringAsFixed(1)}%',
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: scheme.outline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BookTile extends StatelessWidget {
  const _BookTile({
    required this.book,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  final Book book;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.14),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: BookCover(book: book),
                ),
                if (selected)
                  Container(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.32),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.check_circle, color: scheme.onPrimary, size: 30),
                  ),
                if (book.finished && !selected)
                  Positioned(
                    left: 6,
                    top: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.45),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text('读完',
                          style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 7),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: book.percent.clamp(0.0, 1.0),
                    minHeight: 2.5,
                    backgroundColor: scheme.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation(scheme.primary),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '${(book.percent * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(fontSize: 10, color: scheme.outline),
              ),
            ],
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
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              color: scheme.primaryContainer.withValues(alpha: 0.45),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_stories_outlined, size: 46, color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 24),
          Text('书架还是空的', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text(
            '导入 TXT 或 EPUB 就能开始，\n书和进度都只存在本机。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline, height: 1.6),
          ),
          const SizedBox(height: 26),
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
