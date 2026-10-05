import 'dart:convert';

/// 文档身份：与文件路径解耦，用内容指纹，文件移动后仍能匹配笔记。
String docKeyFor({required int size, required String headHash}) =>
    'd$headHash-${size.toRadixString(16)}';

class LibraryEntry {
  LibraryEntry({
    required this.key,
    required this.path,
    required this.title,
    this.pageCount = 0,
    this.lastPage = 1,
    this.zoom,
    required this.lastOpened,
  });

  final String key;
  String path;
  String title;
  int pageCount;
  int lastPage;
  double? zoom;
  DateTime lastOpened;

  double get progress =>
      pageCount <= 0 ? 0 : (lastPage / pageCount).clamp(0, 1);

  Map<String, dynamic> toJson() => {
    'key': key,
    'path': path,
    'title': title,
    'pageCount': pageCount,
    'lastPage': lastPage,
    'zoom': zoom,
    'lastOpened': lastOpened.millisecondsSinceEpoch,
  };

  factory LibraryEntry.fromJson(Map<String, dynamic> j) => LibraryEntry(
    key: j['key'] as String,
    path: j['path'] as String? ?? '',
    title: j['title'] as String? ?? '未命名',
    pageCount: j['pageCount'] as int? ?? 0,
    lastPage: j['lastPage'] as int? ?? 1,
    zoom: (j['zoom'] as num?)?.toDouble(),
    lastOpened: DateTime.fromMillisecondsSinceEpoch(
      j['lastOpened'] as int? ?? 0,
    ),
  );
}

/// 高亮/笔记批注。rects 为 PDF 页面坐标（l,t,r,b，t>b）。
class Annotation {
  Annotation({
    required this.id,
    required this.page,
    required this.rects,
    required this.colorValue,
    this.text = '',
    this.note = '',
    required this.createdAt,
  });

  final String id;
  final int page;
  final List<List<double>> rects; // [[l,t,r,b], ...]
  int colorValue;
  String text;
  String note;
  DateTime createdAt;

  bool get hasNote => note.trim().isNotEmpty;

  Map<String, dynamic> toJson() => {
    'id': id,
    'page': page,
    'rects': rects,
    'color': colorValue,
    'text': text,
    'note': note,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Annotation.fromJson(Map<String, dynamic> j) => Annotation(
    id: j['id'] as String,
    page: j['page'] as int,
    rects: [
      for (final r in (j['rects'] as List))
        [for (final v in (r as List)) (v as num).toDouble()],
    ],
    colorValue: j['color'] as int,
    text: j['text'] as String? ?? '',
    note: j['note'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int? ?? 0),
  );
}

class Bookmark {
  Bookmark({required this.page, this.title = '', required this.createdAt});

  final int page;
  String title;
  DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'page': page,
    'title': title,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Bookmark.fromJson(Map<String, dynamic> j) => Bookmark(
    page: j['page'] as int,
    title: j['title'] as String? ?? '',
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int? ?? 0),
  );
}

class ChatMessage {
  ChatMessage({required this.role, required this.content, DateTime? time})
    : time = time ?? DateTime.now();

  final String role; // user | assistant | system
  String content;
  final DateTime time;

  Map<String, dynamic> toJson() => {
    'role': role,
    'content': content,
    'time': time.millisecondsSinceEpoch,
  };

  factory ChatMessage.fromJson(Map<String, dynamic> j) => ChatMessage(
    role: j['role'] as String,
    content: j['content'] as String? ?? '',
    time: DateTime.fromMillisecondsSinceEpoch(j['time'] as int? ?? 0),
  );
}

/// 复习卡片（SM-2 间隔重复）。
class Flashcard {
  Flashcard({
    required this.id,
    required this.front,
    required this.back,
    this.page,
    this.ease = 2.5,
    this.intervalDays = 0,
    this.reps = 0,
    this.lapses = 0,
    DateTime? due,
    DateTime? createdAt,
  }) : due = due ?? DateTime.now(),
       createdAt = createdAt ?? DateTime.now();

  final String id;
  String front;
  String back;
  int? page;
  double ease;
  int intervalDays;
  int reps;
  int lapses;
  DateTime due;
  DateTime createdAt;

  bool isDue([DateTime? now]) => !due.isAfter(now ?? DateTime.now());

  Map<String, dynamic> toJson() => {
    'id': id,
    'front': front,
    'back': back,
    'page': page,
    'ease': ease,
    'interval': intervalDays,
    'reps': reps,
    'lapses': lapses,
    'due': due.millisecondsSinceEpoch,
    'createdAt': createdAt.millisecondsSinceEpoch,
  };

  factory Flashcard.fromJson(Map<String, dynamic> j) => Flashcard(
    id: j['id'] as String,
    front: j['front'] as String? ?? '',
    back: j['back'] as String? ?? '',
    page: j['page'] as int?,
    ease: (j['ease'] as num?)?.toDouble() ?? 2.5,
    intervalDays: j['interval'] as int? ?? 0,
    reps: j['reps'] as int? ?? 0,
    lapses: j['lapses'] as int? ?? 0,
    due: DateTime.fromMillisecondsSinceEpoch(j['due'] as int? ?? 0),
    createdAt: DateTime.fromMillisecondsSinceEpoch(j['createdAt'] as int? ?? 0),
  );
}

/// AI 提供方种类。
enum AiProviderKind { openaiCompat, claudeCli, codexCli, devinApi }

/// 一个已配置的 AI 提供方（密钥仅存本地设置文件）。
class AiProviderConfig {
  AiProviderConfig({
    required this.id,
    required this.kind,
    required this.name,
    this.apiKey = '',
    this.baseUrl = '',
    this.model = '',
    this.cliPath = '',
    this.extra = const {},
  });

  final String id;
  final AiProviderKind kind;
  String name;
  String apiKey;
  String baseUrl;
  String model;
  String cliPath;
  Map<String, String> extra;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'name': name,
    'apiKey': apiKey,
    'baseUrl': baseUrl,
    'model': model,
    'cliPath': cliPath,
    'extra': extra,
  };

  factory AiProviderConfig.fromJson(Map<String, dynamic> j) => AiProviderConfig(
    id: j['id'] as String,
    kind: AiProviderKind.values.firstWhere(
      (k) => k.name == j['kind'],
      orElse: () => AiProviderKind.openaiCompat,
    ),
    name: j['name'] as String? ?? '',
    apiKey: j['apiKey'] as String? ?? '',
    baseUrl: j['baseUrl'] as String? ?? '',
    model: j['model'] as String? ?? '',
    cliPath: j['cliPath'] as String? ?? '',
    extra: {
      for (final e in (j['extra'] as Map? ?? {}).entries)
        e.key.toString(): e.value.toString(),
    },
  );
}

List<Map<String, dynamic>> decodeJsonList(String raw) =>
    (jsonDecode(raw) as List)
        .map((e) => (e as Map).cast<String, dynamic>())
        .toList();

String newId() =>
    DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
    (DateTime.now().hashCode & 0xffff).toRadixString(36);
