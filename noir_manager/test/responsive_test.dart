import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/theme/noir_colors.dart';

/// ยืด / ย่อหน้าต่างทุกแบบที่ Windows ยอม (ขั้นต่ำ 420×640 ตาม win32_window.cpp)
/// ทุกหน้าต้องไม่ล้นจอ ไม่พัง
const sizes = {
  'ขั้นต่ำ 420×640': Size(420, 640),
  'มือถือแนวนอน 900×420': Size(900, 420),
  'กว้างเตี้ย 1600×640': Size(1600, 640),
  'สูงแคบ 700×1400': Size(700, 1400),
  'Full HD 1920×1080': Size(1920, 1080),
  'จอยาวมาก 3440×1440': Size(3440, 1440),
};

const pages = ['วันนี้', 'ปฏิทิน', 'การเรียน', 'ไฟล์', 'สถิติ'];

void main() {
  for (final MapEntry(key: name, value: size) in sizes.entries) {
    testWidgets('ทุกหน้าไม่ล้นจอที่ $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(NoirManagerApp(
        studyRepository: MemoryStudyRepository.seeded(),
        calendarRepository: MemoryCalendarRepository(),
      ));
      await tester.pumpAndSettle();
      for (final p in pages) {
        await tester.tap(find.text(p).last);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'หน้า $p ที่ $name');
      }
      // หน้าตั้งค่า (ปุ่มในเมนูซ้าย หรือไอคอนบนแถบหัวตอนจอแคบ)
      final settings = find.text('ตั้งค่า');
      await tester.tap(settings.evaluate().isNotEmpty ? settings.first : find.byTooltip('ตั้งค่า'));
      await tester.pumpAndSettle();
      expect(find.text('หน้าตา'), findsOneWidget); // หัวข้อแรก (ข้อถัดไปอาจอยู่ใต้จอเตี้ย)
      expect(tester.takeException(), isNull, reason: 'หน้าตั้งค่าที่ $name');
    });
  }

  testWidgets('ตั้งค่า: เลือกธีมพาสเทล → จำไว้ · เปิดแอปใหม่ยังเป็นธีมเดิม', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final study = MemoryStudyRepository.seeded();
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งค่า').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ชมพู').first); // แถวสีพาสเทล · สว่าง
    await tester.pumpAndSettle();
    expect(await study.getSetting('theme'), 'pink');
    final bg = Theme.of(tester.element(find.text('โหมดแอป'))).scaffoldBackgroundColor;
    expect(bg, const Color(0xFFFDF4F7));

    // 3 กลุ่ม: โหมด (มืด · สว่าง · ตามเวลา) · พาสเทลสว่าง · พาสเทลมืด
    expect(find.text('ตามเวลา'), findsOneWidget);
    expect(find.text('ชมพู'), findsNWidgets(2));
    await tester.tap(find.text('ทั้งคู่'));
    await tester.pumpAndSettle();
    expect(await study.getSetting('app_mode'), 'both');
    expect(find.byKey(const Key('menu-work')), findsOneWidget); // รอบ 8D: สวิตช์เมนู "งาน"

    // เปิดแอปใหม่ (repo เดิม) → ธีมชมพูยังอยู่
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal));
    await tester.pumpAndSettle();
    expect(Theme.of(tester.element(find.text('วันนี้').first)).scaffoldBackgroundColor, const Color(0xFFFDF4F7));
  });

  testWidgets('ปุ่มลัดสลับธีมในเมนู: ชมพู ↔ ชมพู (มืด)', (tester) async {
    tester.view.physicalSize = const Size(1280, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final study = MemoryStudyRepository.seeded();
    await study.setSetting('theme', 'pink');
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: MemoryCalendarRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('โหมดมืด'));
    await tester.pumpAndSettle();
    expect(await study.getSetting('theme'), 'pink-dark');
    expect(Theme.of(tester.element(find.text('วันนี้').first)).scaffoldBackgroundColor, const Color(0xFF1A1216));
    await tester.tap(find.text('โหมดสว่าง'));
    await tester.pumpAndSettle();
    expect(await study.getSetting('theme'), 'pink');
  });

  test('ธีมตามเวลา: 06:00–17:59 สว่าง · นอกนั้นมืด · รวมสี + ความสว่าง', () {
    expect(resolveTheme('auto', now: DateTime(2026, 11, 11, 6)), 'light');
    expect(resolveTheme('auto', now: DateTime(2026, 11, 11, 17, 59)), 'light');
    expect(resolveTheme('auto', now: DateTime(2026, 11, 11, 18)), 'dark');
    expect(resolveTheme('pink'), 'pink');
    expect(themeIdFor('pink', 'dark'), 'pink-dark');
    expect(themeIdFor('', 'light'), 'light');
    expect(themeIdFor('', 'auto'), 'auto');
  });
}
