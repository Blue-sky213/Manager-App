import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/demo_term.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/study/timetable_sim.dart';

void main() {
  test('แบ่งชั่วโมง: คาบละ ≤ 2 ชม. · ชั่วโมงต่อสัปดาห์ตามหน่วยกิต ไม่เกิน 4', () async {
    expect(splitHours(3), [2, 1]);
    expect(splitHours(4), [2, 2]);
    expect(splitHours(0), isEmpty);

    final study = MemoryStudyRepository();
    final id = await study.addSubject('โครงงาน');
    await study.setSubjectPlan(id, credits: '3(0-6-3)');
    final s = (await study.subjects()).firstWhere((s) => s.id == id);
    expect(simHours(s), (theory: 0, lab: 4, unknown: 0)); // 6 → ตัดเหลือ 4

    await study.setSubjectPlan(id, credits: '3(2-2-5)');
    expect(simHours((await study.subjects()).firstWhere((s) => s.id == id)), (theory: 2, lab: 2, unknown: 0));
    await study.setSubjectPlan(id, credits: null);
  });

  test('จำลองแผน 4 ปีทุกภาค: ผ่านกฎทุกข้อ · ไม่ชนคาบเดิม · seed เดิมได้ตารางเดิม', () async {
    final study = MemoryStudyRepository();
    await loadDemoCurriculum(study, MemoryCalendarRepository());
    final all = await study.subjects();
    for (final y in [1, 2, 3, 4]) {
      for (final t in [1, 2]) {
        final subjects = [for (final s in all) if (s.planYear == y && s.planTerm == t) s];
        if (subjects.isEmpty) continue;
        const busy = [(weekday: 1, start: 9 * 60, end: 12 * 60)]; // คาบเดิมที่มีอยู่
        final plan = planSimTimetable(subjects, busy: busy);
        expect(checkSimRules(plan.sessions), isEmpty, reason: 'ปี $y ภาค $t');
        expect(plan.skipped, isEmpty, reason: 'ปี $y ภาค $t');
        expect(plan.sessions.where((s) => s.weekday == 1 && s.startHour < 12 && s.endHour > 9), isEmpty);
        // วิชาที่มีทั้งทฤษฎีและปฏิบัติ → แยกคาบ
        for (final s in subjects.where((s) => s.credits == '3(2-2-5)')) {
          final types = plan.sessions.where((x) => x.subject.id == s.id).map((x) => x.type).toSet();
          expect(types, {ClassType.theory, ClassType.lab});
        }
        final again = planSimTimetable(subjects, busy: busy);
        expect([for (final s in again.sessions) '${s.weekday}${s.startHour}'],
            [for (final s in plan.sessions) '${s.weekday}${s.startHour}']);
      }
    }
  });

  test('ตรวจกฎจับผิดได้: คาบยาว · เกินสัปดาห์ · ชน', () async {
    final study = MemoryStudyRepository();
    final a = await study.addSubject('A');
    final s = (await study.subjects()).firstWhere((x) => x.id == a);
    final bad = [
      SimSession(s, 1, 9, 3, ClassType.theory),
      SimSession(s, 1, 10, 2, ClassType.lab),
    ];
    final errors = checkSimRules(bad);
    expect(errors.any((e) => e.contains('คาบยาว')), isTrue);
    expect(errors.any((e) => e.contains('ชม./สัปดาห์')), isTrue);
    expect(errors.any((e) => e.startsWith('ชน')), isTrue);
  });

  test('ตารางตัวอย่าง (ปี 1 ภาค 1) ถูกกฎ: คาบ ≤ 2 ชม. · วิชา ≤ 4 ชม./สัปดาห์ · ไม่ชน · ระบุประเภท', () async {
    final study = MemoryStudyRepository();
    final cal = MemoryCalendarRepository();
    await loadDemoCurriculum(study, cal);
    final sessions = <SimSession>[];
    for (final s in await study.subjects()) {
      for (final a in await cal.activitiesForSubject(s.id)) {
        if (a.kind != ActivityKind.classSession || a.endDate!.isAfter(DateTime(2026, 12, 31))) continue; // ครึ่งแรก
        expect(a.classInfo.type, isNotNull, reason: s.name);
        expect(a.startMinute! % 60, 0);
        for (final wd in a.weekdays) {
          sessions.add(SimSession(s, wd, a.startMinute! ~/ 60, a.durationMin! ~/ 60, a.classInfo.type));
        }
      }
    }
    expect(sessions, isNotEmpty);
    expect(checkSimRules(sessions), isEmpty);
  });

  testWidgets('หน้าตารางเรียน: จำลอง → มีคาบ ไม่ชน · ลบตารางจำลอง → กลับเหมือนเดิม', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final study = MemoryStudyRepository();
    final cal = MemoryCalendarRepository();
    await loadDemoCurriculum(study, cal);
    // คาบที่นัวร์ใส่เอง 1 คาบ ให้วิชาปี 2 ภาค 1 (เสาร์ ไม่ชนตัวอย่าง)
    final mine = (await study.subjects()).firstWhere((s) => s.code == '040203111');
    final now = DateTime.now();
    await cal.addActivity(NewActivity(
      name: 'เรียน · ${mine.name}',
      categoryId: 1,
      importance: 3,
      timed: true,
      day: now.subtract(const Duration(days: 7)),
      startMinute: 540,
      durationMin: 120,
      repeat: RepeatKind.weekly,
      weekdays: {6},
      endDate: now.add(const Duration(days: 60)),
      subjectId: mine.id,
      kind: ActivityKind.classSession,
    ));

    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตารางเรียนทั้งสัปดาห์'));
    await tester.pumpAndSettle();
    // ตัวนับบนหน้า "N คาบ · M วิชา" (ไม่ใช่ข้อความ SnackBar "จำลอง N คาบ …")
    final counter = find.byWidgetPredicate(
        (w) => w is Text && RegExp(r'^\d+ คาบ · \d+ วิชา$').hasMatch(w.data ?? ''));
    String count() => tester.widget<Text>(counter).data!;
    final before = count();

    await tester.tap(find.byTooltip('ตัวเลือก').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('จำลองตารางเรียน (ทดสอบ)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปี 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('จำลอง'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ข้าม 1 วิชาที่มีคาบแล้ว'), findsOneWidget);
    expect(count(), isNot(before));
    expect(find.textContaining('ชนกัน'), findsNothing);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byTooltip('ตัวเลือก').last);
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('ลบตารางจำลอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(count(), before);
  });
}
