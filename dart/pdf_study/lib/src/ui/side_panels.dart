import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../models.dart';
import '../store.dart';

/// 目录（大纲）面板。
class OutlinePanel extends StatelessWidget {
  const OutlinePanel({
    required this.outline,
    required this.controller,
    super.key,
  });

  final List<PdfOutlineNode>? outline;
  final PdfViewerController controller;

  @override
  Widget build(BuildContext context) {
    final list = _flat(outline, 0).toList();
    if (list.isEmpty) {
      return const Center(
        child: Text('本文档没有目录', style: TextStyle(color: Colors.grey)),
      );
    }
    return ListView.builder(
      itemCount: list.length,
      itemBuilder: (context, i) {
        final it = list[i];
        return InkWell(
          onTap: it.node.dest == null
              ? null
              : () => controller.goToDest(it.node.dest),
          child: Padding(
            padding: EdgeInsets.only(
              left: it.level * 14.0 + 12,
              top: 9,
              bottom: 9,
              right: 8,
            ),
            child: Text(
              it.node.title,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: it.level == 0 ? 13.5 : 12.5,
                fontWeight: it.level == 0 ? FontWeight.w600 : null,
              ),
            ),
          ),
        );
      },
    );
  }

  Iterable<({PdfOutlineNode node, int level})> _flat(
    List<PdfOutlineNode>? nodes,
    int level,
  ) sync* {
    if (nodes == null) return;
    for (final n in nodes) {
      yield (node: n, level: level);
      yield* _flat(n.children, level + 1);
    }
  }
}

/// 页面缩略图面板。
class ThumbnailsPanel extends StatelessWidget {
  const ThumbnailsPanel({
    required this.docRef,
    required this.controller,
    required this.currentPage,
    super.key,
  });

  final PdfDocumentRef? docRef;
  final PdfViewerController controller;
  final int currentPage;

  @override
  Widget build(BuildContext context) {
    if (docRef == null) return const SizedBox.shrink();
    return PdfDocumentViewBuilder(
      documentRef: docRef!,
      builder: (context, doc) => GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          childAspectRatio: 0.72,
        ),
        itemCount: doc?.pages.length ?? 0,
        itemBuilder: (context, i) {
          final page = i + 1;
          final cur = page == currentPage;
          return InkWell(
            onTap: () => controller.goToPage(
              pageNumber: page,
              anchor: PdfPageAnchor.top,
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: cur
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.withValues(alpha: 0.4),
                        width: cur ? 2 : 1,
                      ),
                    ),
                    child: doc == null
                        ? const SizedBox.shrink()
                        : PdfPageView(
                            document: doc,
                            pageNumber: page,
                            alignment: Alignment.center,
                            maximumDpi: 90,
                          ),
                  ),
                ),
                Text(
                  '$page',
                  style: TextStyle(
                    fontSize: 11,
                    color: cur
                        ? Theme.of(context).colorScheme.primary
                        : Colors.grey,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// 批注列表面板。
class AnnotationsPanel extends StatelessWidget {
  const AnnotationsPanel({
    required this.docData,
    required this.onTap,
    required this.onEdit,
    super.key,
  });

  final DocDataStore docData;
  final void Function(Annotation) onTap;
  final void Function(Annotation) onEdit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: docData,
      builder: (context, _) {
        final items = [...docData.annotations]
          ..sort((a, b) => a.page.compareTo(b.page));
        if (items.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                '选中文字后右键（或长按）即可高亮/记笔记',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ),
          );
        }
        return ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final a = items[i];
            return ListTile(
              dense: true,
              leading: CircleAvatar(
                radius: 7,
                backgroundColor: Color(a.colorValue),
              ),
              title: Text(
                a.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5),
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (a.hasNote)
                    Text(
                      a.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  Text(
                    '第 ${a.page} 页',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit_outlined, size: 17),
                tooltip: '编辑/删除',
                onPressed: () => onEdit(a),
              ),
              onTap: () => onTap(a),
            );
          },
        );
      },
    );
  }
}

/// 书签面板。
class BookmarksPanel extends StatelessWidget {
  const BookmarksPanel({required this.docData, required this.onTap, super.key});

  final DocDataStore docData;
  final void Function(Bookmark) onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: docData,
      builder: (context, _) {
        if (docData.bookmarks.isEmpty) {
          return const Center(
            child: Text('点击工具栏书签图标收藏当前页', style: TextStyle(color: Colors.grey)),
          );
        }
        return ListView.builder(
          itemCount: docData.bookmarks.length,
          itemBuilder: (context, i) {
            final b = docData.bookmarks[i];
            return ListTile(
              dense: true,
              leading: const Icon(Icons.bookmark, size: 18),
              title: Text('第 ${b.page} 页'),
              onTap: () => onTap(b),
            );
          },
        );
      },
    );
  }
}

/// 文档内搜索面板（基于 PdfTextSearcher）。
class SearchPanel extends StatefulWidget {
  const SearchPanel({required this.searcher, super.key});

  final PdfTextSearcher? searcher;

  @override
  State<SearchPanel> createState() => _SearchPanelState();
}

class _SearchPanelState extends State<SearchPanel> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _pageTextCache = <int, PdfPageText>{};
  final _matchIndexToListIndex = <int>[];
  final _listIndexToMatchIndex = <int>[];
  int? _session;

  PdfTextSearcher? get s => widget.searcher;

  @override
  void initState() {
    super.initState();
    s?.addListener(_updated);
    _text.addListener(() => s?.startTextSearch(_text.text));
  }

  @override
  void didUpdateWidget(covariant SearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searcher != widget.searcher) {
      oldWidget.searcher?.removeListener(_updated);
      widget.searcher?.addListener(_updated);
      _session = null;
      _matchIndexToListIndex.clear();
      _listIndexToMatchIndex.clear();
      _pageTextCache.clear();
    }
  }

  @override
  void dispose() {
    s?.removeListener(_updated);
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _updated() {
    final t = s;
    if (t == null) return;
    if (_session != t.searchSession) {
      _session = t.searchSession;
      _matchIndexToListIndex.clear();
      _listIndexToMatchIndex.clear();
    }
    for (var i = _matchIndexToListIndex.length; i < t.matches.length; i++) {
      if (i == 0 || t.matches[i - 1].pageNumber != t.matches[i].pageNumber) {
        _listIndexToMatchIndex.add(-t.matches[i].pageNumber);
      }
      _matchIndexToListIndex.add(_listIndexToMatchIndex.length);
      _listIndexToMatchIndex.add(i);
    }
    if (mounted) setState(() {});
  }

  Future<PdfPageText?> _loadText(int page) async {
    final cached = _pageTextCache[page];
    if (cached != null) return cached;
    final t = await s?.loadText(pageNumber: page);
    if (t != null) _pageTextCache[page] = t;
    if (_pageTextCache.length > 60) {
      _pageTextCache.remove(_pageTextCache.keys.first);
    }
    return t;
  }

  void _scrollToCurrent() {
    final t = s;
    if (t == null || t.currentIndex == null || !_scroll.hasClients) return;
    const itemH = 56.0;
    final pos = _scroll.position;
    final listIdx = _matchIndexToListIndex[t.currentIndex!];
    final newPos = itemH * listIdx;
    if (newPos + itemH > pos.pixels + pos.viewportDimension) {
      _scroll.animateTo(
        newPos + itemH - pos.viewportDimension,
        duration: const Duration(milliseconds: 250),
        curve: Curves.decelerate,
      );
    } else if (newPos < pos.pixels) {
      _scroll.animateTo(
        newPos,
        duration: const Duration(milliseconds: 250),
        curve: Curves.decelerate,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = s;
    if (t == null) {
      return const Center(
        child: Text('文档未就绪', style: TextStyle(color: Colors.grey)),
      );
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '在文档中搜索…',
                    border: const OutlineInputBorder(),
                    suffixText: t.hasMatches
                        ? '${(t.currentIndex ?? 0) + 1}/${t.matches.length}'
                        : null,
                    suffixIcon: _text.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _text.clear();
                              t.resetTextSearch();
                            },
                          )
                        : null,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: (t.currentIndex ?? 0) > 0
                    ? () => t.goToPrevMatch().then((_) => _scrollToCurrent())
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: (t.currentIndex ?? 0) < t.matches.length - 1
                    ? () => t.goToNextMatch().then((_) => _scrollToCurrent())
                    : null,
              ),
            ],
          ),
        ),
        SizedBox(
          height: 4,
          child: t.isSearching
              ? LinearProgressIndicator(value: t.searchProgress)
              : null,
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: _listIndexToMatchIndex.length,
            itemBuilder: (context, i) {
              final matchIndex = _listIndexToMatchIndex[i];
              if (matchIndex < 0) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 10, 2),
                  child: Text(
                    '第 ${-matchIndex} 页',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                );
              }
              final m = t.matches[matchIndex];
              return _MatchTile(
                match: m,
                isCurrent: matchIndex == t.currentIndex,
                loadText: _loadText,
                onTap: () async {
                  await t.goToMatchOfIndex(matchIndex);
                  if (mounted) setState(() {});
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MatchTile extends StatefulWidget {
  const _MatchTile({
    required this.match,
    required this.isCurrent,
    required this.loadText,
    required this.onTap,
  });

  final PdfPageTextRange match;
  final bool isCurrent;
  final Future<PdfPageText?> Function(int page) loadText;
  final VoidCallback onTap;

  @override
  State<_MatchTile> createState() => _MatchTileState();
}

class _MatchTileState extends State<_MatchTile> {
  PdfPageText? _text;

  @override
  void initState() {
    super.initState();
    widget.loadText(widget.match.pageNumber).then((t) {
      if (mounted) setState(() => _text = t);
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.match;
    final full = _text?.fullText ?? m.text;
    var start = m.start;
    var end = m.end;
    // 上下文片段：扩展到前后句子边界或 ±40 字
    while (start > 0 && m.start - start < 40 && full[start - 1] != '\n') {
      start--;
    }
    while (end < full.length && end - m.end < 40 && full[end] != '\n') {
      end++;
    }
    start = start.clamp(0, m.start);
    end = end.clamp(m.end, full.length);
    final cur = widget.isCurrent;
    return InkWell(
      onTap: widget.onTap,
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        color: cur
            ? Theme.of(context).colorScheme.primaryContainer
                  .withValues(alpha: 0.4)
            : null,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: full.substring(start, m.start.clamp(start, full.length)),
              ),
              TextSpan(
                text: m.text,
                style: const TextStyle(
                  backgroundColor: Color(0x99FFD54F),
                  color: Colors.black87,
                ),
              ),
              TextSpan(text: full.substring(m.end.clamp(0, full.length), end)),
            ],
          ),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }
}
