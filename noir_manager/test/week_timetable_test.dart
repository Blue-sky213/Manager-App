import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/study_models.dart';
import 'package:noir_manager/study/week_timetable.dart';

/// คาบเรียนประจำ 1 รายการ (ซ้ำทุกสัปดาห์)
NewActivity classOf(int subjectId,
        {required Set<int> days,
        required int start,
        int minutes = 120,
        DateTime? from,
        DateTime? to,
        ClassType? type}) =>
    NewActivity(
      name: 'เรียน',
      categoryId: 1,
      importance: 3,
      timed: true,
      day: from ?? DateTime(2026, 11, 2),
      startMinute: start,
      durationMin: minutes,
      repeat: RepeatKind.weekly,
      weekdays: days,
      endDate: to ?? DateTime(2027, 2, 26),
      subjectId: subjectId,
      kind: ActivityKind.classSession,
      classInfo: ClassInfo(type: type),
    );

void main() {
  final today = DateTime(2026, 11, 10);

  Future<(Subject, Subject, MemoryCalendarRepository)> setup() async {
    final study = MemoryStudyRepository();
    final a = await study.addSubject('คณิต 1');
    final b = await study.addSubject('DataCOM');
    final subjects = await study.subjects();
    Subject by(int id) => subjects.firstWhere((s) => s.id == id);
    return (by(a), by(b), MemoryCalendarRepository());
  }

  test('รวมคาบ: แยกวันเป็นช่อง · คาบที่แยกช่วงกลางภาครวมเป็นช่องเดียว · ซ่อนเทอมที่จบแล้ว', () async {
    final (m1, _, cal) = await setup();
    // จ+พ 09:00 · ก่อนกลางภาค / หลังกลางภาค = 2 รายการ เวลาเดียวกัน
    await cal.addActivity(classOf(m1.id, days: {1, 3}, start: 540, to: DateTime(2026, 12, 18)));
    await cal.addActivity(classOf(m1.id, days: {1, 3}, start: 540, from: DateTime(2027, 1, 4)));
    // เทอมก่อน จบไปแล้ว
    await cal.addActivity(classOf(m1.id, days: {5}, start: 780, from: DateTime(2026, 6, 1), to: DateTime(2026, 10, 1)));

    final acts = {m1: await cal.activitiesForSubject(m1.id)};
    final now = buildWeekSlots(acts, today: today);
    expect(now.map((s) => s.weekday), [1, 3]);
    expect(now.first.activities, hasLength(2));
    expect(buildWeekSlots(acts, today: today, onlyCurrent: false), hasLength(3));
  });

  test('ดูทีละสัปดาห์: คาบก่อน/หลังกลางภาคไม่ซ้อนกัน · ชั่วโมงหน่วยกิตไม่เกินจริง', () async {
    final (m1, _, cal) = await setup();
        // ก่อนกลางภาค: พ 09–13 · หลังกลางภาค: ศ 16–20 (ทฤษฎีทั้งคู่ 4 ชม.)
    await cal.addActivity(classOf(m1.id,
        days: {3}, start: 540, minutes: 240, to: DateTime(2026, 12, 18), type: ClassType.theory));
    await cal.addActivity(classOf(m1.id,
        days: {5}, start: 960, minutes: 240, from: DateTime(2027, 1, 4), type: ClassType.theory));
    final acts = {m1: await cal.activitiesForSubject(m1.id)};

    // ซ้อนทุกช่วง = 8 ชม. (ที่เคยขึ้น "เกิน") · ทีละสัปดาห์ = 4 ชม.
    expect(weekMinutes(m1, buildWeekSlots(acts, today: today)).theory, 480);
    final nov = buildWeekSlots(acts, week: mondayOf(today));
    expect(nov.map((s) => s.weekday), [3]);
    expect(weekMinutes(m1, nov).theory, 240);
    final jan = buildWeekSlots(acts, week: mondayOf(DateTime(2027, 1, 6)));
    expect(jan.map((s) => s.weekday), [5]);
    // ปิดเทอมระหว่างกลาง (ไม่มีคาบ)
    expect(buildWeekSlots(acts, week: mondayOf(DateTime(2026, 12, 23))), isEmpty);
    expect(mondayOf(DateTime(2026, 11, 15)), DateTime(2026, 11, 9)); // อาทิตย์ → จันทร์ก่อนหน้า
  });

  test('ชน: วันเดียวกันเวลาซ้อน + ช่วงวันที่ทับ = ชน · ต่อกันพอดี / คนละช่วงเทอม = ไม่ชน', () async {
    final (m1, dc, cal) = await setup();
    await cal.addActivity(classOf(m1.id, days: {2}, start: 540)); // อ 09–11
    await cal.addActivity(classOf(dc.id, days: {2}, start: 600)); // อ 10–12 → ชน
    await cal.addActivity(classOf(dc.id, days: {4}, start: 660)); // พฤ 11–13
    await cal.addActivity(classOf(m1.id, days: {4}, start: 540)); // พฤ 09–11 → ต่อกันพอดี ไม่ชน
    // ศ เวลาเดียวกัน แต่คนละช่วงวันที่ → ไม่ชน
    await cal.addActivity(classOf(m1.id, days: {5}, start: 540, to: DateTime(2026, 12, 18)));
    await cal.addActivity(classOf(dc.id, days: {5}, start: 540, from: DateTime(2027, 1, 4)));

    final slots = buildWeekSlots({
      m1: await cal.activitiesForSubject(m1.id),
      dc: await cal.activitiesForSubject(dc.id),
    }, today: today);
    final clash = findWeekClashes(slots);
    expect(clash.map((s) => s.weekday).toSet(), {2});
    expect(clash, hasLength(2));
  });

  testWidgets('หน้าตารางเรียนทั้งสัปดาห์: เห็นคาบ · ขอบแดงเตือนชน · ตรวจหน่วยกิต · แตะคาบ → เปิดวิชา',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final study = MemoryStudyRepository.seeded();
    final subject = (await study.subjects()).first;
    await study.setSubjectPlan(subject.id, code: '060233115', credits: '3(2-2-5)', year: 1, term: 1);
    final cal = MemoryCalendarRepository();
    final now = DateTime.now();
    await cal.addActivity(classOf(subject.id,
        days: {1}, start: 540, from: now.subtract(const Duration(days: 7)), to: now.add(const Duration(days: 60)),
        type: ClassType.theory));
    await cal.addActivity(classOf(subject.id,
        days: {1}, start: 600, from: now.subtract(const Duration(days: 7)), to: now.add(const Duration(days: 60)),
        type: ClassType.lab));

    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตารางเรียนทั้งสัปดาห์'));
    await tester.pumpAndSettle();

    expect(find.text('2 คาบ · 1 วิชา'), findsOneWidget);
    expect(find.textContaining('ชนกัน 2 คาบ'), findsOneWidget);
    expect(find.textContaining('ตรวจตามหลักหน่วยกิต (ชม./สัปดาห์)'), findsOneWidget);
    expect(find.text('2/2 ✓'), findsNWidgets(2)); // ทฤษฎี 2 ชม. · ปฏิบัติ 2 ชม.
    expect(tester.takeException(), isNull);

    // คลิกขวา (กดค้าง) = เมนูตรงตำแหน่ง
    await tester.longPress(find.text('060233115').first);
    await tester.pumpAndSettle();
    expect(find.text('ลบคาบนี้'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5)); // ปิดเมนู
    await tester.pumpAndSettle();

    // คลิกซ้าย = เปิดวิชาทันที → ปุ่ม "กลับตารางเรียน" พากลับมา
    await tester.tap(find.text('060233115').first);
    await tester.pumpAndSettle();
    expect(find.text('2 คาบ · 1 วิชา'), findsNothing);
    await tester.tap(find.text('กลับตารางเรียน'));
    await tester.pumpAndSettle();
    expect(find.text('2 คาบ · 1 วิชา'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
