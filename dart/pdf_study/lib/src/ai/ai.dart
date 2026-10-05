import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models.dart';
import '../store.dart';

class AiChatRequest {
  AiChatRequest({
    required this.messages,
    this.jsonMode = false,
    this.maxTokens,
  });

  final List<ChatMessage> messages;
  final bool jsonMode;
  final int? maxTokens;
}

/// 流式输出片段。done=true 表示结束；error 非空表示失败。
class AiChunk {
  AiChunk(this.text, {this.done = false, this.error});

  final String text;
  final bool done;
  final String? error;
}

abstract class AiProvider {
  AiProvider(this.config);

  final AiProviderConfig config;

  /// 配置是否足以发起请求（有 key / CLI 存在）。
  Future<bool> available();

  /// 不可用时的中文原因说明。
  String unavailableReason();

  Stream<AiChunk> chat(AiChatRequest request);
}

/// 解析 OpenAI 兼容 SSE 的 data 行 → 增量文本（[DONE] 或非法行返回 null）。
String? parseOpenAiSseLine(String data) {
  final d = data.trim();
  if (d.isEmpty || d == '[DONE]') return null;
  try {
    final j = jsonDecode(d) as Map<String, dynamic>;
    final choices = j['choices'] as List?;
    if (choices == null || choices.isEmpty) return null;
    final delta = (choices.first as Map)['delta'] as Map?;
    final c = delta?['content'];
    return c is String ? c : null;
  } catch (_) {
    return null;
  }
}

/// 把字节流按 SSE 事件切分为 data 载荷字符串。
Stream<String> sseDataStream(Stream<List<int>> byteStream) async* {
  var buf = '';
  await for (final chunk in byteStream.transform(utf8.decoder)) {
    buf += chunk;
    int idx;
    while ((idx = buf.indexOf('\n')) >= 0) {
      var line = buf.substring(0, idx);
      buf = buf.substring(idx + 1);
      if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
      if (line.startsWith('data:')) {
        yield line.substring(5).trimLeft();
      }
    }
  }
  if (buf.startsWith('data:')) yield buf.substring(5).trimLeft();
}

class OpenAiCompatProvider extends AiProvider {
  OpenAiCompatProvider(super.config);

  @override
  Future<bool> available() async =>
      config.apiKey.trim().isNotEmpty && config.baseUrl.trim().isNotEmpty;

  @override
  String unavailableReason() => config.apiKey.trim().isEmpty
      ? '未填写 API Key（到设置里配置 ${config.name}）'
      : '未填写 Base URL';

  @override
  Stream<AiChunk> chat(AiChatRequest request) async* {
    final base = config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final uri = Uri.parse(
      base.endsWith('/chat/completions') ? base : '$base/chat/completions',
    );
    final body = <String, dynamic>{
      'model': config.model.trim().isEmpty
          ? 'deepseek-chat'
          : config.model.trim(),
      'messages': [
        for (final m in request.messages)
          {'role': m.role, 'content': m.content},
      ],
      'stream': true,
      if (request.maxTokens != null) 'max_tokens': request.maxTokens,
      if (request.jsonMode) 'response_format': {'type': 'json_object'},
    };
    try {
      final req = http.Request('POST', uri)
        ..headers['Content-Type'] = 'application/json'
        ..headers['Authorization'] = 'Bearer ${config.apiKey.trim()}'
        ..body = jsonEncode(body);
      final client = http.Client();
      try {
        final resp = await client
            .send(req)
            .timeout(const Duration(seconds: 30));
        if (resp.statusCode != 200) {
          final text = await resp.stream.bytesToString();
          yield AiChunk(
            '',
            done: true,
            error:
                'HTTP ${resp.statusCode}: ${text.length > 300 ? text.substring(0, 300) : text}',
          );
          return;
        }
        await for (final data in sseDataStream(resp.stream)) {
          if (data == '[DONE]') break;
          final delta = parseOpenAiSseLine(data);
          if (delta != null && delta.isNotEmpty) yield AiChunk(delta);
        }
        yield AiChunk('', done: true);
      } finally {
        client.close();
      }
    } catch (e) {
      yield AiChunk('', done: true, error: '网络错误：$e');
    }
  }
}

/// 本地 CLI Agent（claude / codex）。把会话拼成单条 prompt 交给 CLI 非交互执行。
class CliAgentProvider extends AiProvider {
  CliAgentProvider(super.config);

  @override
  Future<bool> available() async => (await _resolveCli()) != null;

  @override
  String unavailableReason() =>
      '未找到 CLI `${config.cliPath}`（确认已安装并在 PATH 中，或在设置里填绝对路径）';

  static final _cliNamePattern = RegExp(r'^[A-Za-z0-9._-]+$');

  Future<String?> _resolveCli() async {
    final p = config.cliPath.trim();
    if (p.isEmpty) return null;
    if (p.contains('/')) {
      // 显式路径：文件检查即可，不经过 shell
      return await File(p).exists() ? p : null;
    }
    // 裸命令名才走 shell 查找；白名单字符防止命令名注入 bash -lc
    if (!_cliNamePattern.hasMatch(p)) return null;
    try {
      final r = await Process.run('/bin/bash', [
        '-lc',
        'command -v $p',
      ], runInShell: false);
      final out = (r.stdout as String).trim();
      if (r.exitCode == 0 && out.isNotEmpty) {
        return out.split('\n').first.trim();
      }
    } catch (_) {}
    for (final dir in [
      '/opt/homebrew/bin',
      '/usr/local/bin',
      '${Platform.environment['HOME']}/.local/bin',
      '${Platform.environment['HOME']}/.npm-global/bin',
    ]) {
      if (await File('$dir/$p').exists()) return '$dir/$p';
    }
    return null;
  }

  String _composePrompt(List<ChatMessage> messages) {
    final b = StringBuffer();
    for (final m in messages) {
      switch (m.role) {
        case 'system':
          b.writeln('【系统指令】\n${m.content}\n');
        case 'assistant':
          b.writeln('【助手此前的回答】\n${m.content}\n');
        default:
          b.writeln('【用户】\n${m.content}\n');
      }
    }
    return b.toString();
  }

  List<String> _argsFor(String prompt) {
    if (config.kind == AiProviderKind.claudeCli) {
      return ['-p', prompt, '--output-format', 'text'];
    }
    // codex exec 非交互模式
    return ['exec', '--skip-git-repo-check', prompt];
  }

  @override
  Stream<AiChunk> chat(AiChatRequest request) async* {
    final exe = await _resolveCli();
    if (exe == null) {
      yield AiChunk('', done: true, error: unavailableReason());
      return;
    }
    try {
      final args = _argsFor(_composePrompt(request.messages));
      final env = Map<String, String>.from(Platform.environment);
      // 保证登录 shell 的 PATH 对子进程可用
      try {
        final r = await Process.run('/bin/bash', ['-lc', 'echo \$PATH']);
        if (r.exitCode == 0) env['PATH'] = (r.stdout as String).trim();
      } catch (_) {}
      Process? proc;
      try {
        proc = await Process.start(
          exe,
          args,
          environment: env,
          mode: ProcessStartMode.normal,
        );
        var gotOutput = false;
        proc.stderr.transform(utf8.decoder).drain<void>(); // 静默 stderr
        await for (final chunk in proc.stdout.transform(utf8.decoder)) {
          if (chunk.isNotEmpty) {
            gotOutput = true;
            yield AiChunk(chunk);
          }
        }
        final code = await proc.exitCode;
        if (code != 0 && !gotOutput) {
          yield AiChunk(
            '',
            done: true,
            error: '${config.name} 退出码 $code（可能未登录或参数不兼容）',
          );
          return;
        }
        yield AiChunk('', done: true);
      } finally {
        // 流被取消（用户点停止）时终止子进程，避免 CLI 残留跑资源
        proc?.kill();
      }
    } catch (e) {
      yield AiChunk('', done: true, error: '启动 ${config.name} 失败：$e');
    }
  }
}

/// Devin Cloud：创建会话 → 轮询直到完成 → 返回最终答复。
class DevinApiProvider extends AiProvider {
  DevinApiProvider(super.config);

  @override
  Future<bool> available() async => config.apiKey.trim().isNotEmpty;

  @override
  String unavailableReason() =>
      '未填写 Devin API Key（Settings → API Keys 创建服务用户密钥）';

  String get _base => config.baseUrl.trim().isEmpty
      ? 'https://api.devin.ai'
      : config.baseUrl.trim().replaceAll(RegExp(r'/+$'), '');

  Map<String, String> get _headers => {
    'Authorization': 'Bearer ${config.apiKey.trim()}',
    'Content-Type': 'application/json',
  };

  @override
  Stream<AiChunk> chat(AiChatRequest request) async* {
    final prompt = _composePrompt(request.messages);
    final client = http.Client();
    try {
      final created = await client
          .post(
            Uri.parse('$_base/v3/sessions'),
            headers: _headers,
            body: jsonEncode({'prompt': prompt}),
          )
          .timeout(const Duration(seconds: 30));
      if (created.statusCode >= 300) {
        yield AiChunk(
          '',
          done: true,
          error:
              '创建 Devin 会话失败 HTTP ${created.statusCode}: ${_clip(created.body)}',
        );
        return;
      }
      final cj = jsonDecode(created.body) as Map<String, dynamic>;
      final sid = cj['session_id'] as String? ?? cj['id'] as String?;
      if (sid == null) {
        yield AiChunk(
          '',
          done: true,
          error: '创建 Devin 会话返回异常：${_clip(created.body)}',
        );
        return;
      }
      yield AiChunk('已创建 Devin 会话 $sid，云端执行中…\n');
      // 轮询
      final deadline = DateTime.now().add(const Duration(minutes: 15));
      var lastLen = 0;
      while (DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(seconds: 5));
        final g = await client
            .get(Uri.parse('$_base/v3/sessions/$sid'), headers: _headers)
            .timeout(const Duration(seconds: 30));
        if (g.statusCode >= 300) continue;
        final gj = jsonDecode(g.body) as Map<String, dynamic>;
        final out = gj['structured_output'];
        final status = (gj['status'] ?? '').toString().toLowerCase();
        // v3 可能直接返回结构化输出或最后消息
        final text = _extractResult(gj);
        if (text != null && text.length > lastLen) {
          yield AiChunk(text.substring(lastLen));
          lastLen = text.length;
        }
        if (status.contains('finish') ||
            status.contains('stop') ||
            status.contains('suspend') ||
            out != null) {
          yield AiChunk('', done: true);
          return;
        }
      }
      yield AiChunk('', done: true, error: 'Devin 会话超时（15 分钟）');
    } catch (e) {
      yield AiChunk('', done: true, error: 'Devin API 错误：$e');
    } finally {
      client.close();
    }
  }

  String _composePrompt(List<ChatMessage> messages) {
    final b = StringBuffer();
    for (final m in messages) {
      if (m.role == 'system') {
        b.writeln('${m.content}\n');
      } else if (m.role == 'assistant') {
        b.writeln('【此前回答】\n${m.content}\n');
      } else {
        b.writeln('${m.content}\n');
      }
    }
    return b.toString();
  }

  String? _extractResult(Map<String, dynamic> j) {
    final so = j['structured_output'];
    if (so is Map && so['result'] is String) return so['result'] as String;
    if (so is String) return so;
    final msgs = j['messages'];
    if (msgs is List) {
      for (final m in msgs.reversed) {
        if (m is Map && (m['source'] == 'agent' || m['role'] == 'assistant')) {
          final t = m['message'] ?? m['content'] ?? m['text'];
          if (t is String && t.isNotEmpty) return t;
        }
      }
    }
    final lm = j['last_message'];
    if (lm is String) return lm;
    return null;
  }

  static String _clip(String s) => s.length > 300 ? s.substring(0, 300) : s;
}

/// 构建 provider 实例并做可用性检查。
class AiService {
  AiService(this.settings);

  final SettingsStore settings;

  AiProvider? providerFor(String id) {
    final c = settings.provider(id);
    if (c == null) return null;
    return switch (c.kind) {
      AiProviderKind.openaiCompat => OpenAiCompatProvider(c),
      AiProviderKind.claudeCli ||
      AiProviderKind.codexCli => CliAgentProvider(c),
      AiProviderKind.devinApi => DevinApiProvider(c),
    };
  }

  /// 各 provider 可用性缓存。
  Future<Map<String, bool>> availability() async {
    final out = <String, bool>{};
    for (final c in settings.providers) {
      out[c.id] = await (providerFor(c.id)?.available() ?? Future.value(false));
    }
    return out;
  }
}
