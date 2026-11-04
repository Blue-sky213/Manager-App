import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/demo_term.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/study_repository.dart';

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
}
