import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'models.dart';

/// 应用数据目录（应用支持目录/pdf_study）。
class AppDirs {
  AppDirs(this.root);

  final Directory root;

  Directory get docs => Directory('${root.path}/docs');
  Directory get chats => Directory('${root.path}/chats');
  Directory get decks => Directory('${root.path}/decks');

  static Future<AppDirs> open() async {
    final base = await getApplicationSupportDirectory();
    final root = Directory('${base.path}/pdf_study');
    await root.create(recursive: true);
    final dirs = AppDirs(root);
    await dirs.docs.create(recursive: true);
    await dirs.chats.create(recursive: true);
    await dirs.decks.create(recursive: true);
    return dirs;
  }

  File file(String name) => File('${root.path}/$name');
}

/// 原子 JSON 文件读写。写入按实例串行排队，避免并发写同一 .tmp 丢数据。
class JsonFile {
  JsonFile(this.file);

  final File file;
  Future<void> _tail = Future.value();

  Future<dynamic> read() async {
    try {
      if (!await file.exists()) return null;
      return jsonDecode(await file.readAsString());
    } catch (_) {
      return null; // 损坏文件不阻塞启动
    }
  }

  Future<void> write(dynamic value) {
    final op = _tail.then((_) async {
      await file.parent.create(recursive: true);
      final tmp = File('${file.path}.tmp');
      await tmp.writeAsString(jsonEncode(value));
      await tmp.rename(file.path);
    });
    _tail = op.then((_) {}, onError: (_) {});
    return op;
  }
}

/// 计算文档身份指纹：采样内容哈希（头/中/尾）+ 大小，不读全文件。
Future<String> fingerprintFile(String path) async {
  final f = File(path);
  final size = await f.length();
  final raf = await f.open();
  try {
    const chunk = 64 * 1024;
    final buf = BytesBuilder(copy: false);
    Future<void> feed(int offset, int len) async {
      if (len <= 0) return;
      await raf.setPosition(offset);
      buf.add(await raf.read(len));
    }

    await feed(0, size < chunk ? size : chunk);
    if (size > chunk * 2) {
      final mid = size ~/ 2 - chunk ~/ 2;
      await feed(mid, chunk);
    }
    if (size > chunk) {
      await feed(size - chunk, chunk);
    }
    buf.add(utf8.encode('/$size'));
    final hex = sha256.convert(buf.toBytes()).toString();
    return docKeyFor(size: size, headHash: hex.substring(0, 16));
  } finally {
    await raf.close();
  }
}

class SettingsStore extends ChangeNotifier {
  SettingsStore(this._file);

  final JsonFile _file;

  List<AiProviderConfig> providers = [];
  String defaultProviderId = '';
  bool sidebarOpen = true;
  bool aiPanelOpen = true;
  int themeMode = 0; // 0 system 1 light 2 dark

  static List<AiProviderConfig> _builtin() => [
    AiProviderConfig(
      id: 'deepseek',
      kind: AiProviderKind.openaiCompat,
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
    ),
    AiProviderConfig(
      id: 'openai_compat',
      kind: AiProviderKind.openaiCompat,
      name: 'OpenAI 兼容接口',
      baseUrl: '',
      model: '',
    ),
    AiProviderConfig(
      id: 'claude_cli',
      kind: AiProviderKind.claudeCli,
      name: 'Claude Code (本地 CLI)',
      cliPath: 'claude',
    ),
    AiProviderConfig(
      id: 'codex_cli',
      kind: AiProviderKind.codexCli,
      name: 'Codex (本地 CLI)',
      cliPath: 'codex',
    ),
    AiProviderConfig(
      id: 'devin',
      kind: AiProviderKind.devinApi,
      name: 'Devin Cloud',
      baseUrl: 'https://api.devin.ai',
    ),
  ];

  Future<void> load() async {
    final j = await _file.read();
    if (j is Map) {
      providers = [
        for (final e in (j['providers'] as List? ?? []))
          AiProviderConfig.fromJson((e as Map).cast<String, dynamic>()),
      ];
      for (final b in _builtin()) {
        if (!providers.any((p) => p.id == b.id)) providers.add(b);
      }
      defaultProviderId = j['defaultProviderId'] as String? ?? '';
      sidebarOpen = j['sidebarOpen'] as bool? ?? true;
      aiPanelOpen = j['aiPanelOpen'] as bool? ?? true;
      themeMode = j['themeMode'] as int? ?? 0;
    } else {
      providers = _builtin();
      defaultProviderId = 'deepseek';
    }
    if (!providers.any((p) => p.id == defaultProviderId)) {
      defaultProviderId = providers.isNotEmpty ? providers.first.id : '';
    }
    notifyListeners();
  }

  AiProviderConfig? provider(String id) {
    for (final p in providers) {
      if (p.id == id) return p;
    }
    return null;
  }

  AiProviderConfig? get defaultProvider => provider(defaultProviderId);

  Future<void> save() async {
    await _file.write({
      'providers': providers.map((p) => p.toJson()).toList(),
      'defaultProviderId': defaultProviderId,
      'sidebarOpen': sidebarOpen,
      'aiPanelOpen': aiPanelOpen,
      'themeMode': themeMode,
    });
    notifyListeners();
  }
}

class LibraryStore extends ChangeNotifier {
  LibraryStore(this._file);

  final JsonFile _file;
  List<LibraryEntry> entries = [];

  Future<void> load() async {
    final j = await _file.read();
    if (j is List) {
      entries = [
        for (final e in j)
          LibraryEntry.fromJson((e as Map).cast<String, dynamic>()),
      ];
    }
    notifyListeners();
  }

  LibraryEntry? byKey(String key) {
    for (final e in entries) {
      if (e.key == key) return e;
    }
    return null;
  }

  Future<LibraryEntry> touch({
    required String key,
    required String path,
    required String title,
    int? pageCount,
    int? lastPage,
    double? zoom,
  }) async {
    var e = byKey(key);
    if (e == null) {
      e = LibraryEntry(
        key: key,
        path: path,
        title: title,
        lastOpened: DateTime.now(),
      );
      entries.insert(0, e);
    }
    e.path = path;
    e.title = title;
    if (pageCount != null) e.pageCount = pageCount;
    if (lastPage != null) e.lastPage = lastPage;
    if (zoom != null) e.zoom = zoom;
    e.lastOpened = DateTime.now();
    entries.sort((a, b) => b.lastOpened.compareTo(a.lastOpened));
    await _save();
    return e;
  }

  Future<void> remove(String key) async {
    entries.removeWhere((e) => e.key == key);
    await _save();
  }

  Future<void> _save() async {
    await _file.write(entries.map((e) => e.toJson()).toList());
    notifyListeners();
  }
}

/// 单文档数据：批注、书签（随 `docs/<key>.json` 持久化）。
class DocDataStore extends ChangeNotifier {
  DocDataStore(this._file);

  final JsonFile _file;
  List<Annotation> annotations = [];
  List<Bookmark> bookmarks = [];

  Future<void> load() async {
    final j = await _file.read();
    if (j is Map) {
      annotations = [
        for (final e in (j['annotations'] as List? ?? []))
          Annotation.fromJson((e as Map).cast<String, dynamic>()),
      ];
      bookmarks = [
        for (final e in (j['bookmarks'] as List? ?? []))
          Bookmark.fromJson((e as Map).cast<String, dynamic>()),
      ];
      notifyListeners();
    }
  }

  Future<void> addAnnotation(Annotation a) async {
    annotations.add(a);
    await _save();
  }

  Future<void> updateAnnotation(Annotation a) async => _save();

  Future<void> removeAnnotation(String id) async {
    annotations.removeWhere((a) => a.id == id);
    await _save();
  }

  List<Annotation> onPage(int page) =>
      annotations.where((a) => a.page == page).toList();

  bool isBookmarked(int page) => bookmarks.any((b) => b.page == page);

  Future<void> toggleBookmark(int page) async {
    if (isBookmarked(page)) {
      bookmarks.removeWhere((b) => b.page == page);
    } else {
      bookmarks.add(Bookmark(page: page, createdAt: DateTime.now()));
    }
    bookmarks.sort((a, b) => a.page.compareTo(b.page));
    await _save();
  }

  Future<void> _save() async {
    await _file.write({
      'annotations': annotations.map((a) => a.toJson()).toList(),
      'bookmarks': bookmarks.map((b) => b.toJson()).toList(),
    });
    notifyListeners();
  }
}

class ChatStore extends ChangeNotifier {
  ChatStore(this._file);

  final JsonFile _file;
  List<ChatMessage> messages = [];

  Future<void> load() async {
    final j = await _file.read();
    if (j is List) {
      messages = [
        for (final e in j)
          ChatMessage.fromJson((e as Map).cast<String, dynamic>()),
      ];
      notifyListeners();
    }
  }

  Future<void> add(ChatMessage m) async {
    messages.add(m);
    await _save();
  }

  Future<void> update() async {
    await _file.write(messages.map((m) => m.toJson()).toList());
    notifyListeners();
  }

  /// 只刷新 UI 不落盘（流式期间每个 chunk 调用）。
  void notify() => notifyListeners();

  Future<void> clear() async {
    messages.clear();
    await _save();
  }

  Future<void> _save() async => update();
}

class DeckStore extends ChangeNotifier {
  DeckStore(this._file);

  final JsonFile _file;
  List<Flashcard> cards = [];

  Future<void> load() async {
    final j = await _file.read();
    if (j is List) {
      cards = [
        for (final e in j)
          Flashcard.fromJson((e as Map).cast<String, dynamic>()),
      ];
      notifyListeners();
    }
  }

  Future<void> addAll(Iterable<Flashcard> newCards) async {
    cards.addAll(newCards);
    await _save();
  }

  Future<void> remove(String id) async {
    cards.removeWhere((c) => c.id == id);
    await _save();
  }

  Future<void> update() async {
    await _file.write(cards.map((c) => c.toJson()).toList());
    notifyListeners();
  }

  Future<void> _save() async => update();

  int dueCount([DateTime? now]) => cards.where((c) => c.isDue(now)).length;
}
