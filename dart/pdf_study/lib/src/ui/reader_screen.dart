import 'dart:async';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../ai/context.dart';
import '../models.dart';
import '../providers.dart';
import '../store.dart';
import 'ai_panel.dart';
import 'flashcard_panel.dart';
import 'settings_screen.dart';
import 'side_panels.dart';
import 'util.dart';

/// 批注可选颜色。
const kAnnotationColors = [0xFFFFD54F, 0xFF81C784, 0xFF64B5F6, 0xFFF48FB1];

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({required this.entryKey, super.key});

  final String entryKey;

  @override
  ConsumerState<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends ConsumerState<ReaderScreen> {
  late final LibraryEntry entry;
  final controller = PdfViewerController();

  PdfDocumentRef? docRef;
  PdfDocument? document;
  List<PdfOutlineNode>? outline;
  PdfTextSearcher? searcher;
  List<PdfPageTextRange> selectionRanges = [];

  late final DocDataStore docData;
  late final ChatStore chat;
  late final DeckStore deck;

  int currentPage = 1;
  int pageCount = 0;
  int sidebarTab = 0; // 0 搜索 1 目录 2 页面 3 批注 4 书签
  Timer? _progressTimer;

  /// AI 面板注册的动作处理器。
  void Function(String action, ContextScope scope)? onAiAction;

  /// 卡片面板注册的生成处理器。
  void Function(ContextScope scope)? onGenerateCards;

  bool get sidebarOpen => ref.read(settingsProvider).sidebarOpen;
  bool get aiPanelOpen => ref.read(settingsProvider).aiPanelOpen;

  @override
  void initState() {
    super.initState();
    final lib = ref.read(libraryProvider);
    final e = lib.byKey(widget.entryKey);
    if (e == null) {
      // 书库条目被删时直接返回，不崩溃
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      entry = LibraryEntry(
        key: widget.entryKey,
        path: '',
        title: '',
        lastOpened: DateTime.now(),
      );
      docRef = null;
      final dirs0 = ref.read(appDirsProvider);
      docData = DocDataStore(JsonFile(dirs0.file('docs/_none.json')));
      chat = ChatStore(JsonFile(dirs0.file('chats/_none.json')));
      deck = DeckStore(JsonFile(dirs0.file('decks/_none.json')));
      return;
    }
    entry = e;
    final dirs = ref.read(appDirsProvider);
    docData = DocDataStore(JsonFile(dirs.file('docs/${entry.key}.json')));
    chat = ChatStore(JsonFile(dirs.file('chats/${entry.key}.json')));
    deck = DeckStore(JsonFile(dirs.file('decks/${entry.key}.json')));
    docRef = PdfDocumentRefFile(
      entry.path,
      passwordProvider: () => _passwordDialog(context),
    );
    docData.load();
    chat.load();
    deck.load();
  }

  @override
  void dispose() {
    _progressTimer?.cancel();
    _saveProgress();
    searcher?.dispose();
    super.dispose();
  }

  void _saveProgress() {
    if (docRef == null) return; // 条目已被删，不回写进度
    final lib = ref.read(libraryProvider);
    unawaited(
      lib.touch(
        key: entry.key,
        path: entry.path,
        title: entry.title,
        pageCount: pageCount,
        lastPage: currentPage,
        zoom: controller.isReady ? controller.currentZoom : null,
      ),
    );
  }

  /// 批注/书签变更后强制页面层重绘（pdfrx 的自定义绘制只在视图变换时重跑）。
  void _repaintPages() {
    if (controller.isReady) {
      unawaited(
        controller.goTo(controller.value.clone(), duration: Duration.zero),
      );
    }
  }

  void _onPageChanged(int? page) {
    if (page == null) return;
    setState(() => currentPage = page);
    _progressTimer?.cancel();
    _progressTimer = Timer(const Duration(milliseconds: 800), _saveProgress);
  }

  Future<String> selectedText() async => controller.isReady
      ? controller.textSelectionDelegate.getSelectedText()
      : '';

  void goToAnnotation(Annotation a) {
    if (a.rects.isEmpty || !controller.isReady) return;
    final r = a.rects.first;
    controller.ensureVisible(
      controller.calcRectForRectInsidePage(
        pageNumber: a.page,
        rect: PdfRect(r[0], r[1], r[2], r[3]),
      ),
      margin: 60,
    );
  }

  void toggleSidebar([int? tab]) {
    final s = ref.read(settingsProvider);
    if (tab != null) sidebarTab = tab;
    s.sidebarOpen = tab != null ? true : !s.sidebarOpen;
    s.save();
    setState(() {});
  }

  void toggleAiPanel() {
    final s = ref.read(settingsProvider);
    s.aiPanelOpen = !s.aiPanelOpen;
    s.save();
    setState(() {});
  }

  Future<void> _openAnother() async {
    final files = await FilePicker.pickFiles(
      dialogTitle: '打开 PDF',
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = files.isEmpty ? null : files.first.path;
    if (path == null) return;
    final key = await fingerprintFile(path);
    final lib = ref.read(libraryProvider);
    final title = path
        .split(RegExp(r'[\\/]'))
        .last
        .replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '');
    final e = await lib.touch(
      key: key,
      path: path,
      title: lib.byKey(key)?.title ?? title,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => ReaderScreen(entryKey: e.key)),
    );
  }

  // ---------- 批注 ----------

  Future<void> _addHighlight(int colorValue, {bool withNote = false}) async {
    if (selectionRanges.isEmpty) return;
    final byPage = <int, List<PdfPageTextRange>>{};
    for (final r in selectionRanges) {
      byPage.putIfAbsent(r.pageNumber, () => []).add(r);
    }
    for (final e in byPage.entries) {
      // 同页多段合并为一条批注（按行矩形记录）
      final rects = <List<double>>[];
      final buf = StringBuffer();
      for (final r in e.value) {
        for (final f in r.enumerateFragmentBoundingRects()) {
          final b = f.bounds;
          rects.add([b.left, b.top, b.right, b.bottom]);
        }
        buf.write(r.text);
      }
      final a = Annotation(
        id: newId(),
        page: e.key,
        rects: rects,
        colorValue: colorValue,
        text: buf.toString(),
        createdAt: DateTime.now(),
      );
      await docData.addAnnotation(a);
      if (withNote && mounted) {
        await editAnnotation(a);
      }
    }
    await controller.textSelectionDelegate.clearTextSelection();
    _repaintPages();
  }

  Future<void> editAnnotation(Annotation a) async {
    final noteCtrl = TextEditingController(text: a.note);
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('笔记'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Color(a.colorValue).withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    a.text,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    for (final c in kAnnotationColors)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: InkWell(
                          onTap: () => setD(() => a.colorValue = c),
                          child: CircleAvatar(
                            radius: 12,
                            backgroundColor: Color(c),
                            child: a.colorValue == c
                                ? const Icon(
                                    Icons.check,
                                    size: 14,
                                    color: Colors.black87,
                                  )
                                : null,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: noteCtrl,
                  autofocus: true,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    hintText: '写下想法…',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('删除'),
              onPressed: () => Navigator.pop(ctx, '__delete__'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, noteCtrl.text),
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    if (result == '__delete__') {
      await docData.removeAnnotation(a.id);
    } else if (result != null) {
      a.note = result;
      await docData.updateAnnotation(a);
    } else {
      return;
    }
    _repaintPages();
  }

  // ---------- 绘制 ----------

  void _paintAnnotations(Canvas canvas, Rect pageRect, PdfPage page) {
    for (final a in docData.onPage(page.pageNumber)) {
      final paint = Paint()
        ..color = Color(a.colorValue).withValues(alpha: 0.35)
        ..style = PaintingStyle.fill;
      for (final r in a.rects) {
        final rect = PdfRect(
          r[0],
          r[1],
          r[2],
          r[3],
        ).toRectInDocument(page: page, pageRect: pageRect);
        canvas.drawRect(rect, paint);
      }
      if (a.hasNote && a.rects.isNotEmpty) {
        final r = a.rects.first;
        final rect = PdfRect(
          r[0],
          r[1],
          r[2],
          r[3],
        ).toRectInDocument(page: page, pageRect: pageRect);
        final path = Path()
          ..moveTo(rect.right - 2, rect.top)
          ..lineTo(rect.right + 8, rect.top)
          ..lineTo(rect.right - 2, rect.top - 10)
          ..close();
        canvas.drawPath(
          path,
          Paint()..color = Color(a.colorValue).withValues(alpha: 0.95),
        );
      }
    }
  }

  // ---------- 上下文菜单 ----------

  Widget _selectionToolbar(
    BuildContext context,
    PdfViewerContextMenuBuilderParams p,
  ) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tbBtn(context, Icons.copy, '复制', () async {
              await p.textSelectionDelegate.copyTextSelection();
              p.dismissContextMenu();
            }),
            _tbBtn(context, Icons.select_all, '全选', () async {
              await p.textSelectionDelegate.selectAllText();
            }),
            Container(
              width: 1,
              height: 22,
              color: Theme.of(context).dividerColor,
            ),
            for (final c in kAnnotationColors)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: InkWell(
                  onTap: () {
                    p.dismissContextMenu();
                    _addHighlight(c);
                  },
                  child: CircleAvatar(radius: 9, backgroundColor: Color(c)),
                ),
              ),
            _tbBtn(context, Icons.edit_note, '笔记', () {
              p.dismissContextMenu();
              _addHighlight(kAnnotationColors.first, withNote: true);
            }),
            Container(
              width: 1,
              height: 22,
              color: Theme.of(context).dividerColor,
            ),
            _tbBtn(context, Icons.psychology_outlined, '讲解', () {
              p.dismissContextMenu();
              onAiAction?.call('explain', ContextScope.selection);
            }),
            _tbBtn(context, Icons.translate, '翻译', () {
              p.dismissContextMenu();
              onAiAction?.call('translate', ContextScope.selection);
            }),
            _tbBtn(context, Icons.summarize_outlined, '总结', () {
              p.dismissContextMenu();
              onAiAction?.call('summarize', ContextScope.selection);
            }),
            _tbBtn(context, Icons.chat_bubble_outline, '问 AI', () {
              p.dismissContextMenu();
              if (!aiPanelOpen) toggleAiPanel();
            }),
          ],
        ),
      ),
    );
  }

  Widget _tbBtn(
    BuildContext context,
    IconData icon,
    String tip,
    VoidCallback onTap,
  ) {
    return Tooltip(
      message: tip,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 7),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17),
              Text(tip, style: const TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ),
    );
  }

  Widget? _buildContextMenu(
    BuildContext context,
    PdfViewerContextMenuBuilderParams p,
  ) {
    if (p.contextMenuFor == PdfViewerPart.selectedText &&
        p.isTextSelectionEnabled) {
      return _selectionToolbar(context, p);
    }
    // 背景右键：精简菜单
    return Card(
      elevation: 8,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _menuItem(Icons.bookmark_add_outlined, '本页加书签', () {
              docData.toggleBookmark(currentPage);
              p.dismissContextMenu();
            }),
            _menuItem(Icons.notes, '总结本页', () {
              onAiAction?.call('summarize', ContextScope.page);
              p.dismissContextMenu();
            }),
            _menuItem(Icons.first_page, '回到首页', () {
              controller.goToPage(pageNumber: 1);
              p.dismissContextMenu();
            }),
          ],
        ),
      ),
    );
  }

  Widget _menuItem(IconData icon, String label, VoidCallback onTap) => InkWell(
    onTap: onTap,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 17), const SizedBox(width: 8), Text(label)],
      ),
    ),
  );

  Future<String?> _passwordDialog(BuildContext context) async {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('文档已加密'),
        content: TextField(
          controller: c,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '密码',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, c.text),
            child: const Text('解锁'),
          ),
        ],
      ),
    );
  }

  // ---------- 布局 ----------

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final docReady = docRef != null;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            toggleSidebar(0),
        const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () =>
            toggleSidebar(),
        const SingleActivator(LogicalKeyboardKey.keyJ, meta: true):
            toggleAiPanel,
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): () =>
            controller.zoomUp(),
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): () =>
            controller.zoomDown(),
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () {
          if (controller.isReady) {
            controller.goTo(
              controller.calcMatrixFitWidthForPage(pageNumber: currentPage),
            );
          }
        },
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: '返回书库',
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.title,
                style: const TextStyle(fontSize: 15),
                overflow: TextOverflow.ellipsis,
              ),
              if (pageCount > 0)
                Text(
                  '第 $currentPage / $pageCount 页',
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
            ],
          ),
          actions: [
            IconButton(
              tooltip: '侧栏（⌘B）',
              icon: Icon(
                Icons.view_sidebar_outlined,
                color: settings.sidebarOpen
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: () => toggleSidebar(),
            ),
            IconButton(
              tooltip: '搜索（⌘F）',
              icon: const Icon(Icons.search),
              onPressed: () => toggleSidebar(0),
            ),
            IconButton(
              tooltip: '本页书签',
              icon: Icon(
                docData.isBookmarked(currentPage)
                    ? Icons.bookmark
                    : Icons.bookmark_border,
              ),
              onPressed: () => docData.toggleBookmark(currentPage),
            ),
            IconButton(
              tooltip: '缩小（⌘-）',
              icon: const Icon(Icons.zoom_out),
              onPressed: docReady ? controller.zoomDown : null,
            ),
            IconButton(
              tooltip: '放大（⌘=）',
              icon: const Icon(Icons.zoom_in),
              onPressed: docReady ? controller.zoomUp : null,
            ),
            IconButton(
              tooltip: '适合页宽（⌘0）',
              icon: const Icon(Icons.fit_screen),
              onPressed: docReady
                  ? () => controller.goTo(
                      controller.calcMatrixFitWidthForPage(
                        pageNumber: currentPage,
                      ),
                    )
                  : null,
            ),
            IconButton(
              tooltip: 'AI 面板（⌘J）',
              icon: Icon(
                Icons.smart_toy_outlined,
                color: settings.aiPanelOpen
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              onPressed: toggleAiPanel,
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                switch (v) {
                  case 'open':
                    _openAnother();
                  case 'settings':
                    Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const SettingsScreen()),
                    );
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'open', child: Text('打开其他 PDF…')),
                PopupMenuItem(value: 'settings', child: Text('设置')),
              ],
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            // 窄屏（手机）下双面板改为浮层，不再挤占阅读区
            final narrow = constraints.maxWidth < 840;
            final sideW = narrow
                ? math.min(300.0, constraints.maxWidth * 0.8)
                : 290.0;
            final aiW = narrow
                ? math.min(380.0, constraints.maxWidth * 0.85)
                : 400.0;
            final viewer = docRef == null
                ? const Center(child: Text('没有打开的文档'))
                : PdfViewer(
                    docRef!,
                    controller: controller,
                    params: PdfViewerParams(
                      pageAnchor: PdfPageAnchor.top,
                      backgroundColor:
                          Theme.of(context).brightness == Brightness.dark
                          ? const Color(0xFF20242B)
                          : const Color(0xFFE8EAEE),
                      keyHandlerParams: const PdfViewerKeyHandlerParams(
                        autofocus: true,
                      ),
                      sizeDelegateProvider:
                          const PdfViewerSizeDelegateProviderLegacy(
                            maxScale: 8,
                          ),
                      textSelectionParams: PdfTextSelectionParams(
                        onTextSelectionChange: (sel) async {
                          selectionRanges = await sel.getSelectedTextRanges();
                        },
                      ),
                      pagePaintCallbacks: [
                        if (searcher != null)
                          searcher!.pageTextMatchPaintCallback,
                        _paintAnnotations,
                      ],
                      buildContextMenu: _buildContextMenu,
                      onViewerReady: (doc, ctrl) async {
                        document = doc;
                        pageCount = doc.pages.length;
                        outline = await doc.loadOutline();
                        searcher = PdfTextSearcher(ctrl)
                          ..addListener(() => setState(() {}));
                        ctrl.requestFocus();
                        // 恢复进度
                        if (entry.lastPage > 1) {
                          await ctrl.goToPage(
                            pageNumber: entry.lastPage.clamp(1, pageCount),
                            duration: Duration.zero,
                          );
                        }
                        if (entry.zoom != null && entry.zoom! > 0) {
                          await ctrl.setZoom(
                            ctrl.centerPosition,
                            entry.zoom!,
                            duration: Duration.zero,
                          );
                        }
                        await ref
                            .read(libraryProvider)
                            .touch(
                              key: entry.key,
                              path: entry.path,
                              title: entry.title,
                              pageCount: pageCount,
                              lastPage: currentPage,
                            );
                        if (mounted) setState(() {});
                      },
                      onPageChanged: _onPageChanged,
                      linkHandlerParams: PdfLinkHandlerParams(
                        onLinkTap: (link) {
                          if (link.dest != null) {
                            controller.goToDest(link.dest);
                          } else if (link.url != null) {
                            launchUrlExternal(link.url!, context: context);
                          }
                        },
                      ),
                      loadingBannerBuilder: (context, done, total) =>
                          const Center(child: CircularProgressIndicator()),
                      viewerOverlayBuilder: (context, size, handleLinkTap) => [
                        PdfViewerScrollThumb(
                          controller: controller,
                          orientation: ScrollbarOrientation.right,
                          thumbSize: const Size(36, 24),
                          thumbBuilder:
                              (context, thumbSize, pageNumber, controller) =>
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .inverseSurface
                                          .withValues(alpha: 0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '$pageNumber',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onInverseSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                        ),
                      ],
                    ),
                  );
            if (narrow) {
              return Stack(
                children: [
                  Positioned.fill(child: viewer),
                  if (settings.sidebarOpen || settings.aiPanelOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: () {
                          final s = ref.read(settingsProvider);
                          s.sidebarOpen = false;
                          s.aiPanelOpen = false;
                          s.save();
                          setState(() {});
                        },
                        child: const ColoredBox(color: Color(0x33000000)),
                      ),
                    ),
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: sideW,
                    child: Material(
                      elevation: 16,
                      child: settings.sidebarOpen
                          ? _buildSidebar()
                          : const SizedBox.shrink(),
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    width: aiW,
                    child: Material(
                      elevation: 16,
                      child: settings.aiPanelOpen
                          ? _buildRightPanel()
                          : const SizedBox.shrink(),
                    ),
                  ),
                ],
              );
            }
            return Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: settings.sidebarOpen ? sideW : 0,
                  child: settings.sidebarOpen ? _buildSidebar() : null,
                ),
                Expanded(child: viewer),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: settings.aiPanelOpen ? aiW : 0,
                  child: settings.aiPanelOpen ? _buildRightPanel() : null,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSidebar() {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: DefaultTabController(
        length: 5,
        initialIndex: sidebarTab,
        key: ValueKey(sidebarTab),
        child: Column(
          children: [
            TabBar(
              labelPadding: EdgeInsets.zero,
              tabs: const [
                Tab(icon: Icon(Icons.search, size: 18), text: '搜索'),
                Tab(
                  icon: Icon(Icons.format_list_bulleted, size: 18),
                  text: '目录',
                ),
                Tab(icon: Icon(Icons.grid_view, size: 18), text: '页面'),
                Tab(icon: Icon(Icons.highlight, size: 18), text: '批注'),
                Tab(icon: Icon(Icons.bookmark_border, size: 18), text: '书签'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  SearchPanel(searcher: searcher),
                  OutlinePanel(outline: outline, controller: controller),
                  ThumbnailsPanel(
                    docRef: docRef,
                    controller: controller,
                    currentPage: currentPage,
                  ),
                  AnnotationsPanel(
                    docData: docData,
                    onTap: goToAnnotation,
                    onEdit: editAnnotation,
                  ),
                  BookmarksPanel(
                    docData: docData,
                    onTap: (b) => controller.goToPage(pageNumber: b.page),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightPanel() {
    return ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: DefaultTabController(
        length: 2,
        child: Column(
          children: [
            const TabBar(
              tabs: [
                Tab(
                  icon: Icon(Icons.smart_toy_outlined, size: 18),
                  text: 'AI 助手',
                ),
                Tab(icon: Icon(Icons.style_outlined, size: 18), text: '复习卡片'),
              ],
            ),
            Expanded(
              child: TabBarView(
                children: [
                  AiPanel(host: this),
                  FlashcardPanel(host: this),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
