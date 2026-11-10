import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'calendar/calendar_repository.dart';
import 'data/study_repository.dart';
import 'data/study_scope.dart';
import 'shell/app_shell.dart';
import 'theme/app_theme.dart';
import 'widgets/dialogs.dart';

/// ตัวแอปทั้งหมด: ถือ "ธีมปัจจุบัน" (มืด/สว่าง) และส่ง repository ลงไปให้ทุกหน้า
class NoirManagerApp extends StatefulWidget {
  const NoirManagerApp({
    super.key,
    required this.studyRepository,
    required this.calendarRepository,
  });

  /// ที่เก็บข้อมูลวิชา: แอปจริง = SQLite · ตอนเทส = เก็บใน RAM
  final StudyRepository studyRepository;

  /// ที่เก็บข้อมูลปฏิทิน (แบบเดียวกัน)
  final CalendarRepository calendarRepository;

  @override
  State<NoirManagerApp> createState() => _NoirManagerAppState();
}

class _NoirManagerAppState extends State<NoirManagerApp> {
  final _nav = GlobalKey<NavigatorState>();

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
      child: CalendarScope(
        repository: widget.calendarRepository,
        child: MaterialApp(
          title: 'Noir Manager',
          navigatorKey: _nav,
          // ปุ่มเมาส์ 4 = ย้อนกลับ: ปิดหน้าที่เปิดซ้อน / เมนู / กล่อง (หน้าแรกสุดไม่มีที่ให้ย้อน → ไม่ทำอะไร)
          builder: (context, child) =>
              MouseBack(onBack: () => _nav.currentState?.maybePop(), child: child!),
          debugShowCheckedModeBanner: false,
          // ภาษาไทย: ปฏิทินเลือกวัน, นาฬิกาเลือกเวลา, ปุ่ม OK/Cancel ของระบบ
          locale: const Locale('th', 'TH'),
          supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: _themeMode,
          home: AppShell(
            isDark: _themeMode == ThemeMode.dark,
            onToggleTheme: _toggleTheme,
          ),
        ),
      ),
    );
  }
}
