import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/free_slots.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/slot_picker.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

void main() {
  test('จองเวลา: แตะแล้วขยับให้พอดีช่อง · ช่องสั้นเกิน / งานล็อก = เลือกไม่ได้ · งานแทนได้ = ทับได้', () {
    final day = SlotDay(DateTime(2026, 11, 15), [
      const Busy(10 * 60, 12 * 60, 'เรียน', classSession: true),
      const Busy(17 * 60, 18 * 60, 'วิ่ง 5K', importance: 1),
      const Busy(20 * 60, 21 * 60, 'คำมั่น', locked: true),
    ], 8 * 60, 24 * 60);
    expect(const Busy(0, 1, 'x', importance: 1).replaceable, isTrue);
    expect(const Busy(0, 1, 'x', classSession: true).replaceable, isFalse);
    expect(const Busy(0, 1, 'x', importance: 3).replaceable, isFalse);
    // 08:00–10:00 ว่าง 2 ชม. · แตะ 09:40 รอบ 90 นาที → ขยับขึ้นเป็น 08:30
    expect(fitStart(day.bookable, 9 * 60 + 40, 90), 8 * 60 + 30);
    expect(fitStart(day.bookable, 11 * 60, 60), isNull); // โดนคาบเรียน
    // 17:00 วิ่ง (แทนได้) → จองทับได้ · ช่วง 12:00–20:00
    expect(fitStart(day.bookable, 17 * 60 + 5, 60), 17 * 60);
    expect(fitStart(day.bookable, 20 * 60 + 30, 30), isNull); // ล็อก
    // ชั่วโมงว่างนับเฉพาะช่องว่างจริงที่ยาวพอ
    expect(day.freeHours(90), (120 + 300 + 120 + 180) / 60);
    expect([freeLevel(0), freeLevel(2), freeLevel(5), freeLevel(9)], [0, 1, 2, 3]);
  });

  testWidgets('ปฏิทิน → สมุด: ดูอย่างเดียว · คำอธิบาย · สรุปเดือน · แตะวัน = สรุปวัน', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    final now = DateTime.now();
    await cal.addActivity(NewActivity(
      name: 'ส่ง: การบ้านบท 2',
      categoryId: null,
      importance: 3,
      timed: true,
      day: DateTime(now.year, now.month, now.day),
      startMinute: 23 * 60,
      durationMin: 30,
    ));
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('สัปดาห์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('สมุด').last);
    await tester.pumpAndSettle();
    expect(find.text('ทำครบทั้งวัน'), findsOneWidget);
    expect(find.text('⭐ ส่งงาน 1'), findsOneWidget);
    await tester.tap(find.byKey(ValueKey('nb-${now.month}-${now.day}')));
    await tester.pumpAndSettle();
    expect(find.text('⭐ ส่ง: การบ้านบท 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('สถิติ: วงกลม · กราฟ · แยกกิจกรรม · Streak', (tester) async {
    tester.view.physicalSize = const Size(393, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: MemoryCalendarRepository()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สถิติ').last);
    await tester.pumpAndSettle();
    expect(find.text('ทำตามแผนรายวัน'), findsOneWidget);
    expect(find.text('แยกตามกิจกรรม'), findsOneWidget);
    expect(find.textContaining('Streak'), findsWidgets);
    await tester.tap(find.text('28 วัน'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
