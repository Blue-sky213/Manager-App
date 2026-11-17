/// ย้ายสารบัญเรียนเอง จาก "วิชา" (รอบ 11) → สกิล (รอบ 13)
/// นัวร์ต้องการให้เรียนเองแยกจากแผน 4 ปี (วิชาเรียนเองขึ้นเตือน "ขาดรหัส · หน่วยกิต")
/// คะแนนเดิม: หัวข้อชื่อตรงกัน → ย้ายไปหัวข้อนั้น · ไม่ตรง → บท "ย้ายมาจากวิชาเดิม" (ไม่ทิ้งคะแนน)
library;

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../skills/skill_lessons.dart';
import '../skills/skill_models.dart';
import 'study_repository.dart';

/// วิชาเรียนเองเดิม → คำค้นสกิล
const selfStudySubjects = {'IELTS': 'ielts', 'DaVinci Resolve': 'davinci', 'Canva': 'canva'};

const movedChapterName = 'ย้ายมาจากวิชาเดิม';

typedef MoveResult = ({int subjects, int scores, int unlinked, LessonResult lessons});

Future<MoveResult> moveSelfStudyToSkills(StudyRepository study, CalendarRepository cal) async {
  final r = cal.skillRepo;
  final lessons = await applyLessonPresets(r);
  var subjects = 0, scores = 0, unlinked = 0;
  for (final sub in await study.subjects()) {
    final key = selfStudySubjects[sub.name];
    if (key == null) continue;
    final skill = skillByKey(await r.skills(), key)!;
    final nodeIds = {for (final n in await r.nodes()) if (n.skillId == skill.id) n.id};
    int? movedNode;
    for (final ch in await study.chapters(sub.id)) {
      for (final t in ch.subtopics) {
        if (t.scores.isEmpty) continue;
        final topics = await r.topics();
        var target = topics.where((x) => nodeIds.contains(x.nodeId) && x.name == t.name).firstOrNull?.id;
        if (target == null) {
          movedNode ??= await r.saveNode(SkillNode(skillId: skill.id, name: movedChapterName, sort: 99));
          nodeIds.add(movedNode);
          target = await r.saveTopic(SkillTopic(nodeId: movedNode, name: t.name));
        }
        for (final p in t.scores) {
          await r.addTopicScore(target, p.score, at: p.at);
        }
        scores++;
      }
    }
    // งานในปฏิทินที่ผูกเป็นรอบติว → กลับเป็นงานธรรมดา (ยังเกิดตามเวลาเดิม)
    for (final aid in await cal.activityIds()) {
      final a = await cal.activity(aid);
      if (a.subjectId != sub.id) continue;
      await cal.updateActivity(
        aid,
        NewActivity(
          name: a.name,
          categoryId: a.categoryId,
          importance: a.importance,
          timed: a.timed,
          day: a.startDate,
          startMinute: a.startMinute,
          durationMin: a.durationMin,
          repeat: a.repeat,
          weekdays: a.weekdays,
          endDate: a.endDate,
          presetId: a.presetId,
          dates: a.toDraft().dates,
          subjectId: null,
          kind: ActivityKind.todo,
          flexible: a.flexible,
        ),
      );
      unlinked++;
    }
    await study.deleteSubject(sub.id);
    subjects++;
  }
  return (subjects: subjects, scores: scores, unlinked: unlinked, lessons: lessons);
}
