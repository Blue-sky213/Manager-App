import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/demo_term.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/study/grading.dart';
import 'package:noir_manager/study/mastery.dart';

void main() {
  test('เติมรายละเอียดตัวอย่าง: ครบทุกระบบ · ทำซ้ำไม่เพิ่มของซ้ำ', () async {
    final study = MemoryStudyRepository();
    final cal = MemoryCalendarRepository();
    expect(await loadDemoTerm(study, cal), isTrue);
    final today = DateTime(2026, 11, 12); // พฤหัส สัปดาห์แรก → จ อ พ ผ่านไปแล้ว

    final first = await enrichDemoTerm(study, cal, today: today);
    expect(first, contains('คะแนน'));

    // คะแนน: มีครบ ดี / พอได้ / ยังไม่ได้ / ยังไม่ประเมิน
    final levels = <MasteryLevel>{};
    var scored = 0;
    for (final s in await study.subjects()) {
      for (final ch in await study.chapters(s.id)) {
        for (final t in ch.subtopics) {
          if (t.scores.isNotEmpty) scored++;
          final last = t.scores.isEmpty ? null : t.scores.last.score;
          levels.add(masteryOf(last));
        }
      }
    }
    expect(levels, containsAll(MasteryLevel.values));

    // ห้องเรียนครบทุกคาบ
    for (final s in await study.subjects()) {
      for (final a in await cal.activitiesForSubject(s.id)) {
        if (a.kind == ActivityKind.classSession) expect(a.classInfo.room, isNotNull, reason: s.name);
      }
    }

    // คาบที่ผ่านไปแล้ว: ทำแล้ว + เวลาเลิกจริง · ยกเลิก 1 คาบพร้อมเหตุผล
    final past = [
      for (var d = demoTermStart; d.isBefore(today); d = d.add(const Duration(days: 1)))
        ...await cal.occurrencesOn(d),
    ].where((o) => o.kind == ActivityKind.classSession).toList();
    expect(past.where((o) => o.status == OccurrenceStatus.done && o.actualEnd != null), isNotEmpty);
    expect(past.where((o) => o.status == OccurrenceStatus.cancelled && o.reason != null), hasLength(1));

    // ติว · งานหมวดอื่น · Inbox · วันหยุด
    final monday = await cal.occurrencesOn(demoTermStart);
    expect(monday.where((o) => o.kind == ActivityKind.tutor && o.status == OccurrenceStatus.done), hasLength(1));
    expect((await cal.occurrencesOn(DateTime(2026, 11, 10))).map((o) => o.title), contains('วิ่ง 5K'));
    expect((await cal.inbox()).map((o) => o.title), contains('อ่านสไลด์บท 2 ก่อนเรียน'));
    expect((await cal.holidays()).map((h) => h.day), contains(demoHoliday));

    // เกรด: ทุกวิชาตัวอย่างมี 5 ส่วน รวม 100 · มีคะแนนบางชิ้น · ปลายภาคยังไม่มี
    expect(first, contains('คะแนนเก็บ 6 วิชา'));
    final demo = (await study.subjects()).where((s) => s.planYear == 1 && s.planTerm == 1).toList();
    for (final s in demo) {
      final parts = await study.gradeParts(s.id);
      if (parts.isEmpty) continue;
      expect(parts.fold<double>(0, (a, p) => a + p.weight), 100);
      final r = computeGrade(parts, kuGradeScale);
      expect(r.complete, isFalse);
      expect(r.earned, greaterThan(0));
    }

    // ทำซ้ำ: ไม่เพิ่มคะแนน / ของอื่นซ้ำ
    final again = await enrichDemoTerm(study, cal, today: today);
    expect(again, startsWith('คะแนน 0 ครั้ง · ห้อง 0 คาบ'));
    expect(again, endsWith('ของอื่น 0 รายการ'));
    var scoredAfter = 0;
    for (final s in await study.subjects()) {
      for (final ch in await study.chapters(s.id)) {
        scoredAfter += ch.subtopics.where((t) => t.scores.isNotEmpty).length;
      }
    }
    expect(scoredAfter, scored);
  });

  test('ข้อมูลตัวอย่างไม่ทำให้ตารางผิดกฎ (คาบ ≤ 2 ชม. ทุกคาบ)', () async {
    final study = MemoryStudyRepository();
    final cal = MemoryCalendarRepository();
    await loadDemoCurriculum(study, cal);
    for (final s in await study.subjects()) {
      for (final a in await cal.activitiesForSubject(s.id)) {
        if (a.kind == ActivityKind.classSession) expect(a.durationMin, lessThanOrEqualTo(120));
      }
    }
  });
}
