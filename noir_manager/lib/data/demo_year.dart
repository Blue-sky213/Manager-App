/// โหมดข้อมูลตัวอย่าง 1 ปี (ทดสอบ): เหมือนใช้แอปมาแล้ว 1 ปีเต็ม
///
/// กฎ (ตกลงกับนัวร์ 12 พ.ย. 2569):
/// - ย้อนหลัง 365 วันจากวันนี้ + แผนล่วงหน้าของเทอมปัจจุบัน
/// - 2 เทอมย้อนหลัง (ราว 4 เดือนต่อเทอม) + ปิดเทอมคั่น · เทอมปัจจุบัน = ข้อมูลตัวอย่างปี 1 เทอม 1 เดิม
/// - คาบตามกฎตารางเรียนที่ตกลงแล้ว (timetable_sim) · ติวสัปดาห์ละ 1 รอบต่อวิชา · การบ้านทุก 4 สัปดาห์ · สอบกลาง / ปลายภาค
/// - ทำตามแผนเฉลี่ย ~80% · เดือนสอบต่ำลง · ปิดเทอมสูงขึ้น · วิ่ง อ/พฤ + Live ส (งาน "แทนได้")
/// - สติกเกอร์ ~60% ของวัน จากชุดในแอป
/// - **อยู่ในหน่วยความจำเท่านั้น** ไม่เขียนไฟล์ ไม่แตะข้อมูลจริง · seed ตายตัว = ได้ข้อมูลเดิมทุกครั้ง
library;

import 'dart:math';

import 'package:flutter/foundation.dart';

import '../calendar/achievements.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../calendar/memory_calendar_repository.dart';
import '../study/timetable_sim.dart';
import 'demo_term.dart';
import 'memory_study_repository.dart';
import 'study_repository.dart';

/// เปิด / ปิดโหมดข้อมูลตัวอย่าง (ไม่บันทึก · ปิดแอป = กลับข้อมูลจริง)
final demoMode = ValueNotifier<bool>(false);

/// ผลการสร้าง: repo ในหน่วยความจำ + คาบที่จำลอง (ไว้ตรวจกฎ)
class DemoYear {
  DemoYear(this.study, this.calendar, this.sessions, this.today);
  final StudyRepository study;
  final CalendarRepository calendar;
  /// คาบที่จำลอง แยกตามเทอม (ตรวจกฎทีละเทอม)
  final List<List<SimSession>> sessions;
  final DateTime today;
}

/// ช่วงเทอมย้อนหลังที่จำลอง (เริ่ม, จบ) นับจาก [today]
List<(DateTime, DateTime)> demoPastTerms(DateTime today) => [
      (today.subtract(const Duration(days: 365)), today.subtract(const Duration(days: 245))),
      (today.subtract(const Duration(days: 170)), today.subtract(const Duration(days: 40))),
    ];

/// โอกาส "ทำแล้ว" ตามชนิดงาน + ช่วงเวลา (เดือนสอบต่ำลง · ปิดเทอมสูงขึ้น)
double _doneChance(Occurrence o, bool examMonth, bool inTerm) {
  final base = switch (o.kind) {
    ActivityKind.classSession => 0.93,
    ActivityKind.tutor => 0.72,
    ActivityKind.exam => 1.0,
    _ => o.title.startsWith('ส่ง:') ? 0.9 : 0.62,
  };
  return (base + (examMonth ? -0.1 : 0) + (inTerm ? 0 : 0.08)).clamp(0, 1);
}

Future<DemoYear> buildDemoYear({DateTime? today, int seed = 2569}) async {
  final now = dayOnly(today ?? DateTime.now());
  final rnd = Random(seed);
  final study = MemoryStudyRepository();
  final cal = MemoryCalendarRepository();

  // เทอมปัจจุบัน + แผน 4 ปี (ข้อมูลตัวอย่างเดิม)
  await loadDemoCurriculum(study, cal);
  final cats = await cal.categories();
  final learn = studyCategoryId(cats) ?? cats.first.id;
  final sport = cats.where((c) => c.name == 'ออกกำลังกาย').firstOrNull?.id;
  final stream = cats.where((c) => c.name == 'สตรีม').firstOrNull?.id;

  // เทอมย้อนหลัง: ใช้รายชื่อวิชาปี 1 เทอม 2 เป็นตัวแทน
  final subjects = [for (final s in await study.subjects()) if (s.planYear == 1 && s.planTerm == 2) s];
  final sessions = <List<SimSession>>[];
  for (final (i, (from, to)) in demoPastTerms(now).indexed) {
    await cal.saveTerm(0, i + 1, from, to);
    final plan = planSimTimetable(subjects, seed: seed + i);
    sessions.add(plan.sessions);
    final mid = from.add(Duration(days: (to.difference(from).inDays ~/ 2) ~/ 7 * 7));
    for (final s in plan.sessions) {
      await cal.addActivity(simToActivity(s, categoryId: learn, from: from, to: to));
    }
    for (final s in subjects) {
      // ติวสัปดาห์ละ 1 รอบ (เย็นวันธรรมดา) · การบ้านทุก 4 สัปดาห์ (ส่งศุกร์ 22:30)
      var week = 0;
      for (var w = from; w.isBefore(to); w = w.add(const Duration(days: 7)), week++) {
        final monday = w.subtract(Duration(days: w.weekday - 1));
        await cal.addActivity(NewActivity(
          name: 'ติว · ${s.name}',
          categoryId: learn,
          importance: 2,
          timed: true,
          day: monday.add(Duration(days: rnd.nextInt(5))),
          startMinute: 19 * 60,
          durationMin: 90,
          subjectId: s.id,
          kind: ActivityKind.tutor,
        ));
        if (week % 4 == 2) {
          await cal.addActivity(NewActivity(
            name: 'ส่ง: การบ้าน ${week ~/ 4 + 1} · ${s.name}',
            categoryId: learn,
            importance: 3,
            timed: true,
            day: monday.add(const Duration(days: 4)),
            startMinute: 22 * 60 + 30,
            durationMin: 30,
            subjectId: s.id,
          ));
        }
      }
      // สอบกลางภาค / ปลายภาค (เสาร์ 09:00 · ไม่ชนคาบ)
      for (final (k, d) in [(0, mid), (1, to)]) {
        final sat = d.subtract(Duration(days: (d.weekday - 6) % 7));
        await cal.addActivity(NewActivity(
          name: '${k == 0 ? 'สอบกลางภาค' : 'สอบปลายภาค'} · ${s.name}',
          categoryId: learn,
          importance: 3,
          timed: true,
          day: sat,
          startMinute: (9 + (s.id % 3) * 3) * 60,
          durationMin: 120,
          subjectId: s.id,
          kind: ActivityKind.exam,
        ));
      }
    }
  }

  // งานแทนได้ทั้งปี: วิ่ง อ/พฤ 17:30 · Live CS2 ส 20:00
  final yearStart = now.subtract(const Duration(days: 365));
  final until = now.add(const Duration(days: 60));
  await cal.addActivity(NewActivity(
      name: 'วิ่ง 5K', categoryId: sport, importance: 1, timed: true, day: yearStart,
      startMinute: 17 * 60 + 30, durationMin: 45, repeat: RepeatKind.weekly, weekdays: {2, 4}, endDate: until));
  await cal.addActivity(NewActivity(
      name: 'Live CS2', categoryId: stream, importance: 1, timed: true, day: yearStart,
      startMinute: 20 * 60, durationMin: 120, repeat: RepeatKind.weekly, weekdays: {6}, endDate: until));

  // ผลย้อนหลัง: ทำแล้ว / ยกเลิกมีเหตุผล / พลาด · สติกเกอร์ ~60% ของวัน
  final terms = demoPastTerms(now);
  final stickers = [
    for (final p in await cal.stickerPacks())
      if (p.builtin) ...p.stickers,
  ];
  for (var d = yearStart; d.isBefore(now); d = DateTime(d.year, d.month, d.day + 1)) {
    final inTerm = terms.any((t) => !d.isBefore(t.$1) && !d.isAfter(t.$2)) || !d.isBefore(demoTermStart);
    final examMonth = d.month == 3 || d.month == 10;
    for (final o in await cal.occurrencesOn(d)) {
      if (o.status != OccurrenceStatus.planned) continue;
      final r = rnd.nextDouble();
      final p = _doneChance(o, examMonth, inTerm);
      if (r < p) {
        await cal.setDone(o.id, true);
      } else if (r < p + 0.05) {
        await cal.cancel(o.id, rnd.nextBool() ? 'ติดธุระ' : 'ไม่สบาย');
      }
    }
    if (stickers.isNotEmpty && rnd.nextDouble() < 0.6) {
      await cal.stickDay(d, stickers[rnd.nextInt(stickers.length)].id);
    }
  }
  return DemoYear(study, cal, sessions, now);
}

/// ตัวตรวจกฎ · ว่าง = ผ่าน (ใช้กับข้อมูลตัวอย่าง และเช็กข้อมูลที่ใส่เองได้)
Future<List<String>> checkDemoYear(CalendarRepository cal, DateTime today, List<List<SimSession>> sessions) async {
  final errors = [for (final term in sessions) ...checkSimRules(term)];
  final all = <Occurrence>[];
  for (var i = 1; i <= 365; i++) {
    final d = today.subtract(Duration(days: i));
    all.addAll(await cal.occurrencesOn(d));
  }
  for (var i = 0; i <= 30; i++) {
    final d = today.add(Duration(days: i + 1));
    for (final o in await cal.occurrencesOn(d)) {
      if (o.status == OccurrenceStatus.done) errors.add('ทำแล้วล่วงหน้า: ${o.title} ${dayKey(d)}');
    }
  }
  for (final o in all) {
    if (o.kind == ActivityKind.classSession && o.day.weekday == DateTime.sunday) {
      errors.add('มีคาบวันอาทิตย์: ${o.title} ${dayKey(o.day)}');
    }
  }
  final p = percentDone(all);
  if (p == null || p < 65 || p > 92) errors.add('ทำตามแผนเฉลี่ย ${p?.round()}% (ต้อง 65–92%)');
  return errors;
}
