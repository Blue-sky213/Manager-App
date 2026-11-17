// รอบ 11: สารบัญเรียนเอง IELTS · คำศัพท์ · DaVinci · Canva
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/noir_plan.dart';
import 'package:noir_manager/data/self_study.dart';
import 'package:noir_manager/skills/skill_models.dart';
import 'package:noir_manager/study/mastery.dart';

final today = DateTime(2026, 11, 17);

void main() {
  test('ใส่สารบัญ: 4 วิชา ครบทุกบท/หัวข้อ · ผูกงานในแผนเป็นรอบติว · กดซ้ำไม่ซ้อน', () async {
    final cal = MemoryCalendarRepository();
    final study = MemoryStudyRepository();
    await applyNoirPlan(cal, today);
    final r = await applySelfStudy(study, cal);
    expect(r.subjects, 4);
    expect(r.chapters, selfStudyToc.fold<int>(0, (a, t) => a + t.$2.length));
    expect(r.subtopics, selfStudyToc.fold<int>(0, (a, t) => a + t.$2.fold<int>(0, (b, c) => b + c.$2.length)));

    final subs = {for (final s in await study.subjects()) s.name: s.id};
    expect(subs.keys, containsAll(['IELTS', 'คำศัพท์ A1 → C2', 'DaVinci Resolve', 'Canva']));
    expect((await study.chapters(subs['IELTS']!)).length, 10);
    expect((await study.chapters(subs['คำศัพท์ A1 → C2']!)).map((c) => c.chapter.name.split(' ').first), ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']);

    // งานในแผนผูกถูกวิชา · งาน/ไลฟ์/อ่าน ไม่ผูก
    var tutor = 0;
    for (final id in await cal.activityIds()) {
      final a = await cal.activity(id);
      if (a.name.startsWith('IELTS · คำศัพท์')) {
        expect((a.kind, a.subjectId), (ActivityKind.tutor, subs['คำศัพท์ A1 → C2']));
      } else if (a.name.startsWith('IELTS ·')) {
        expect(a.subjectId, subs['IELTS']);
      } else if (a.name.startsWith('ฝึก · DaVinci')) {
        expect(a.subjectId, subs['DaVinci Resolve']);
      } else if (a.name.startsWith('ฝึก · Canva')) {
        expect(a.subjectId, subs['Canva']);
      } else {
        expect(a.subjectId, isNull, reason: a.name);
      }
      if (a.kind == ActivityKind.tutor) tutor++;
    }
    expect(tutor, r.linked);
    // ยังเกิดตามเวลาเดิม
    expect((await cal.occurrencesOn(DateTime(2026, 11, 18))).any((o) => o.title == 'IELTS · Writing'), isTrue);

    final again = await applySelfStudy(study, cal);
    expect((again.subjects, again.chapters, again.subtopics, again.linked), (0, 0, 0, 0));
  });

  test('% ของสกิล = หัวข้อที่ 🟢 ของวิชาคู่กัน', () async {
    final cal = MemoryCalendarRepository();
    final study = MemoryStudyRepository();
    await applySelfStudy(study, cal);
    final dv = (await study.subjects()).firstWhere((s) => s.name == 'DaVinci Resolve');
    final topics = [for (final ch in await study.chapters(dv.id)) ...ch.subtopics];
    for (final t in topics.take(4)) {
      await study.addAssessment(t.id, 90);
    }
    await study.addAssessment(topics[5].id, 50);
    final skill = Skill(name: 'DaVinci', startedAt: today);
    expect(subjectForSkill(skill.name, await study.subjects())?.id, dv.id);
    expect(await subjectRatioOr(study, skill, GradingMode.ez, 0), closeTo(4 / topics.length, 1e-9));
    expect(await subjectRatioOr(study, Skill(name: 'OBS', startedAt: today), GradingMode.ez, 0.3), 0.3);
  });
}
