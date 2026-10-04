import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart';

import 'ai/ai.dart';
import 'store.dart';

/// AppDirs 在 main() 里初始化后 override 注入。
final appDirsProvider = Provider<AppDirs>(
  (ref) => throw StateError('AppDirs 未初始化'),
);

final settingsProvider = ChangeNotifierProvider<SettingsStore>(
  (ref) =>
      SettingsStore(JsonFile(ref.watch(appDirsProvider).file('settings.json'))),
);

final libraryProvider = ChangeNotifierProvider<LibraryStore>(
  (ref) =>
      LibraryStore(JsonFile(ref.watch(appDirsProvider).file('library.json'))),
);

final aiServiceProvider = Provider<AiService>(
  (ref) => AiService(ref.watch(settingsProvider)),
);
