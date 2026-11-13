import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/library.dart';

/// 一套阅读配色。夜间主题下界面 chrome 也要跟着变深。
class ReaderTheme {
  const ReaderTheme({
    required this.name,
    required this.background,
    required this.text,
    required this.dim,
    required this.chrome,
    required this.chromeText,
    this.isDark = false,
  });

  final String name;
  final Color background;
  final Color text;

  /// 页码、章节名等次要文字。
  final Color dim;

  /// 菜单面板底色。
  final Color chrome;
  final Color chromeText;
  final bool isDark;

  static const List<ReaderTheme> all = [
    ReaderTheme(
      name: '纸白',
      background: Color(0xFFF6F1E6),
      text: Color(0xFF2E2A24),
      dim: Color(0xFF9A917F),
      chrome: Color(0xFFFCF8EF),
      chromeText: Color(0xFF2E2A24),
    ),
    ReaderTheme(
      name: '月白',
      background: Color(0xFFFFFFFF),
      text: Color(0xFF1D1F22),
      dim: Color(0xFF9AA0A6),
      chrome: Color(0xFFFFFFFF),
      chromeText: Color(0xFF1D1F22),
    ),
    ReaderTheme(
      name: '青竹',
      background: Color(0xFFDDE8D6),
      text: Color(0xFF2F3A2C),
      dim: Color(0xFF83917B),
      chrome: Color(0xFFE9F1E3),
      chromeText: Color(0xFF2F3A2C),
    ),
    ReaderTheme(
      name: '暖沙',
      background: Color(0xFFF0E0C8),
      text: Color(0xFF40342A),
      dim: Color(0xFFA08A6E),
      chrome: Color(0xFFF6E9D5),
      chromeText: Color(0xFF40342A),
    ),
    ReaderTheme(
      name: '深夜',
      background: Color(0xFF17181A),
      text: Color(0xFFA8ADB4),
      dim: Color(0xFF6B7076),
      chrome: Color(0xFF222428),
      chromeText: Color(0xFFD5D8DC),
      isDark: true,
    ),
    ReaderTheme(
      name: '纯黑',
      background: Color(0xFF000000),
      text: Color(0xFF8C9195),
      dim: Color(0xFF5A5F63),
      chrome: Color(0xFF121314),
      chromeText: Color(0xFFCFD2D5),
      isDark: true,
    ),
  ];
}

/// 阅读设置，全局共享并持久化到书库目录下的 settings.json。
class ReaderSettings extends ChangeNotifier {
  ReaderSettings._();

  static final ReaderSettings instance = ReaderSettings._();

  double fontSize = 19;
  double lineHeight = 1.8;
  int themeIndex = 0;
  String fontFamily = 'system';

  ReaderTheme get theme => ReaderTheme.all[themeIndex.clamp(0, ReaderTheme.all.length - 1)];

  TextStyle textStyle([Color? color]) => TextStyle(
        fontSize: fontSize,
        height: lineHeight,
        color: color ?? theme.text,
        fontFamily: switch (fontFamily) {
          'serif' => 'serif',
          'sans' => 'sans-serif',
          _ => null,
        },
        letterSpacing: 0.2,
      );

  Future<File> _file() async => File('${(await Library.instance.root).path}/settings.json');

  Future<void> load() async {
    try {
      final f = await _file();
      if (!await f.exists()) return;
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      fontSize = (j['fontSize'] as num?)?.toDouble() ?? fontSize;
      lineHeight = (j['lineHeight'] as num?)?.toDouble() ?? lineHeight;
      themeIndex = (j['themeIndex'] as num?)?.toInt() ?? themeIndex;
      fontFamily = j['fontFamily'] as String? ?? fontFamily;
      notifyListeners();
    } catch (_) {
      // 设置文件坏了就用默认值，不值得打断阅读。
    }
  }

  Timer? _saveTimer;

  /// 拖动滑块会连续触发，合并成一次写盘。
  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), _writeNow);
  }

  Future<void> _writeNow() async {
    try {
      final f = await _file();
      await f.writeAsString(jsonEncode({
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'themeIndex': themeIndex,
        'fontFamily': fontFamily,
      }));
    } catch (_) {}
  }

  void setFontSize(double v) {
    fontSize = v.clamp(13.0, 34.0);
    notifyListeners();
    save();
  }

  void setLineHeight(double v) {
    lineHeight = v.clamp(1.2, 2.6);
    notifyListeners();
    save();
  }

  void setTheme(int i) {
    themeIndex = i;
    notifyListeners();
    save();
  }

  void setFontFamily(String f) {
    fontFamily = f;
    notifyListeners();
    save();
  }
}
