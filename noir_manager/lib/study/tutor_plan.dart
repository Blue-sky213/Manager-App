/// กฎของรอบติว: นับรอบต่อสัปดาห์ + วางเนื้อหาของรอบถัดไป (ตามหลักการติวในแผน v0.2)
library;

import '../calendar/calendar_models.dart';
import '../data/study_models.dart';
import 'mastery.dart';

/// สรุปรอบของสัปดาห์
class WeekQuota {
  const WeekQuota({
    required this.target,
    required this.classes,
    required this.tutors,
    this.advanced = false,
    this.passed = false,
  });

  /// โหมด Advanced: สัปดาห์ที่มีคาบเรียน ต้องติวอย่างน้อย 1 รอบ แม้คาบเรียนครบเป้าแล้ว
  final bool advanced;

  /// บทที่เรียนแล้วผ่านเกณฑ์ (เช่น ≥ 80%) → ติวไม่บังคับ "พักได้"
  final bool passed;

  /// รอบต่อสัปดาห์ตามความสำคัญของวิชา
  final int target;

  /// คาบเรียนสัปดาห์นี้ (EZ: ยกเลิก/วันหยุดก็ยังนับ)
  final int classes;

  /// รอบติวที่จองแล้ว (ไม่นับที่ยกเลิก)
  final int tutors;

  /// รอบติวตามกฎ (ก่อนหักผ่านเกณฑ์) = เป้า − คาบเรียน · Advanced + มีคาบ → อย่างน้อย 1
  int get ruleNeeded {
    final base = (target - classes).clamp(0, target);
    return advanced && classes > 0 && base < 1 ? 1 : base;
  }

  /// ต้องติวกี่รอบ (ผ่านเกณฑ์แล้ว = 0 · ติวต่อได้ตามใจ)
  int get tutorNeeded => passed ? 0 : ruleNeeded;
  int get remaining => (tutorNeeded - tutors).clamp(0, tutorNeeded);
}

WeekQuota weekQuota(int target, Iterable<Occurrence> weekItems, {bool advanced = false, bool passed = false}) =>
    WeekQuota(
      target: target,
      advanced: advanced,
      passed: passed,
      classes: weekItems
          .where((o) =>
              o.kind == ActivityKind.classSession &&
              o.status != OccurrenceStatus.moved &&
              o.status != OccurrenceStatus.inbox)
          .length,
      tutors: weekItems
          .where((o) =>
              o.kind == ActivityKind.tutor &&
              (o.status == OccurrenceStatus.planned || o.status == OccurrenceStatus.done))
          .length,
    );

/// ขั้นตอน 1 ช่วงในรอบติว
class TutorStep {
  const TutorStep(this.minutes, this.label);
  final int minutes;
  final String label;
}

class TutorPlan {
  const TutorPlan({required this.chapter, required this.review, required this.steps});

  /// บทที่จะติว (null = ติวครบทุกบทแล้ว → ทวนอย่างเดียว)
  final Chapter? chapter;

  /// หัวข้อที่ยังแดง (ทวนหัวข้อละ 15 นาที ไม่เกินครึ่งรอบ)
  final List<Subtopic> review;
  final List<TutorStep> steps;
}

/// บทถัดไปที่ต้องติว: บทที่ "กำลังติว" ก่อน แล้วค่อยบทที่ยังไม่เริ่ม (ตามลำดับบท)
Chapter? nextChapter(List<ChapterWithTopics> chapters) {
  for (final ch in chapters) {
    if (ch.chapter.status == ChapterStatus.learning) return ch.chapter;
  }
  for (final ch in chapters) {
    if (ch.chapter.status == ChapterStatus.todo) return ch.chapter;
  }
  return null;
}

/// วางเนื้อหารอบติวยาว [minutes] นาที
TutorPlan planTutor(List<ChapterWithTopics> chapters, int minutes) {
  final chapter = nextChapter(chapters);
  final weak = [
    for (final ch in chapters)
      for (final t in ch.subtopics)
        if (masteryOf(t.latestScore) == MasteryLevel.bad) t,
  ]..sort((a, b) => a.latestScore!.compareTo(b.latestScore!));

  // ทวนหัวข้อละ 15 นาที ไม่เกินครึ่งรอบ · ไม่มีบทใหม่ = ทวนได้ทั้งรอบ
  final maxReview = chapter == null ? minutes ~/ 15 : (minutes ~/ 2) ~/ 15;
  final review = weak.take(maxReview).toList();
  final reviewMin = review.length * 15;

  final steps = <TutorStep>[];
  if (chapter != null) {
    final kind = chapter.kind;
    var left = minutes - reviewMin;
    // ช่วงเปิด/ปิด ใส่เมื่อรอบยาวพอ
    final opening = left >= 45 ? (kind == ChapterKind.practice ? 10 : 5) : 0;
    final closing = left >= 60 ? (kind == ChapterKind.practice ? 5 : 10) : 0;
    left -= opening + closing;
    if (opening > 0) {
      steps.add(TutorStep(opening,
          kind == ChapterKind.practice ? 'ดูตัวอย่างทีละขั้น' : 'ทวนบทก่อนแบบปิดโน้ต'));
    }
    final body = switch (kind) {
      ChapterKind.theory => 'เรียน ${chapter.name} (25 นาที + พัก 5)',
      ChapterKind.practice => 'ลงมือทำ ${chapter.name} (50 นาที + พัก 10)',
      ChapterKind.mixed => 'ทฤษฎีครึ่งแรก → ลงมือทำครึ่งหลัง · ${chapter.name}',
    };
    steps.add(TutorStep(left, body));
    for (final t in review) {
      steps.add(TutorStep(15, 'ทวน ${t.name} (${t.latestScore}%)'));
    }
    if (closing > 0) {
      steps.add(TutorStep(closing,
          kind == ChapterKind.practice ? 'งานสั้นวัดผล · คละโจทย์บทเก่า' : 'ทดสอบตัวเอง → บันทึกคะแนน'));
    }
  } else {
    for (final t in review) {
      steps.add(TutorStep(15, 'ทวน ${t.name} (${t.latestScore}%)'));
    }
  }
  return TutorPlan(chapter: chapter, review: review, steps: steps);
}

/// วันจันทร์ของสัปดาห์ที่มี [day]
DateTime mondayOf(DateTime day) {
  final d = dayOnly(day);
  return DateTime(d.year, d.month, d.day - (d.weekday - 1));
}


/// ตั้งค่า: เกณฑ์ "ผ่าน · พักได้" (%) ของบทที่เรียนแล้ว
const tutorPassKey = 'tutor_pass';
const defaultTutorPass = 80;

/// ตั้งค่าต่อวิชาในสัปดาห์: เลือก "พักสัปดาห์นี้" แล้ว (key = `rest:subjectId:วันจันทร์`)
String restKey(int subjectId, DateTime monday) =>
    'rest:$subjectId:${monday.year}-${monday.month}-${monday.day}';

/// บทที่เรียนถึง (ลำดับในรายการบท) จากบันทึกเรียน · null = ยังไม่เคยบันทึก
int? reachedIndex(List<ChapterWithTopics> chapters, List<ClassLog> logs) {
  int? best;
  for (final l in logs) {
    final i = chapters.indexWhere((c) => c.chapter.id == l.chapterId);
    if (i >= 0 && (best == null || i > best)) best = i;
  }
  return best;
}

/// ขอบเขตติว = บทแรกถึงบทที่เรียนถึง · ยังไม่เคยบันทึก → ทุกบท (แบบเดิม)
List<ChapterWithTopics> tutorScope(List<ChapterWithTopics> chapters, List<ClassLog> logs) {
  final i = reachedIndex(chapters, logs);
  return i == null ? chapters : chapters.sublist(0, i + 1);
}

/// คะแนนเฉลี่ยของหัวข้อในขอบเขต · มีหัวข้อที่ยังไม่ประเมิน → null (ยังตัดสินไม่ได้)
double? scopeAverage(List<ChapterWithTopics> scope) {
  final topics = [for (final c in scope) ...c.subtopics];
  if (topics.isEmpty || topics.any((t) => t.latestScore == null)) return null;
  return topics.map((t) => t.latestScore!).reduce((a, b) => a + b) / topics.length;
}

/// ผ่านเกณฑ์ "พักได้" ไหม
bool scopePassed(List<ChapterWithTopics> scope, int pass) {
  final avg = scopeAverage(scope);
  return avg != null && avg >= pass;
}

/// หัวข้อในขอบเขต เรียงอ่อนสุดก่อน (ยังไม่ประเมิน = อ่อนสุด) · ใช้เลือกว่ารอบนี้ติวอะไร
List<Subtopic> weakestFirst(List<ChapterWithTopics> scope) {
  final topics = [for (final c in scope) ...c.subtopics];
  topics.sort((a, b) => (a.latestScore ?? -1).compareTo(b.latestScore ?? -1));
  return topics;
}
