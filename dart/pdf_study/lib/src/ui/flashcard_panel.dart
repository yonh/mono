import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai.dart';
import '../ai/context.dart';
import '../models.dart';
import '../providers.dart';
import '../srs.dart';
import '../store.dart';
import 'reader_screen.dart';

/// 从 AI 输出里提取 JSON 卡片数组（容忍代码块/前后噪文）。
List<Map<String, dynamic>> parseCardsJson(String raw) {
  var s = raw.trim();
  // 去掉 ```json ... ``` 包裹
  final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)```');
  final m = fence.firstMatch(s);
  if (m != null) s = m.group(1)!.trim();
  dynamic j;
  try {
    j = jsonDecode(s);
  } catch (_) {
    final a = s.indexOf('{');
    final b = s.lastIndexOf('}');
    if (a >= 0 && b > a) {
      try {
        j = jsonDecode(s.substring(a, b + 1));
      } catch (_) {
        return [];
      }
    } else {
      // 可能是裸数组
      final la = s.indexOf('[');
      final lb = s.lastIndexOf(']');
      if (la >= 0 && lb > la) {
        try {
          j = {'cards': jsonDecode(s.substring(la, lb + 1))};
        } catch (_) {
          return [];
        }
      } else {
        return [];
      }
    }
  }
  final cards = (j is Map ? j['cards'] : j) as List?;
  if (cards == null) return [];
  return [for (final c in cards) (c as Map).cast<String, dynamic>()];
}

class FlashcardPanel extends ConsumerStatefulWidget {
  const FlashcardPanel({required this.host, super.key});

  final ReaderScreenState host;

  @override
  ConsumerState<FlashcardPanel> createState() => _FlashcardPanelState();
}

class _FlashcardPanelState extends ConsumerState<FlashcardPanel> {
  ContextScope _scope = ContextScope.chapter;
  bool _generating = false;
  bool _reviewing = false;
  bool _showAnswer = false;
  String? _error;

  ReaderScreenState get host => widget.host;
  DeckStore get deck => host.deck;

  @override
  void initState() {
    super.initState();
    host.onGenerateCards = _generate;
  }

  @override
  void dispose() {
    if (host.onGenerateCards != null &&
        identical(host.onGenerateCards, _generate)) {
      host.onGenerateCards = null;
    }
    super.dispose();
  }

  Future<void> _generate(ContextScope scope) async {
    if (_generating) return;
    final settings = ref.read(settingsProvider);
    final provider = ref
        .read(aiServiceProvider)
        .providerFor(settings.defaultProviderId);
    if (provider == null || !await provider.available()) {
      setState(() => _error = provider?.unavailableReason() ?? '未配置 AI 提供方');
      return;
    }
    setState(() {
      _generating = true;
      _error = null;
    });
    try {
      final doc = host.document;
      if (doc == null) return;
      final sel = scope == ContextScope.selection
          ? await host.selectedText()
          : '';
      final ctx = await buildContext(
        doc: doc,
        scope: scope == ContextScope.selection && sel.trim().isEmpty
            ? ContextScope.page
            : scope,
        currentPage: host.currentPage,
        selection: sel,
        outline: host.outline,
        cap: 30000,
      );
      final buf = StringBuffer();
      await for (final c in provider.chat(
        AiChatRequest(messages: Prompts.action('quiz', ctx), jsonMode: true),
      )) {
        if (c.error != null) {
          setState(() => _error = c.error);
          return;
        }
        buf.write(c.text);
        if (c.done) break;
      }
      final parsed = parseCardsJson(buf.toString());
      if (parsed.isEmpty) {
        setState(() => _error = 'AI 返回无法解析为卡片，请重试或换个范围');
        return;
      }
      final cards = [
        for (final c in parsed)
          Flashcard(
            id: newId(),
            front: (c['front'] ?? '').toString(),
            back: (c['back'] ?? '').toString(),
            page: (c['page'] as num?)?.toInt(),
          ),
      ];
      await deck.addAll(cards);
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('已生成 ${cards.length} 张卡片')));
      }
    } finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  void _grade(Flashcard c, int grade) {
    Srs.review(c, grade);
    deck.update();
    setState(() => _showAnswer = false);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: deck,
      builder: (context, _) {
        final due = Srs.dueOrder(deck.cards);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  Text(
                    '共 ${deck.cards.length} 张',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '待复习 ${due.length}',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const Spacer(),
                  if (_reviewing)
                    TextButton(
                      onPressed: () => setState(() {
                        _reviewing = false;
                        _showAnswer = false;
                      }),
                      child: const Text('退出复习'),
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: _reviewing ? _buildReview(due) : _buildManage(due)),
          ],
        );
      },
    );
  }

  Widget _buildManage(List<Flashcard> due) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              const Text('出卡范围', style: TextStyle(fontSize: 12)),
              for (final s in [
                ContextScope.page,
                ContextScope.chapter,
                ContextScope.document,
              ])
                ChoiceChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  selected: _scope == s,
                  onSelected: (_) => setState(() => _scope = s),
                ),
              _generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: () => _generate(_scope),
                      icon: const Icon(Icons.auto_awesome, size: 15),
                      label: const Text(
                        'AI 生成卡片',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
              if (due.isNotEmpty)
                FilledButton.icon(
                  onPressed: () => setState(() => _reviewing = true),
                  icon: const Icon(Icons.play_arrow, size: 15),
                  label: Text(
                    '开始复习 (${due.length})',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              _error!,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12),
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: deck.cards.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      '还没有卡片。选择范围点「AI 生成卡片」开始出题。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: deck.cards.length,
                  itemBuilder: (context, i) {
                    final c = deck.cards[i];
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        c.isDue()
                            ? Icons.radio_button_checked
                            : Icons.check_circle_outline,
                        size: 16,
                        color: c.isDue()
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: Text(
                        c.front,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        '${c.page != null ? '第${c.page}页 · ' : ''}间隔 ${c.intervalDays}d · 复习 ${c.reps} 次',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 17),
                        onPressed: () => deck.remove(c.id),
                      ),
                      onTap: () => _showCardDetail(c),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showCardDetail(Flashcard c) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('卡片'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.front,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const Divider(),
              SelectableText(c.back),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  Widget _buildReview(List<Flashcard> due) {
    if (due.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.celebration_outlined,
              size: 48,
              color: Colors.green,
            ),
            const SizedBox(height: 10),
            const Text('本轮复习完成！'),
            TextButton(
              onPressed: () => setState(() => _reviewing = false),
              child: const Text('返回列表'),
            ),
          ],
        ),
      );
    }
    final c = due.first;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8),
          child: Text(
            '剩余 ${due.length}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: InkWell(
              onTap: () => setState(() => _showAnswer = !_showAnswer),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).dividerColor),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.front,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_showAnswer) ...[
                        const Divider(),
                        const SizedBox(height: 8),
                        SelectableText(
                          c.back,
                          style: const TextStyle(fontSize: 14, height: 1.5),
                        ),
                        if (c.page != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: InkWell(
                              onTap: () =>
                                  host.controller.goToPage(pageNumber: c.page!),
                              child: Text(
                                '→ 跳到第 ${c.page} 页',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                      ] else
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 24),
                            child: Text(
                              '点击翻面',
                              style: TextStyle(
                                color: Theme.of(context).hintColor,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: Row(
            children: [
              for (final (label, grade, color) in [
                ('重来', Srs.gradeAgain, Colors.redAccent),
                ('困难', Srs.gradeHard, Colors.orange),
                ('记得', Srs.gradeGood, Colors.blue),
                ('简单', Srs.gradeEasy, Colors.green),
              ])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(foregroundColor: color),
                      onPressed: _showAnswer
                          ? () => _grade(c, grade)
                          : () => setState(() => _showAnswer = true),
                      child: Text(
                        _showAnswer ? label : '翻面',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
