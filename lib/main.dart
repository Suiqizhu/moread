import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/shelf_screen.dart';
import 'services/library.dart';
import 'theme/reader_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp, DeviceOrientation.portraitDown]);
  await Library.instance.init();
  await ReaderSettings.instance.load();
  runApp(const MoreadApp());
}

class MoreadApp extends StatelessWidget {
  const MoreadApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3E5C4B);
    return MaterialApp(
      title: '墨读',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          surface: const Color(0xFFF8F7F4),
        ),
        scaffoldBackgroundColor: const Color(0xFFF8F7F4),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFF8F7F4),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          centerTitle: false,
        ),
        splashFactory: InkSparkle.splashFactory,
      ),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const ShelfScreen(),
    );
  }
}
