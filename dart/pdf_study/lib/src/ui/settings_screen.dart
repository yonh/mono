import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../providers.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  Map<String, bool> _avail = {};
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() => _checking = true);
    final a = await ref.read(aiServiceProvider).availability();
    if (mounted) {
      setState(() {
        _avail = a;
        _checking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('设置 · AI 提供方'),
        actions: [
          IconButton(
            tooltip: '重新检测可用性',
            onPressed: _checking ? null : _check,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '默认 AI 提供方',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: settings.defaultProviderId,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final p in settings.providers)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        settings.defaultProviderId = v;
                        settings.save();
                      }
                    },
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'API Key 仅保存在本机设置文件中，不会上传。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          for (final p in settings.providers)
            _ProviderCard(config: p, available: _avail[p.id]),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              final c = AiProviderConfig(
                id: newId(),
                kind: AiProviderKind.openaiCompat,
                name: '自定义 OpenAI 兼容接口',
              );
              settings.providers.add(c);
              await settings.save();
              setState(() {});
            },
            icon: const Icon(Icons.add),
            label: const Text(
              '添加 OpenAI 兼容接口（Moonshot / Qwen / Ollama / vLLM…）',
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'CLI 提供方（Claude Code / Codex）调用本机已登录的命令行工具；Devin Cloud 通过 API 创建云端会话执行任务。',
            style: TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

class _ProviderCard extends ConsumerStatefulWidget {
  const _ProviderCard({required this.config, this.available});

  final AiProviderConfig config;
  final bool? available;

  @override
  ConsumerState<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends ConsumerState<_ProviderCard> {
  late final TextEditingController _key;
  late final TextEditingController _base;
  late final TextEditingController _model;
  late final TextEditingController _cli;
  late final TextEditingController _name;

  AiProviderConfig get c => widget.config;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: c.name);
    _key = TextEditingController(text: c.apiKey);
    _base = TextEditingController(text: c.baseUrl);
    _model = TextEditingController(text: c.model);
    _cli = TextEditingController(text: c.cliPath);
  }

  @override
  void dispose() {
    _name.dispose();
    _key.dispose();
    _base.dispose();
    _model.dispose();
    _cli.dispose();
    super.dispose();
  }

  Future<void> _apply() async {
    c.name = _name.text.trim().isEmpty ? c.name : _name.text.trim();
    c.apiKey = _key.text.trim();
    c.baseUrl = _base.text.trim();
    c.model = _model.text.trim();
    c.cliPath = _cli.text.trim();
    await ref.read(settingsProvider).save();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final builtin = [
      'deepseek',
      'openai_compat',
      'claude_cli',
      'codex_cli',
      'devin',
    ].contains(c.id);
    final avail = widget.available;
    return Card(
      child: ExpansionTile(
        initiallyExpanded: c.id == 'deepseek',
        leading: Icon(
          avail == true ? Icons.check_circle : Icons.help_outline,
          size: 18,
          color: avail == true ? Colors.green : Colors.grey,
        ),
        title: Text(c.name),
        subtitle: Text(switch (c.kind) {
          AiProviderKind.openaiCompat => 'HTTP · OpenAI 兼容',
          AiProviderKind.claudeCli => '本地 CLI · claude',
          AiProviderKind.codexCli => '本地 CLI · codex',
          AiProviderKind.devinApi => '云端 API · Devin',
        }, style: const TextStyle(fontSize: 12)),
        trailing: builtin
            ? null
            : IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () async {
                  final s = ref.read(settingsProvider);
                  s.providers.removeWhere((p) => p.id == c.id);
                  if (s.defaultProviderId == c.id) {
                    s.defaultProviderId = s.providers.isNotEmpty
                        ? s.providers.first.id
                        : '';
                  }
                  await s.save();
                },
              ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Column(
              children: [
                _field('名称', _name),
                if (c.kind == AiProviderKind.openaiCompat ||
                    c.kind == AiProviderKind.devinApi) ...[
                  _field(
                    'API Key',
                    _key,
                    obscure: true,
                    hint: c.kind == AiProviderKind.devinApi
                        ? 'Devin API Key'
                        : 'sk-…',
                  ),
                  _field(
                    'Base URL',
                    _base,
                    hint: c.kind == AiProviderKind.devinApi
                        ? 'https://api.devin.ai'
                        : 'https://api.deepseek.com',
                  ),
                ],
                if (c.kind == AiProviderKind.openaiCompat)
                  _field('模型', _model, hint: 'deepseek-chat'),
                if (c.kind == AiProviderKind.devinApi)
                  _field('模型（可选）', _model, hint: '留空默认'),
                if (c.kind == AiProviderKind.claudeCli ||
                    c.kind == AiProviderKind.codexCli)
                  _field(
                    'CLI 命令或绝对路径',
                    _cli,
                    hint: c.kind == AiProviderKind.claudeCli
                        ? 'claude'
                        : 'codex',
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.tonal(
                    onPressed: _apply,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _field(
    String label,
    TextEditingController ctrl, {
    bool obscure = false,
    String? hint,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: ctrl,
        obscureText: obscure,
        onChanged: (_) => _apply(),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
