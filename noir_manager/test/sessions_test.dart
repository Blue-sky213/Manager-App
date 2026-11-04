import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/demo_term.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/data/study_models.dart';
import 'package:noir_manager/data/study_repository.dart';
import 'package:noir_manager/study/tutor_plan.dart';

void main() {
  test('ช่วงรอบติว: น้อย 1–2 · กลาง 2–3 · สูง 3–7', () {
    expect(sessionRange(1), (1, 2));
    expect(sessionRange(2), (2, 3));
    expect(sessionRange(3), (3, 7));
    expect(sessionsForImportance(1), 2);
  });

  test('เลือกรอบเองได้ แต่ถูกบีบให้อยู่ในช่วง', () async {
    final repo = MemoryStudyRepository.seeded();
    final s = (await repo.subjects()).first; // DaVinci · สูง
    await repo.setSessionsPerWeek(s.id, 9);
    expect((await repo.subjects()).first.sessionsPerWeek, 7);

    await repo.setSubjectImportance(s.id, 1);
    expect((await repo.subjects()).first.sessionsPerWeek, 2);
    await repo.setSessionsPerWeek(s.id, 1);
    expect((await repo.subjects()).first.sessionsPerWeek, 1);
    await repo.setSessionsPerWeek(s.id, 5);
    expect((await repo.subjects()).first.sessionsPerWeek, 2);
  });

  test('ข้อมูลตัวอย่างเทอม: 6 วิชา · คาบเรียนเว้นสัปดาห์สอบ · ใส่ซ้ำไม่ได้', () async {
    final study = MemoryStudyRepository.seeded();
    final cal = MemoryCalendarRepository();
    expect(await loadDemoTerm(study, cal), isTrue);
    expect(await study.subjects(), hasLength(1 + demoSubjects.length));

    // จ. 9 พ.ย. = สัปดาห์ 1: วิศวกรรมฯ + ภาษาอังกฤษ
    expect(await cal.occurrencesOn(DateTime(2026, 11, 9)), hasLength(2));
    // จ. 21 ธ.ค. = สัปดาห์สอบกลางภาค: มีแต่สอบ ไม่มีคาบ
    final mid = await cal.occurrencesOn(DateTime(2026, 12, 21));
    expect(mid.single.title, startsWith('สอบกลางภาค'));
    // จ. 28 ธ.ค. = สัปดาห์ 8 เรียนต่อ
    expect(await cal.occurrencesOn(DateTime(2026, 12, 28)), hasLength(2));

    expect(await loadDemoTerm(study, cal), isFalse);
  });

  test('แผน 4 ปี: 46 วิชา · 125 หน่วยกิต · ใส่ซ้ำไม่เพิ่ม', () async {
    final study = MemoryStudyRepository.seeded();
    final cal = MemoryCalendarRepository();
    expect(await loadDemoCurriculum(study, cal), demoSubjects.length + curriculumPlan.length);
    final planned = (await study.subjects()).where((s) => s.planYear != null);
    expect(planned, hasLength(46));
    expect(planned.fold<int>(0, (n, s) => n + s.creditUnits), 125);
    expect(await loadDemoCurriculum(study, cal), 0);
  });

  group('รอบติว', () {
    Occurrence occ(int id, ActivityKind kind, OccurrenceStatus st) => Occurrence(
          id: id, activityId: id, title: 'x', categoryId: 1, importance: 3, repeats: true,
          day: DateTime(2026, 11, 2), startAt: DateTime(2026, 11, 2, 9),
          endAt: DateTime(2026, 11, 2, 11), status: st, reason: null, movedFromId: null,
          subjectId: 1, kind: kind);

    test('เป้า 3 · เรียน จ+พ = 2 → ต้องติว 1 · คาบที่ยกเลิกยังนับ (EZ)', () {
      final q = weekQuota(3, [
        occ(1, ActivityKind.classSession, OccurrenceStatus.done),
        occ(2, ActivityKind.classSession, OccurrenceStatus.cancelled),
      ]);
      expect(q.classes, 2);
      expect(q.tutorNeeded, 1);
      expect(q.remaining, 1);
      final q2 = weekQuota(3, [
        occ(1, ActivityKind.classSession, OccurrenceStatus.done),
        occ(2, ActivityKind.classSession, OccurrenceStatus.done),
        occ(3, ActivityKind.tutor, OccurrenceStatus.planned),
      ]);
      expect(q2.remaining, 0);
    });

    test('วางเนื้อหา: บทที่กำลังติวมาก่อน · ทวนหัวข้อละ 15 ไม่เกินครึ่งรอบ', () async {
      final repo = MemoryStudyRepository.seeded();
      final s = (await repo.subjects()).first;
      final chs = await repo.chapters(s.id);
      // บท 1 ติวจบแล้ว · บท 2 กำลังติว · ให้หัวข้อในบท 1 แดง 3 หัวข้อ
      await repo.setChapterStatus(chs[0].chapter.id, ChapterStatus.learned);
      await repo.setChapterStatus(chs[1].chapter.id, ChapterStatus.learning);
      for (final t in chs[0].subtopics.take(3)) {
        await repo.addAssessment(t.id, 40, at: DateTime(2026, 11, 1));
      }
      final plan = planTutor(await repo.chapters(s.id), 60);
      expect(plan.chapter!.id, chs[1].chapter.id);
      expect(plan.review, hasLength(2)); // 60 นาที → ทวนได้ไม่เกิน 30 = 2 หัวข้อ
      expect(plan.steps.fold<int>(0, (n, x) => n + x.minutes), 60);
    });
  });
}
