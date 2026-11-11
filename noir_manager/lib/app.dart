import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'calendar/calendar_repository.dart';
import 'data/study_repository.dart';
import 'data/study_scope.dart';
import 'shell/app_shell.dart';
import 'calendar/lock_flow.dart';
import 'pages/onboarding_page.dart';
import 'theme/app_theme.dart';
import 'theme/noir_colors.dart';
import 'shell/app_nav.dart';
import 'study/subject_colors.dart';
import 'widgets/dialogs.dart';

/// ตัวแอปทั้งหมด: ถือ "ธีมปัจจุบัน" (มืด/สว่าง) และส่ง repository ลงไปให้ทุกหน้า
class NoirManagerApp extends StatefulWidget {
  const NoirManagerApp({
    super.key,
    required this.studyRepository,
    this.askOnboarding = false,
    required this.calendarRepository,
  });

  /// ที่เก็บข้อมูลวิชา: แอปจริง = SQLite · ตอนเทส = เก็บใน RAM
  final StudyRepository studyRepository;

  /// เปิดครั้งแรก → ถามคำถามแรกเข้า (main.dart เปิด · เทสส่วนใหญ่ปิด)
  final bool askOnboarding;

  /// ที่เก็บข้อมูลปฏิทิน (แบบเดียวกัน)
  final CalendarRepository calendarRepository;

  @override
  State<NoirManagerApp> createState() => _NoirManagerAppState();
}

class _NoirManagerAppState extends State<NoirManagerApp> {
  final _nav = GlobalKey<NavigatorState>();

  /// ย้อนกลับ: ปิดหน้า/เมนูที่เปิดซ้อนก่อน · ไม่มีแล้ว → หน้าที่โชว์อยู่ / shell ย้อนเอง
  Future<void> _back() async {
    final popped = await _nav.currentState?.maybePop() ?? false;
    if (!popped) appBack.handle();
  }

  // ค่าเริ่มต้น = โหมดมืด · ธีมที่เลือกจำในตาราง setting (key = theme)
  String _themeId = 'dark';
  bool _onboarding = false;
  static const _themeKey = 'theme';

  @override
  void initState() {
    super.initState();
    // สีประจำวิชาให้ปฏิทิน / วันนี้ ตั้งแต่เปิดแอป (หน้าวิชาโหลดซ้ำเมื่อเปลี่ยน)
    refreshSubjectColors(widget.studyRepository);
    refreshLockInfo(widget.calendarRepository); // 🔒 ที่หน้าปฏิทิน
    widget.studyRepository.getSetting(_themeKey).then((id) {
      if (mounted && id != null) setState(() => _themeId = themeChoiceOf(id).id);
    });
    if (widget.askOnboarding) {
      widget.studyRepository.getSetting(onboardedKey).then((v) {
        if (mounted && v == null) setState(() => _onboarding = true);
      });
    }
  }

  void _setTheme(String id) {
    setState(() => _themeId = id);
    widget.studyRepository.setSetting(_themeKey, id);
  }

  /// ปุ่มลัดในเมนู: มืด ↔ สว่าง (ธีมพาสเทล → มืด)
  void _toggleTheme() => _setTheme(_themeId == 'dark' ? 'light' : 'dark');

  @override
  Widget build(BuildContext context) {
    return StudyScope(
      repository: widget.studyRepository,
      child: CalendarScope(
        repository: widget.calendarRepository,
        child: MaterialApp(
          title: 'Noir Manager',
          navigatorKey: _nav,
          // ปุ่มเมาส์ 4 = ย้อนกลับ · ปุ่ม 5 = ไปหน้าที่เพิ่งย้อนมา: ปิดหน้าที่เปิดซ้อน / เมนู / กล่อง (หน้าแรกสุดไม่มีที่ให้ย้อน → ไม่ทำอะไร)
          builder: (context, child) =>
              MouseBack(
                onBack: _back,
                onForward: () => appForward.handle(),
                onPointer: (p) => lastPointerDown = p,
                child: child!,
              ),
          debugShowCheckedModeBanner: false,
          // ภาษาไทย: ปฏิทินเลือกวัน, นาฬิกาเลือกเวลา, ปุ่ม OK/Cancel ของระบบ
          locale: const Locale('th', 'TH'),
          supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // ธีมเดียวที่เลือก (มี brightness ของตัวเอง) → ไม่ใช้ darkTheme / themeMode ของระบบ
          theme: AppTheme.of(themeChoiceOf(_themeId)),
          home: _onboarding
              ? OnboardingPage(onDone: () => setState(() => _onboarding = false))
              : AppShell(
            isDark: themeChoiceOf(_themeId).dark,
            onToggleTheme: _toggleTheme,
            themeId: _themeId,
            onTheme: _setTheme,
          ),
        ),
      ),
    );
  }
}
