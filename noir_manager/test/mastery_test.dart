import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/study_models.dart';
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

  test('เปลี่ยนชื่อ + เปลี่ยนความสำคัญ + ลบวิชา (ลบบทและหัวข้อตามไปด้วย)', () async {
    final repo = MemoryStudyRepository.seeded();
    final id = await repo.addSubject('Test 67', importance: 1);
    final chapterId = await repo.addChapter(id, 'Test deleat');
    await repo.addSubtopic(chapterId, 'Tesst 67');

    await repo.renameSubject(id, 'DataCOM');
    await repo.setSubjectImportance(id, 3);
    await repo.renameChapter(chapterId, 'บท 1');
    final topicId = (await repo.chapters(id)).first.subtopics.first.id;
    await repo.renameSubtopic(topicId, 'Test 67');

    final subject = (await repo.subjects()).firstWhere((s) => s.id == id);
    expect(subject.name, 'DataCOM');
    expect(subject.sessionsPerWeek, 3);
    final chapters = await repo.chapters(id);
    expect(chapters.first.chapter.name, 'บท 1');
    expect(chapters.first.subtopics.first.name, 'Test 67');

    await repo.deleteSubject(id);
    expect((await repo.subjects()).map((s) => s.name), ['DaVinci Resolve']);
    expect(await repo.chapters(id), isEmpty);
  });

  test('Advanced: เพิ่มหัวข้อที่เคยตกแต่ตอนนี้ยังไม่ถึงดี ไว้ท้ายรายการ · EZ ไม่เพิ่ม', () async {
    final repo = MemoryStudyRepository.seeded();
    final subject = (await repo.subjects()).first;
    final t = (await repo.chapters(subject.id)).first.subtopics;

    await repo.addAssessment(t[0].id, 45, at: DateTime(2026, 11, 3)); // ต่ำ
    await repo.addAssessment(t[1].id, 59, at: DateTime(2026, 11, 1)); // เคยตก
    await repo.addAssessment(t[1].id, 80, at: DateTime(2026, 11, 3)); // ตอนนี้พอได้
    await repo.addAssessment(t[2].id, 75, at: DateTime(2026, 11, 3)); // ไม่เคยตก

    final topics = (await repo.chapters(subject.id)).first.subtopics;
    expect(reviewOrder(topics).map((x) => x.id), [t[0].id]);
    expect(
      reviewOrder(topics, mode: GradingMode.advanced).map((x) => x.id),
      [t[0].id, t[1].id],
    );

    expect(await repo.gradingMode(), GradingMode.ez);
    await repo.setGradingMode(GradingMode.advanced);
    expect(await repo.gradingMode(), GradingMode.advanced);
  });

  group('Advanced: เคยตก → ต้องเขียว 2 รอบติดถึงผ่าน', () {
    Future<(MemoryStudyRepository, int, int)> setup(List<int> scores) async {
      final repo = MemoryStudyRepository.seeded();
      final subjectId = (await repo.subjects()).first.id;
      final topicId = (await repo.chapters(subjectId)).first.subtopics.first.id;
      for (var i = 0; i < scores.length; i++) {
        await repo.addAssessment(topicId, scores[i], at: DateTime(2026, 11, 1 + i));
      }
      return (repo, subjectId, topicId);
    }

    Future<Subtopic> topicOf(MemoryStudyRepository repo, int subjectId) async =>
        (await repo.chapters(subjectId)).first.subtopics.first;

    test('แดง → เขียว 1 รอบ: ใช้ค่าเฉลี่ย ยังมีป้ายเช็กซ้ำ และต้องทวน', () async {
      final (repo, subjectId, _) = await setup([55, 81]);
      final t = await topicOf(repo, subjectId);
      expect(shownScore(t, GradingMode.advanced), 68);
      expect(showRecheck(t, GradingMode.advanced), isTrue);
      expect(needsGreenDecision(t), isFalse);
      expect(reviewOrder([t], mode: GradingMode.advanced), [t]);
    });

    test('แดง → เขียว 2 รอบติด แต่ค่าเฉลี่ยยังส้ม: ต้องถาม · นับเป็นเขียวแล้วผ่าน', () async {
      final (repo, subjectId, topicId) = await setup([45, 82, 90]);
      var t = await topicOf(repo, subjectId);
      expect(t.averageScore, 72);
      expect(needsGreenDecision(t), isTrue);

      // ผู้ใช้เลือก "นับเป็นเขียว" → คะแนนก่อน 2 รอบล่าสุดเป็นโมฆะ
      await repo.resetHistoryFrom(topicId, t.scores[t.scores.length - 2].at);
      t = await topicOf(repo, subjectId);
      expect(t.averageScore, 86);
      expect(showRecheck(t, GradingMode.advanced), isFalse);
      expect(reviewOrder([t], mode: GradingMode.advanced), isEmpty);
    });

    test('แดง → เขียว 2 รอบติด และค่าเฉลี่ยเขียวอยู่แล้ว: ผ่านเลย ไม่ต้องถาม', () async {
      final (repo, subjectId, _) = await setup([59, 100, 100]);
      final t = await topicOf(repo, subjectId);
      expect(shownScore(t, GradingMode.advanced), 86);
      expect(needsGreenDecision(t), isFalse);
      expect(showRecheck(t, GradingMode.advanced), isFalse);
    });

    test('จำค่าตั้งค่าได้', () async {
      final repo = MemoryStudyRepository();
      expect(await repo.getSetting('green_twice_rule'), isNull);
      await repo.setSetting('green_twice_rule', 'green');
      expect(await repo.getSetting('green_twice_rule'), 'green');
    });
  });

  group('Advanced: เคยเขียว → ตก 2 รอบติด + ตารางแก้คะแนน', () {
    Future<(MemoryStudyRepository, int, int)> setup(List<int> scores) async {
      final repo = MemoryStudyRepository.seeded();
      final subjectId = (await repo.subjects()).first.id;
      final topicId = (await repo.chapters(subjectId)).first.subtopics.first.id;
      for (var i = 0; i < scores.length; i++) {
        await repo.addAssessment(topicId, scores[i], at: DateTime(2026, 11, 1 + i));
      }
      return (repo, subjectId, topicId);
    }

    Future<Subtopic> topicOf(MemoryStudyRepository repo, int subjectId) async =>
        (await repo.chapters(subjectId)).first.subtopics.first;

    test('99 → 45 → 55: ต้องถาม · ถูกจริง = คิดจาก 2 รอบแดง (เฉลี่ย 50)', () async {
      final (repo, subjectId, topicId) = await setup([99, 45, 55]);
      var t = await topicOf(repo, subjectId);
      expect(t.averageScore, 66); // ค่าเฉลี่ยรวมดูดีเกินจริง
      expect(needsRedDecision(t), isTrue);

      await repo.resetHistoryFrom(topicId, t.scores[t.scores.length - 2].at);
      t = await topicOf(repo, subjectId);
      expect(t.averageScore, 50);
      expect(masteryOf(shownScore(t, GradingMode.advanced)), MasteryLevel.bad);
    });

    test('ตก 2 รอบแต่ไม่เคยเขียว: ไม่ต้องถาม', () async {
      final (repo, subjectId, _) = await setup([70, 45, 55]);
      expect(needsRedDecision(await topicOf(repo, subjectId)), isFalse);
    });

    test('ประวัติ: แก้ / ลบ / ยกเลิกโมฆะ', () async {
      final (repo, subjectId, topicId) = await setup([99, 45, 55]);
      final t = await topicOf(repo, subjectId);
      await repo.resetHistoryFrom(topicId, t.scores[1].at);

      var rows = await repo.scoreHistory(topicId);
      expect(rows.map((r) => r.voided), [true, false, false]);

      await repo.updateAssessment(rows[1].id, 85); // ใส่ผิด แก้ 45 → 85
      await repo.deleteAssessment(rows[2].id); // ลบรอบ 55
      await repo.undoReset(topicId); // นำ 99 กลับมาคิด

      rows = await repo.scoreHistory(topicId);
      expect(rows.map((r) => r.score), [99, 85]);
      expect(rows.any((r) => r.voided), isFalse);
      expect((await topicOf(repo, subjectId)).averageScore, 92);
    });
  });
}
