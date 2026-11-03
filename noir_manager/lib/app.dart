import 'package:flutter/material.dart';

import 'data/study_repository.dart';
import 'data/study_scope.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';

/// ตัวแอปทั้งหมด: ถือ "ธีมปัจจุบัน" (มืด/สว่าง) และส่ง repository ลงไปให้ทุกหน้า
class NoirManagerApp extends StatefulWidget {
  const NoirManagerApp({super.key, required this.studyRepository});

  /// ที่เก็บข้อมูลวิชา: แอปจริง = SQLite · ตอนเทส = เก็บใน RAM
  final StudyRepository studyRepository;

  @override
  State<NoirManagerApp> createState() => _NoirManagerAppState();
}

class _NoirManagerAppState extends State<NoirManagerApp> {
  // ค่าเริ่มต้น = โหมดมืด (ตาม Mockup)
  ThemeMode _themeMode = ThemeMode.dark;

  void _toggleTheme() {
    setState(() {
      _themeMode =
          _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    });
  }

  @override
  Widget build(BuildContext context) {
    return StudyScope(
      repository: widget.studyRepository,
      child: MaterialApp(
        title: 'Noir Manager',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: _themeMode,
        home: AppShell(
          isDark: _themeMode == ThemeMode.dark,
          onToggleTheme: _toggleTheme,
        ),
      ),
    );
  }
}
