import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai.dart';
import '../ai/context.dart';
import '../models.dart';
import '../providers.dart';
import 'reader_screen.dart';
import 'settings_screen.dart';

class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({required this.host, super.key});

  final ReaderScreenState host;

  @override
  ConsumerState<AiPanel> createState() => AiPanelState();
}

class AiPanelState extends ConsumerState<AiPanel> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  ContextScope _scope = ContextScope.page;
  bool _running = false;
  bool _cancel = false;
  Map<String, bool> _avail = {};

  ReaderScreenState get host => widget.host;

  @override
  void initState() {
    super.initState();
    host.onAiAction = runAction;
    _refreshAvail();
  }

  @override
  void dispose() {
    if (host.onAiAction != null && identical(host.onAiAction, runAction)) {
      host.onAiAction = null;
    }
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _refreshAvail() async {
    final avail = await ref.read(aiServiceProvider).availability();
    if (mounted) setState(() => _avail = avail);
  }

  /// 组装当前上下文（选中为空时 selection 自动降级到当前页）。
  Future<DocContext> _ctx(ContextScope scope) async {
    var s = scope;
    var sel = '';
    if (s == ContextScope.selection) {
      sel = await host.selectedText();
      if (sel.trim().isEmpty) s = ContextScope.page;
    }
    if (host.document == null) {
      return DocContext(text: '', scope: s);
    }
    return buildContext(
      doc: host.document!,
      scope: s,
      currentPage: host.currentPage,
      selection: sel,
      outline: host.outline,
    );
  }

  AiProvider? get _provider {
    final settings = ref.read(settingsProvider);
    final p = ref
        .read(aiServiceProvider)
        .providerFor(settings.defaultProviderId);
    return p;
  }

  Future<void> _run(
    List<ChatMessage> messages,
    String displayUser, {
    bool jsonMode = false,
  }) async {
    if (_running) return;
    final provider = _provider;
    if (provider == null) {
      _snack('未选择 AI 提供方，请到设置页配置');
      return;
    }
    setState(() => _running = true);
    _cancel = false;
    _lastReq = messages;
    _lastDisplay = displayUser;
    _lastJson = jsonMode;
    final userMsg = ChatMessage(role: 'user', content: displayUser);
    final asst = ChatMessage(role: 'assistant', content: '');
    await host.chat.add(userMsg);
    await host.chat.add(asst);
    _scrollBottom();
    try {
      await for (final chunk in provider.chat(
        AiChatRequest(messages: messages, jsonMode: jsonMode),
      )) {
        if (_cancel) break;
        if (chunk.error != null) {
          asst.content += '\n\n⚠ ${chunk.error}';
        } else if (chunk.text.isNotEmpty) {
          asst.content += chunk.text;
        }
        host.chat.notify(); // 流式期间只刷 UI，不落盘
        _scrollBottom();
        if (chunk.done) break;
      }
      if (asst.content.trim().isEmpty) {
        asst.content = '（无返回内容）';
      }
      await host.chat.update();
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  List<ChatMessage>? _lastReq;
  String? _lastDisplay;
  bool _lastJson = false;

  /// 重试上一次请求（移除失败的一对消息后重发）。
  Future<void> _retry() async {
    final req = _lastReq;
    if (req == null || _running) return;
    final msgs = host.chat.messages;
    if (msgs.length >= 2) {
      msgs.removeRange(msgs.length - 2, msgs.length);
      await host.chat.update();
    }
    await _run(req, _lastDisplay ?? '', jsonMode: _lastJson);
  }

  /// 供工具栏/右键菜单调用的快捷动作。
  Future<void> runAction(String action, ContextScope scope) async {
    if (!ref.read(settingsProvider).aiPanelOpen) host.toggleAiPanel();
    if (host.document == null) return;
    final ctx = await _ctx(scope);
    const labels = {
      'explain': '讲解',
      'translate': '翻译',
      'summarize': '总结',
      'note': '整理笔记',
      'quiz': '生成复习卡片',
    };
    final label = labels[action] ?? action;
    if (action == 'quiz') {
      host.onGenerateCards?.call(scope);
      return;
    }
    final quote = ctx.text.length > 160
        ? '${ctx.text.substring(0, 160)}…'
        : ctx.text;
    await _run(
      Prompts.action(action, ctx),
      '**$label · ${ctx.scope.label}**\n> ${quote.replaceAll('\n', ' ')}',
    );
  }

  Future<void> _send() async {
    final q = _input.text.trim();
    if (q.isEmpty || _running) return;
    _input.clear();
    final ctx = await _ctx(_scope);
    await _run(
      Prompts.chat(
        ctx,
        host.chat.messages.where((m) => m.role != 'system').toList(),
        q,
      ),
      q,
    );
  }

  void _scrollBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _snack(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    return Column(
      children: [
        // provider 选择 + 设置
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: settings.defaultProviderId,
                  isDense: true,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                  ),
                  items: [
                    for (final p in settings.providers)
                      DropdownMenuItem(
                        value: p.id,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _avail[p.id] == true
                                  ? Icons.circle
                                  : Icons.circle_outlined,
                              size: 8,
                              color: _avail[p.id] == true
                                  ? Colors.green
                                  : Colors.grey,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                p.name,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    settings.defaultProviderId = v;
                    settings.save();
                  },
                ),
              ),
              IconButton(
                tooltip: 'AI 设置',
                icon: const Icon(Icons.tune, size: 19),
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  _refreshAvail();
                },
              ),
            ],
          ),
        ),
        // 上下文范围
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
          child: Wrap(
            spacing: 6,
            children: [
              for (final s in ContextScope.values)
                ChoiceChip(
                  label: Text(s.label, style: const TextStyle(fontSize: 12)),
                  visualDensity: VisualDensity.compact,
                  selected: _scope == s,
                  onSelected: (_) => setState(() => _scope = s),
                ),
            ],
          ),
        ),
        // 快捷动作
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              _actionBtn('讲解', Icons.psychology_outlined, 'explain'),
              _actionBtn('翻译', Icons.translate, 'translate'),
              _actionBtn('总结', Icons.summarize_outlined, 'summarize'),
              _actionBtn('笔记', Icons.edit_note, 'note'),
            ],
          ),
        ),
        const Divider(height: 1),
        // 消息列表
        Expanded(
          child: ListenableBuilder(
            listenable: host.chat,
            builder: (context, _) {
              final msgs = host.chat.messages;
              if (msgs.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(
                      '选择上下文范围后点击快捷动作，或直接提问。\nAI 会基于 PDF 文本回答。',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.hintColor, fontSize: 13),
                    ),
                  ),
                );
              }
              return ListView.builder(
                controller: _scroll,
                padding: const EdgeInsets.all(8),
                itemCount: msgs.length,
                itemBuilder: (context, i) => _Bubble(
                  msg: msgs[i],
                  streaming: _running && i == msgs.length - 1,
                  onRetry:
                      msgs[i].role == 'assistant' &&
                          i == msgs.length - 1 &&
                          msgs[i].content == '（无返回内容）' &&
                          _lastReq != null &&
                          !_running
                      ? _retry
                      : null,
                ),
              );
            },
          ),
        ),
        // 输入区
        Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _input,
                  minLines: 1,
                  maxLines: 5,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  decoration: const InputDecoration(
                    hintText: '问点什么…（回车发送）',
                    border: OutlineInputBorder(),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              _running
                  ? IconButton.filled(
                      icon: const Icon(Icons.stop, size: 18),
                      tooltip: '停止',
                      onPressed: () => _cancel = true,
                    )
                  : IconButton.filled(
                      icon: const Icon(Icons.send, size: 18),
                      tooltip: '发送',
                      onPressed: _send,
                    ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actionBtn(String label, IconData icon, String action) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 15),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        minimumSize: Size.zero,
        visualDensity: VisualDensity.compact,
      ),
      onPressed: _running ? null : () => runAction(action, _scope),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.msg, required this.streaming, this.onRetry});

  final ChatMessage msg;
  final bool streaming;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = msg.role == 'user';
    final theme = Theme.of(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: isUser
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectionArea(
              child: Text(
                streaming && !isUser ? '${msg.content}▍' : msg.content,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
            if (!isUser && msg.content.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onRetry != null)
                      InkWell(
                        onTap: onRetry,
                        child: const Padding(
                          padding: EdgeInsets.only(top: 2, right: 6),
                          child: Icon(
                            Icons.refresh,
                            size: 14,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ),
                    InkWell(
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: msg.content)),
                      child: const Padding(
                        padding: EdgeInsets.only(top: 2),
                        child: Icon(Icons.copy, size: 13, color: Colors.grey),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
