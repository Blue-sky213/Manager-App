import 'package:flutter/material.dart';

import 'noir_colors.dart';

/// สร้าง ThemeData 2 แบบ (มืด / สว่าง) จากชุดสี NoirColors
class AppTheme {
  AppTheme._(); // กันไม่ให้ใครสร้าง object ของคลาสนี้ ใช้แค่ static

  static ThemeData dark() => _build(NoirColors.dark, Brightness.dark);
  static ThemeData light() => _build(NoirColors.light, Brightness.light);

  static ThemeData _build(NoirColors c, Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: c.accent,
      brightness: brightness,
    ).copyWith(
      primary: c.accent,
      onPrimary: c.onAccent,
      surface: c.surface,
      onSurface: c.text,
      outline: c.line2,
    );

    return ThemeData(
      useMaterial3: true,
      fontFamily: 'IBMPlexSansThai', // ชื่อตรงกับ family ใน pubspec.yaml
      colorScheme: scheme,
      scaffoldBackgroundColor: c.bg,
      dividerColor: c.line,
      extensions: [c],
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.side,
        indicatorColor: c.navBg,
      ),
    );
  }
}
