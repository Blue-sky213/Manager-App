/// กฎของรอบติว: นับรอบต่อสัปดาห์ + วางเนื้อหาของรอบถัดไป (ตามหลักการติวในแผน v0.2)
library;

import '../calendar/calendar_models.dart';
import '../data/study_models.dart';
import 'mastery.dart';

/// สรุปรอบของสัปดาห์
class WeekQuota {
  const WeekQuota({required this.target, required this.classes, required this.tutors});

  /// รอบต่อสัปดาห์ตามความสำคัญของวิชา
  final int target;

  /// คาบเรียนสัปดาห์นี้ (EZ: ยกเลิก/วันหยุดก็ยังนับ)
  final int classes;

  /// รอบติวที่จองแล้ว (ไม่นับที่ยกเลิก)
  final int tutors;

  /// ต้องติวกี่รอบ = เป้า − คาบเรียน
  int get tutorNeeded => (target - classes).clamp(0, target);
  int get remaining => (tutorNeeded - tutors).clamp(0, tutorNeeded);
}

WeekQuota weekQuota(int target, Iterable<Occurrence> weekItems) => WeekQuota(
      target: target,
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
