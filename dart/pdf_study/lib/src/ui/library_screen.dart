import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models.dart';
import '../providers.dart';
import '../store.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  bool _dragging = false;
  bool _loading = true;
  String? _opening;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(libraryProvider).load();
      await ref.read(settingsProvider).load();
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<void> _openPaths(List<String> paths) async {
    for (final raw in paths) {
      final path = raw.trim();
      if (path.isEmpty) continue;
      if (!path.toLowerCase().endsWith('.pdf')) continue;
      if (!await File(path).exists()) {
        if (mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('文件不存在：$path')));
        }
        continue;
      }
      setState(() => _opening = path.split('/').last);
      try {
        final key = await fingerprintFile(path);
        final lib = ref.read(libraryProvider);
        var entry = lib.byKey(key);
        entry = await lib.touch(
          key: key,
          path: path,
          title: entry?.title ?? _titleFromPath(path),
        );
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ReaderScreen(entryKey: entry!.key)),
        );
        if (mounted) setState(() {});
      } finally {
        if (mounted) setState(() => _opening = null);
      }
    }
  }

  static String _titleFromPath(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    return name.toLowerCase().endsWith('.pdf')
        ? name.substring(0, name.length - 4)
        : name;
  }

  Future<void> _pick() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '打开 PDF',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    await _openPaths([
      for (final f in files)
        if (f.path != null) f.path!,
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final lib = ref.watch(libraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('研学 PDF · 书库'),
        actions: [
          IconButton(
            tooltip: '设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (d) {
          setState(() => _dragging = false);
          _openPaths(d.files.map((f) => f.path).toList());
        },
        child: Stack(
          children: [
            _loading
                ? const Center(child: CircularProgressIndicator())
                : lib.entries.isEmpty
                ? _EmptyState(onOpen: _pick)
                : GridView.builder(
                    padding: const EdgeInsets.all(20),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 190,
                          mainAxisSpacing: 18,
                          crossAxisSpacing: 18,
                          childAspectRatio: 0.62,
                        ),
                    itemCount: lib.entries.length,
                    itemBuilder: (context, i) => _DocCard(
                      entry: lib.entries[i],
                      onOpen: () => _openPaths([lib.entries[i].path]),
                      onRemove: () => lib.remove(lib.entries[i].key),
                    ),
                  ),
            if (_dragging)
              Container(
                color: Theme.of(context).colorScheme.primary
                    .withValues(alpha: 0.12),
                child: const Center(
                  child: Text(
                    '松开以打开 PDF',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            if (_opening != null)
              Container(
                color: Colors.black26,
                child: Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text('正在打开 $_opening…'),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pick,
        icon: const Icon(Icons.file_open),
        label: const Text('打开 PDF'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.menu_book_outlined,
            size: 88,
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          const Text('把 PDF 拖到这里，或点击打开', style: TextStyle(fontSize: 18)),
          const SizedBox(height: 8),
          const Text(
            '批注、笔记、AI 问答与课后复习都在阅读器里',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: onOpen,
            icon: const Icon(Icons.file_open),
            label: const Text('打开 PDF'),
          ),
        ],
      ),
    );
  }
}

class _DocCard extends StatefulWidget {
  const _DocCard({
    required this.entry,
    required this.onOpen,
    required this.onRemove,
  });

  final LibraryEntry entry;
  final VoidCallback onOpen;
  final VoidCallback onRemove;

  @override
  State<_DocCard> createState() => _DocCardState();
}

class _DocCardState extends State<_DocCard> {
  bool _hover = false;

  /// 封面在 initState 构建一次后复用：hover 触发的整卡 setState 若重建
  /// PdfDocumentViewBuilder/PdfDocumentRefFile，文档会被判定为已变更而重新
  /// 加载，封面闪白——这就是鼠标移上去闪烁的来源。
  late final Widget _cover = _buildCover();

  Widget _buildCover() {
    if (!File(widget.entry.path).existsSync()) {
      return const Center(
        child: Icon(Icons.broken_image_outlined, size: 48, color: Colors.grey),
      );
    }
    return PdfDocumentViewBuilder(
      documentRef: PdfDocumentRefFile(widget.entry.path),
      builder: (context, doc) => doc == null
          ? const Center(
              child: Icon(
                Icons.picture_as_pdf,
                size: 48,
                color: Colors.redAccent,
              ),
            )
          : PdfPageView(
              document: doc,
              pageNumber: 1,
              alignment: Alignment.topCenter,
              maximumDpi: 110,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final exists = File(e.path).existsSync();
    final dateFmt = DateFormat('yyyy-MM-dd');
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: _hover ? 4 : 1,
        child: InkWell(
          onTap: widget.onOpen,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: const Color(0xFF8B93A3).withValues(alpha: 0.15),
                      child: _cover,
                    ),
                    if (_hover)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: IconButton.filledTonal(
                          visualDensity: VisualDensity.compact,
                          iconSize: 18,
                          tooltip: '从书库移除',
                          onPressed: widget.onRemove,
                          icon: const Icon(Icons.close),
                        ),
                      ),
                    if (!exists)
                      const Positioned(
                        bottom: 4,
                        left: 4,
                        child: Chip(
                          label: Text('文件已移动', style: TextStyle(fontSize: 10)),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        height: 1.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: e.progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '${e.pageCount > 0 ? '读到 ${e.lastPage}/${e.pageCount} 页 · ' : ''}${dateFmt.format(e.lastOpened)}',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
