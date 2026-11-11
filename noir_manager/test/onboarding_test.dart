import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

void main() {
  testWidgets('คำถามแรกเข้า: เลือกโหมด · เวลานอน · อยากเปลี่ยนอะไร · เป้า GPA → จำไว้ · เปิดใหม่ไม่ถามซ้ำ', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final study = MemoryStudyRepository.seeded();
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal, askOnboarding: true));
    await tester.pumpAndSettle();

    expect(find.text('ยินดีต้อนรับ · ใช้แอปนี้ทำอะไรเป็นหลัก?'), findsOneWidget);
    await tester.tap(find.text('ทั้งคู่'));
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    // บรรยากาศ → ลองธีมสดทันที
    expect(find.text('เวลาตั้งใจทำอะไรสักอย่าง คุณชอบบรรยากาศแบบไหน?'), findsOneWidget);
    await tester.tap(find.text('ห้องสว่าง โปร่ง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ชมพู · อบอุ่น อ่อนโยนกับตัวเอง'));
    await tester.pumpAndSettle();
    expect(await study.getSetting('theme'), 'pink');
    await tester.ensureVisible(find.text('ถัดไป')); // คำตอบยาว → ปุ่มอยู่ใต้จอ
    await tester.pumpAndSettle();
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('ปกติตื่นกี่โมง นอนกี่โมง?'), findsOneWidget);
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'อยากเป็นคนขยันขึ้น');
    await tester.tap(find.text('ถัดไป'));
    await tester.pumpAndSettle();
    expect(find.text('GPA 3.00'), findsOneWidget);
    await tester.tap(find.text('เริ่มใช้งาน'));
    await tester.pumpAndSettle();

    expect(find.text('Noir Manager'), findsWidgets); // เข้าแอปแล้ว
    expect(await study.getSetting('app_mode'), 'both');
    expect(await study.getSetting('self_goal'), 'อยากเป็นคนขยันขึ้น');
    expect(await study.getSetting('gpa_target'), '3.00');
    expect(await study.getSetting('onboarded'), '1');
    final base = await cal.lifeBase();
    expect(base, hasLength(7));
    expect(base.first.wakeMinute, 7 * 60);

    // เปิดแอปใหม่ → ไม่ถามซ้ำ
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal, askOnboarding: true));
    await tester.pumpAndSettle();
    expect(find.text('ยินดีต้อนรับ · ใช้แอปนี้ทำอะไรเป็นหลัก?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('คำถามแรกเข้า: ข้ามทั้งหมดได้ · จอขั้นต่ำ 420×640 ไม่ล้น', (tester) async {
    tester.view.physicalSize = const Size(420, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final study = MemoryStudyRepository.seeded();
    await tester.pumpWidget(
        NoirManagerApp(studyRepository: study, calendarRepository: MemoryCalendarRepository(), askOnboarding: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('ข้ามทั้งหมด'));
    await tester.pumpAndSettle();
    expect(await study.getSetting('onboarded'), '1');
    expect(await study.getSetting('self_goal'), isNull);
  });
}
