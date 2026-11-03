import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/study/mastery.dart';

void main() {
  group('masteryOf: แบ่งระดับตามกฎ >80 / 60–80 / <60', () {
    test('ยังไม่ประเมิน', () => expect(masteryOf(null), MasteryLevel.none));
    test('81 = ดี', () => expect(masteryOf(81), MasteryLevel.good));
    test('80 = พอได้ (ขอบบน)', () => expect(masteryOf(80), MasteryLevel.warn));
    test('60 = พอได้ (ขอบล่าง)', () => expect(masteryOf(60), MasteryLevel.warn));
    test('59 = ยังไม่ได้', () => expect(masteryOf(59), MasteryLevel.bad));
  });

  test('คะแนนล่าสุดชนะ แต่ป้ายเช็กซ้ำยังอยู่ถ้าเคยต่ำกว่า 60', () async {
    final repo = MemoryStudyRepository.seeded();
    final subject = (await repo.subjects()).first;
    final topic = (await repo.chapters(subject.id)).first.subtopics.first;

    await repo.addAssessment(topic.id, 40, at: DateTime(2026, 11, 1));
    await repo.addAssessment(topic.id, 90, at: DateTime(2026, 11, 3));

    final after = (await repo.chapters(subject.id)).first.subtopics.first;
    expect(after.latestScore, 90);
    expect(after.everBelow60, isTrue);
  });

  test('reviewOrder: คะแนนต่ำก่อน แล้วตามด้วยหัวข้อติดธงที่ยังไม่ถึงดี', () async {
    final repo = MemoryStudyRepository.seeded();
    final subject = (await repo.subjects()).first;
    final t = (await repo.chapters(subject.id)).first.subtopics;

    await repo.addAssessment(t[0].id, 90); // ดี → ไม่ต้องทวน
    await repo.addAssessment(t[1].id, 70); // พอได้ + ธง → ทวนทีหลัง
    await repo.setExamFlag(t[1].id, true);
    await repo.addAssessment(t[2].id, 50); // ต่ำ
    await repo.addAssessment(t[3].id, 30); // ต่ำสุด → ทวนก่อน

    final topics = (await repo.chapters(subject.id)).first.subtopics;
    expect(reviewOrder(topics).map((x) => x.id), [t[3].id, t[2].id, t[1].id]);
  });
}
