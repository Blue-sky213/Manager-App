import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'calendar/calendar_repository.dart';
import 'data/study_repository.dart';
import 'data/study_scope.dart';
import 'shell/app_shell.dart';
import 'calendar/lock_flow.dart' show refreshLockState;
import 'data/backup.dart';
import 'pages/onboarding_page.dart';
import 'widgets/device_preview.dart';
import 'shell/window_mode.dart';
import 'data/demo_year.dart' show demoMode;
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
    this.backup,
    required this.calendarRepository,
  });

  /// ที่เก็บข้อมูลวิชา: แอปจริง = SQLite · ตอนเทส = เก็บใน RAM
  final StudyRepository studyRepository;

  /// เปิดครั้งแรก → ถามคำถามแรกเข้า (main.dart เปิด · เทสส่วนใหญ่ปิด)
  final bool askOnboarding;

  /// ระบบสำรองข้อมูล (มีเฉพาะแอปจริงที่ใช้ไฟล์ DB · เทสไม่มี)
  final BackupService? backup;

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
  Timer? _clock;
  static const _themeKey = 'theme';

  bool _onKey(KeyEvent e) {
    if (e is! KeyDownEvent || !supportsFullscreen) return false;
    if (e.logicalKey == LogicalKeyboardKey.f11) {
      final on = !fullscreen.value;
      setFullscreen(on);
      widget.studyRepository.setSetting(fullscreenKey, on ? 'on' : 'off');
      if (on) {
        final ctx = _nav.currentContext;
        if (ctx != null) {
          ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(const SnackBar(
            content: Text('เต็มจอ · กด Esc หรือ F11 เพื่อออก'),
            duration: Duration(seconds: 2),
          ));
        }
      }
      return true;
    }
    if (e.logicalKey == LogicalKeyboardKey.escape && fullscreen.value) {
      setFullscreen(false);
      widget.studyRepository.setSetting(fullscreenKey, 'off');
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    // สีประจำวิชาให้ปฏิทิน / วันนี้ ตั้งแต่เปิดแอป (หน้าวิชาโหลดซ้ำเมื่อเปลี่ยน)
    refreshSubjectColors(widget.studyRepository);
    refreshLockState(widget.calendarRepository);
    widget.studyRepository.getSetting(_themeKey).then((id) {
      if (mounted && id != null) setState(() => _themeId = id == autoThemeId ? id : themeChoiceOf(id).id);
    });
    // ธีม "ตามเวลา": เช็กทุกนาที พอข้าม 06:00 / 18:00 ก็เปลี่ยนเอง
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_themeId == autoThemeId && mounted) setState(() {});
    });
    // เต็มจอ: F11 สลับ · Esc ออก · จำไว้ตอนเปิดครั้งถัดไป
    HardwareKeyboard.instance.addHandler(_onKey);
    widget.studyRepository.getSetting(fullscreenKey).then((v) {
      if (v == 'on') setFullscreen(true);
    });
    widget.studyRepository.getSetting(devicePreviewKey).then((v) {
      if (v == null || v.isEmpty) return;
      final parts = v.split(':');
      devicePreview.value = (id: parts.first, landscape: parts.length > 1);
    });
    if (widget.askOnboarding) {
      widget.studyRepository.getSetting(onboardedKey).then((v) {
        if (mounted && v == null) setState(() => _onboarding = true);
      });
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _clock?.cancel();
    super.dispose();
  }

  void _setTheme(String id) {
    setState(() => _themeId = id);
    widget.studyRepository.setSetting(_themeKey, id);
  }

  /// ปุ่มลัดในเมนู: สลับสว่าง ↔ มืด ในโทนสีเดิม (ชมพู ↔ ชมพูมืด)
  void _toggleTheme() => _setTheme(pairedTheme(resolveTheme(_themeId)));

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
              DevicePreviewFrame(
                child: MouseBack(
                  onBack: _back,
                  onForward: () => appForward.handle(),
                  onPointer: (p) => lastPointerDown = p,
                  child: ValueListenableBuilder(
                    valueListenable: demoMode,
                    // โหมดข้อมูลตัวอย่าง: แถบเหลืองด้านบนตลอด กดปิดได้
                    builder: (context, demo, _) => !demo
                        ? child!
                        : Column(children: [
                            Material(
                              color: const Color(0xFF6B5205),
                              child: SafeArea(
                                bottom: false,
                                child: InkWell(
                                  onTap: () => demoMode.value = false,
                                  child: const Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                    child: Text('กำลังดูข้อมูลตัวอย่าง 1 ปี · ข้อมูลจริงไม่ถูกแตะ · แตะเพื่อปิด',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: Color(0xFFFFF3C4), fontSize: 13)),
                                  ),
                                ),
                              ),
                            ),
                            Expanded(child: child!),
                          ]),
                  ),
                ),
              ),
          debugShowCheckedModeBanner: false,
          // ภาษาไทย: ปฏิทินเลือกวัน, นาฬิกาเลือกเวลา, ปุ่ม OK/Cancel ของระบบ
          locale: const Locale('th', 'TH'),
          supportedLocales: const [Locale('th', 'TH'), Locale('en', 'US')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // ธีมเดียวที่เลือก (มี brightness ของตัวเอง) → ไม่ใช้ darkTheme / themeMode ของระบบ
          theme: AppTheme.of(themeChoiceOf(resolveTheme(_themeId))),
          home: _onboarding
              ? OnboardingPage(onDone: () => setState(() => _onboarding = false), onTheme: _setTheme)
              : AppShell(
            isDark: themeChoiceOf(resolveTheme(_themeId)).dark,
            onToggleTheme: _toggleTheme,
            themeId: _themeId,
            onTheme: _setTheme,
            backup: widget.backup,
          ),
        ),
      ),
    );
  }
}
