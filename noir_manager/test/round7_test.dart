import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/notebook_view.dart' show isoWeek;
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/study/tutor_plan.dart';

Occurrence _occ(int id, DateTime day, ActivityKind kind) => Occurrence(
      id: id,
      activityId: id,
      title: 'x',
      categoryId: 1,
      importance: 3,
      repeats: true,
      day: day,
      startAt: DateTime(day.year, day.month, day.day, 19),
      endAt: DateTime(day.year, day.month, day.day, 20),
      status: OccurrenceStatus.planned,
      reason: null,
      movedFromId: null,
      subjectId: 1,
      kind: kind,
    );

void main() {
  test('เลข W ตาม ISO (สัปดาห์เริ่มจันทร์)', () {
    expect(isoWeek(DateTime(2026, 11, 9)), 46);
    expect(isoWeek(DateTime(2026, 11, 15)), 46); // อาทิตย์ยังเป็นสัปดาห์เดียวกัน
    expect(isoWeek(DateTime(2026, 11, 16)), 47);
    expect(isoWeek(DateTime(2027, 1, 1)), 53); // ศุกร์ 1 ม.ค. 2027 ยังเป็นสัปดาห์สุดท้ายของ 2026
  });

  group('กฎติวใหม่ (J)', () {
    final mon = DateTime(2026, 11, 9);
    test('คาบแรกวันอาทิตย์ = สัปดาห์แรก 0 รอบ (เดิม 4)', () {
      final sun = DateTime(2026, 11, 15);
      final q = weekQuota(5, [_occ(1, sun, ActivityKind.classSession)],
          today: DateTime(2026, 11, 13), monday: mon, firstClass: sun);
      expect(q.firstWeek, isTrue);
      expect(q.weekTarget, 0);
      expect(q.tutorNeeded, 0);
      expect(q.remaining, 0);
    });

    test('คาบแรกวันจันทร์ = เป้าสัปดาห์แรก 5×6÷7 = 4', () {
      final q = weekQuota(5, [_occ(1, mon, ActivityKind.classSession)], monday: mon, firstClass: mon);
      expect(q.weekTarget, 4);
      expect(q.tutorNeeded, 4);
    });

    test('วันเหลือไม่พอ: วันนี้เสาร์ · อาทิตย์มีคาบ (พัก) → เหลือติวได้ 1 วัน', () {
      final m2 = DateTime(2026, 11, 16);
      final q = weekQuota(5, [_occ(1, DateTime(2026, 11, 22), ActivityKind.classSession)],
          today: DateTime(2026, 11, 21), monday: m2, firstClass: DateTime(2026, 11, 15));
      expect(q.firstWeek, isFalse);
      expect(q.tutorNeeded, 4);
      expect(q.daysLeft, 1);
      expect(q.remaining, 1);
      expect(q.cappedByDays, isTrue);
    });

    test('ไม่ส่งวัน = กฎเดิม', () {
      expect(weekQuota(3, const []).tutorNeeded, 3);
      expect(weekQuota(3, const []).remaining, 3);
    });
  });

  test('เลือกวันเอง: ตัดวันที่ข้ามออก', () {
    final d = NewActivity(
      name: 'วาดภาพ',
      categoryId: 1,
      importance: 2,
      timed: true,
      day: DateTime(2026, 11, 16),
      startMinute: 19 * 60,
      durationMin: 90,
      repeat: RepeatKind.dates,
      dates: [ScheduledDate(DateTime(2026, 11, 16)), ScheduledDate(DateTime(2026, 11, 20))],
    );
    final t = d.withDates([d.dates.first]);
    expect(t.dates.length, 1);
    expect(t.name, 'วาดภาพ');
    expect(t.firstDay, DateTime(2026, 11, 16));
  });

  testWidgets('เดือน: แตะ W = เปิดสัปดาห์ · ดับเบิลคลิกวัน = เปิดมุมมองวัน', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(NoirManagerApp(
      studyRepository: MemoryStudyRepository.seeded(),
      calendarRepository: MemoryCalendarRepository(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('สัปดาห์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เดือน').last);
    await tester.pumpAndSettle();

    final now = DateTime.now();
    final monday = DateTime(now.year, now.month, now.day - (now.weekday - 1));
    final w = find.byKey(ValueKey('nb-week-${monday.month}-${monday.day}'));
    expect(w, findsOneWidget);
    expect(find.text('W${isoWeek(monday)}'), findsWidgets);
    await tester.tap(w);
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('nb-week-${monday.month}-${monday.day}')), findsNothing); // ออกจากเดือนแล้ว

    // กลับเดือน → ดับเบิลคลิกวันนี้ → มุมมองวัน
    await tester.tap(find.text('สัปดาห์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เดือน').last);
    await tester.pumpAndSettle();
    final cell = find.byKey(ValueKey('nb-${now.month}-${now.day}'));
    await tester.tap(cell);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(cell);
    await tester.pumpAndSettle();
    expect(find.text('วัน'), findsWidgets);
    expect(find.byKey(ValueKey('nb-${now.month}-${now.day}')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
