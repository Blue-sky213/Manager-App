import 'package:flutter_test/flutter_test.dart';

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
}
