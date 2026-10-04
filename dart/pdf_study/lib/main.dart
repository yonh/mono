import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'src/providers.dart';
import 'src/store.dart';
import 'src/ui/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  final dirs = await AppDirs.open();
  runApp(
    ProviderScope(
      overrides: [appDirsProvider.overrideWithValue(dirs)],
      child: const PdfStudyApp(),
    ),
  );
}

class PdfStudyApp extends ConsumerWidget {
  const PdfStudyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: '研学 PDF',
      debugShowCheckedModeBanner: false,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('zh', 'CN'), Locale('en')],
      locale: const Locale('zh', 'CN'),
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F6BD8),
        brightness: Brightness.light,
        visualDensity: VisualDensity.standard,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F6BD8),
        brightness: Brightness.dark,
      ),
      home: const LibraryScreen(),
    );
  }
}
