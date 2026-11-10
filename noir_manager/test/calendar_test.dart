import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/clash_page.dart';
import 'package:noir_manager/calendar/class_stats.dart';
import 'package:noir_manager/calendar/free_slots.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/study_models.dart';

void main() {
  final mon = DateTime(2026, 11, 2); // จันทร์
  final tue = DateTime(2026, 11, 3);
  final wed = DateTime(2026, 11, 4);

  NewActivity gym({RepeatKind repeat = RepeatKind.daily, Set<int> days = const {}}) =>
      NewActivity(
        name: 'ออกกำลังกาย',
        categoryId: 2,
        importance: 2,
        timed: true,
        day: mon,
        startMinute: 17 * 60,
        durationMin: 45,
        repeat: repeat,
        weekdays: days,
      );

  group('กฎพื้นฐาน', () {
    test('ชั่วโมงนอน: 23:30 → 07:00 = 7.5 · 00:30 → 07:00 = 6.5', () {
      const night = LifeBaseDay(weekday: 1, bedMinute: 23 * 60 + 30, wakeMinute: 7 * 60);
      const after = LifeBaseDay(weekday: 1, bedMinute: 30, wakeMinute: 7 * 60);
      const next = LifeBaseDay(weekday: 2, bedMinute: 0, wakeMinute: 7 * 60);
      expect(sleepHours(night, next), 7.5);
      expect(sleepHours(after, next), 6.5);
    });

    test('ทุกสัปดาห์ จ/พ: มีวันจันทร์และพุธ ไม่มีวันอังคาร', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(gym(repeat: RepeatKind.weekly, days: {1, 3}));
      expect(await repo.occurrencesOn(mon), hasLength(1));
      expect(await repo.occurrencesOn(tue), isEmpty);
      expect(await repo.occurrencesOn(wed), hasLength(1));
    });

    test('เปิดดูวันเดิมหลายรอบ ไม่สร้างงานซ้ำ', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(gym());
      await repo.occurrencesOn(mon);
      await repo.occurrencesOn(mon);
      expect(await repo.occurrencesOn(mon), hasLength(1));
    });

    test('ชนขอบพอดีไม่นับว่าทับ', () {
      final a = DateTime(2026, 11, 2, 17);
      final b = DateTime(2026, 11, 2, 18);
      final c = DateTime(2026, 11, 2, 19);
      expect(rangesOverlap(a, b, b, c), isFalse);
      expect(rangesOverlap(a, c, b, c), isTrue);
    });
  });

  group('Calendar Core', () {
    test('ยกเลิกเก็บเหตุผล', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(gym());
      final o = (await repo.occurrencesOn(mon)).single;
      await repo.cancel(o.id, 'ป่วย');
      final after = (await repo.occurrencesOn(mon)).single;
      expect(after.status, OccurrenceStatus.cancelled);
      expect(after.reason, 'ป่วย');
    });

    test('เลื่อนเฉพาะครั้งนี้: ครั้งเดิม = moved · วันใหม่มีงาน · ไม่สร้างของวันเดิมซ้ำ', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(gym());
      final o = (await repo.occurrencesOn(mon)).single;
      await repo.moveOccurrence(o.id, tue,
          start: DateTime(2026, 11, 3, 8), end: DateTime(2026, 11, 3, 8, 45));

      expect((await repo.occurrencesOn(mon)).single.status, OccurrenceStatus.moved);
      final tueItems = await repo.occurrencesOn(tue);
      expect(tueItems, hasLength(2)); // ของอังคารเอง (17:00) + ที่เลื่อนมา (08:00)
      expect(tueItems.first.startAt, DateTime(2026, 11, 3, 8));
      expect(tueItems.first.movedFromId, o.id);
    });

    test('ยังไม่รู้วัน → Updates → เลือกวันแทน', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(gym(repeat: RepeatKind.none));
      final o = (await repo.occurrencesOn(mon)).single;
      await repo.sendToInbox(o.id);
      expect((await repo.inbox()).single.id, o.id);

      await repo.moveOccurrence(o.id, wed,
          start: DateTime(2026, 11, 4, 17), end: DateTime(2026, 11, 4, 17, 45));
      expect(await repo.inbox(), isEmpty);
      expect((await repo.occurrencesOn(wed)).single.status, OccurrenceStatus.planned);
    });

    test('เลื่อนทั้งแถว: ตั้งแต่วันที่เลือกเปลี่ยนเวลา วันก่อนหน้าไม่เปลี่ยน', () async {
      final repo = MemoryCalendarRepository();
      final id = await repo.addActivity(gym());
      await repo.occurrencesOn(mon);
      await repo.occurrencesOn(tue);
      await repo.moveSeries(id, tue, 19 * 60, 60);

      expect((await repo.occurrencesOn(mon)).single.startAt, DateTime(2026, 11, 2, 17));
      expect((await repo.occurrencesOn(tue)).single.startAt, DateTime(2026, 11, 3, 19));
      expect((await repo.occurrencesOn(wed)).single.endAt, DateTime(2026, 11, 4, 20));
    });

    test('findOverlaps: เจองานที่ทับ ไม่นับตัวเองและงานที่ยกเลิกแล้ว', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(gym(repeat: RepeatKind.none));
      final items = await repo.occurrencesOn(mon);
      final clash = findOverlaps(
          items, DateTime(2026, 11, 2, 17, 30), DateTime(2026, 11, 2, 18, 30));
      expect(clash, hasLength(1));
      expect(
          findOverlaps(items, DateTime(2026, 11, 2, 17, 30),
              DateTime(2026, 11, 2, 18, 30),
              excludeId: items.single.id),
          isEmpty);
    });
  });

  group('Preset · เลือกวันเอง · แก้ไขงาน', () {
    NewActivity re4() => NewActivity(
          name: 'RE4',
          categoryId: 3,
          importance: 3,
          timed: true,
          day: wed,
          startMinute: 20 * 60,
          durationMin: 4 * 60,
          repeat: RepeatKind.dates,
          presetId: 1,
          dates: [
            ScheduledDate(wed),
            ScheduledDate(DateTime(2026, 11, 6), startMinute: 19 * 60, durationMin: 3 * 60),
            ScheduledDate(DateTime(2026, 11, 9)),
          ],
        );

    test('มี Preset "Stream" ตั้งต้น', () async {
      final repo = MemoryCalendarRepository();
      final p = (await repo.presets()).single;
      expect(p.name, 'Stream');
      expect((p.startMinute, p.durationMin), (20 * 60, 240));
    });

    test('เลือกวันเอง: มีงานเฉพาะวันที่เลือก และแต่ละวันใช้เวลาของตัวเอง', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(re4());
      expect(await repo.occurrencesOn(tue), isEmpty);
      expect(await repo.occurrencesOn(DateTime(2026, 11, 5)), isEmpty);

      final w = (await repo.occurrencesOn(wed)).single;
      expect(w.startAt, DateTime(2026, 11, 4, 20));
      expect(w.endAt, DateTime(2026, 11, 5, 0)); // ข้ามเที่ยงคืน

      final f = (await repo.occurrencesOn(DateTime(2026, 11, 6))).single;
      expect(f.startAt, DateTime(2026, 11, 6, 19));
      expect(f.endAt, DateTime(2026, 11, 6, 22));

      expect(await repo.occurrencesOn(DateTime(2026, 11, 9)), hasLength(1));
    });

    test('ถึงวันที่: ทุกวันแต่หยุดหลังวันสิ้นสุด', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(NewActivity(
        name: 'ติว',
        categoryId: 1,
        importance: 2,
        timed: false,
        day: mon,
        repeat: RepeatKind.daily,
        endDate: tue,
      ));
      expect(await repo.occurrencesOn(mon), hasLength(1));
      expect(await repo.occurrencesOn(tue), hasLength(1));
      expect(await repo.occurrencesOn(wed), isEmpty);
    });

    test('แก้ไขงาน: ครั้งที่ทำแล้วไม่เปลี่ยน ครั้งต่อไปใช้เวลาใหม่', () async {
      final repo = MemoryCalendarRepository();
      final id = await repo.addActivity(gym());
      final m = (await repo.occurrencesOn(mon)).single;
      await repo.setDone(m.id, true);
      await repo.occurrencesOn(tue);

      final d = (await repo.activity(id)).toDraft();
      await repo.updateActivity(
          id,
          NewActivity(
            name: 'วิ่ง',
            categoryId: d.categoryId,
            importance: d.importance,
            timed: true,
            day: d.day,
            startMinute: 6 * 60,
            durationMin: 30,
            repeat: d.repeat,
          ),
          from: tue);

      final monAfter = (await repo.occurrencesOn(mon)).single;
      expect(monAfter.status, OccurrenceStatus.done);
      expect(monAfter.startAt, DateTime(2026, 11, 2, 17));
      final t = (await repo.occurrencesOn(tue)).single;
      expect(t.title, 'วิ่ง');
      expect(t.startAt, DateTime(2026, 11, 3, 6));
      expect(t.endAt, DateTime(2026, 11, 3, 6, 30));
    });

    test('แก้เวลาเฉพาะวันนี้: วันอื่นไม่เปลี่ยน', () async {
      final repo = MemoryCalendarRepository();
      await repo.addActivity(gym());
      final m = (await repo.occurrencesOn(mon)).single;
      await repo.updateOccurrenceTime(
          m.id, DateTime(2026, 11, 2, 18), DateTime(2026, 11, 2, 19));
      expect((await repo.occurrencesOn(mon)).single.startAt, DateTime(2026, 11, 2, 18));
      expect((await repo.occurrencesOn(tue)).single.startAt, DateTime(2026, 11, 3, 17));
    });

    test('toDraft → toActivity ได้ค่าเดิม (ฟอร์มแก้ไขไม่ทำข้อมูลหาย)', () {
      final a = re4().toActivity(id: 5);
      final again = a.toDraft().toActivity(id: 5);
      expect(again.dates.keys, a.dates.keys);
      expect(again.presetId, 1);
      expect(timeFor(again, DateTime(2026, 11, 6)), (19 * 60, 180));
    });

    test('ลบ Preset: งานเดิมยังอยู่', () async {
      final repo = MemoryCalendarRepository();
      final pid = (await repo.presets()).single.id;
      final id = await repo.addActivity(NewActivity(
        name: 'Minecraft',
        categoryId: 3,
        importance: 3,
        timed: true,
        day: wed,
        startMinute: 20 * 60,
        durationMin: 120,
        presetId: pid,
      ));
      await repo.deletePreset(pid);
      expect(await repo.presets(), isEmpty);
      final a = await repo.activity(id);
      expect(a.name, 'Minecraft');
      expect(a.presetId, isNull);
    });
  });

  group('คาบเรียน + เวลาเลิกจริง', () {
    test('ผูกวิชา · บันทึกเวลาเลิกจริง · สถิติเฉลี่ย', () async {
      final repo = MemoryCalendarRepository();
      final id = await repo.addActivity(NewActivity(
        name: 'เรียน · Programming',
        categoryId: 1,
        importance: 3,
        timed: true,
        day: mon,
        startMinute: 9 * 60,
        durationMin: 120, // 09:00–11:00
        repeat: RepeatKind.daily,
        subjectId: 7,
      ));
      expect((await repo.activitiesForSubject(7)).single.id, id);
      expect(await repo.activitiesForSubject(8), isEmpty);

      final m = (await repo.occurrencesOn(mon)).single;
      final t = (await repo.occurrencesOn(tue)).single;
      final w = (await repo.occurrencesOn(wed)).single;
      expect(m.subjectId, 7);
      for (final o in [m, t, w]) {
        await repo.setDone(o.id, true);
      }
      await repo.setActualTimes(m.id, end: DateTime(2026, 11, 2, 11, 30)); // ช้า 30
      await repo.setActualTimes(t.id, end: DateTime(2026, 11, 3, 10, 45)); // ก่อน 15
      // พุธไม่ได้บันทึก → ไม่นับ

      final s = classTimeStats(await repo.occurrencesForSubject(7));
      expect(s.count, 2);
      expect(s.late, 1);
      expect(s.early, 1);
      expect(s.averageDiff, 7.5);
      expect(s.maxLate, 30);
      expect(s.maxEarly, 15);
      expect(diffText(s.averageDiff), 'ช้า 8 นาที');
      expect(diffText(3), 'ตรงเวลา');
    });

    test('แก้ไขงานแล้วยังผูกวิชาเดิม', () async {
      final repo = MemoryCalendarRepository();
      final id = await repo.addActivity(NewActivity(
        name: 'เรียน', categoryId: 1, importance: 3, timed: true, day: mon,
        startMinute: 9 * 60, durationMin: 60, subjectId: 3,
      ));
      final draft = (await repo.activity(id)).toDraft();
      expect(draft.subjectId, 3);
    });
  });

  test('clashingIds: งานที่เวลาทับกันถูกจับทั้งคู่ · งานที่ยกเลิกไม่นับ', () async {
    final repo = MemoryCalendarRepository();
    NewActivity at(String n, int h) => NewActivity(
        name: n, categoryId: 1, importance: 3, timed: true, day: mon,
        startMinute: h * 60, durationMin: 120);
    await repo.addActivity(at('A', 9));
    await repo.addActivity(at('B', 10));
    await repo.addActivity(at('C', 13));
    final items = await repo.occurrencesOn(mon);
    final ids = clashingIds(items);
    expect(items.where((o) => ids.contains(o.id)).map((o) => o.title), unorderedEquals(['A', 'B']));

    await repo.cancel(items.firstWhere((o) => o.title == 'B').id, 'ไม่ไป');
    expect(clashingIds(await repo.occurrencesOn(mon)), isEmpty);
  });

  test('findClashes: งานซ้ำที่ชนทุกสัปดาห์รวมเป็นคู่เดียว นับจำนวนครั้ง', () async {
    final repo = MemoryCalendarRepository();
    NewActivity weekly(String n, int h) => NewActivity(
        name: n, categoryId: 1, importance: 3, timed: true, day: mon,
        startMinute: h * 60, durationMin: 120, repeat: RepeatKind.weekly, weekdays: {1});
    await repo.addActivity(weekly('อังกฤษ', 9));
    await repo.addActivity(weekly('ศึกษาทั่วไป', 10));
    final byDay = {
      for (var i = 0; i < 14; i++)
        DateTime(2026, 11, 2 + i): await repo.occurrencesOn(DateTime(2026, 11, 2 + i)),
    };
    final clashes = findClashes(byDay);
    expect(clashes, hasLength(1));
    expect(clashes.single.days, [DateTime(2026, 11, 2), DateTime(2026, 11, 9)]);
  });

  group('ช่วงว่าง (free slots)', () {
    test('freeGaps: ตัดงานออกจากช่วงตื่น–นอน', () {
      final gaps = freeGaps(const [
        Busy(9 * 60, 12 * 60, 'A'),
        Busy(11 * 60, 13 * 60, 'B'), // ทับ A → รวมเป็นช่วงเดียว
        Busy(20 * 60, 24 * 60, 'RE4'),
      ], 7 * 60, 24 * 60);
      expect([for (final g in gaps) (g.start, g.end)], [(420, 540), (780, 1200)]);
    });

    test('suggestSlots: เวลาเดิมมาก่อน · ช่องสั้นไปไม่นับ', () {
      final s = suggestSlots({
        1: [const Gap(13 * 60, 15 * 60)], // จ สั้นไป (2 ชม.)
        4: [const Gap(7 * 60, 13 * 60)], // พฤ ใส่ 09–13 ได้ = เวลาเดิม
        5: [const Gap(11 * 60, 24 * 60)], // ศ ได้เร็วสุด 11:00
      }, 240, 9 * 60, originalRow: 1);
      expect(s.first.row, 4);
      expect(s.first.start, 9 * 60);
      expect(s[1].row, 5);
      expect(s[1].start, 11 * 60);
      expect(s.any((x) => x.row == 1), isFalse);
    });

    test('clashesAt: ชนขอบพอดีไม่นับ', () {
      const busy = [Busy(9 * 60, 11 * 60, 'A')];
      expect(clashesAt(busy, 11 * 60, 60), isEmpty);
      expect(clashesAt(busy, 10 * 60, 60), hasLength(1));
    });
  });

  group('v10: เทอม · วันหยุด · คาบซ้ำ · บันทึกติว', () {
    NewActivity cls({String name = 'เรียน · อังกฤษ', int start = 9 * 60}) => NewActivity(
          name: name,
          categoryId: 1,
          importance: 3,
          timed: true,
          day: mon,
          startMinute: start,
          durationMin: 90,
          repeat: RepeatKind.weekly,
          weekdays: {1},
          subjectId: 7,
          kind: ActivityKind.classSession,
        );

    test('หมวดเรียนหาจากรหัส study ไม่ใช่ชื่อ', () async {
      final repo = MemoryCalendarRepository();
      final id = studyCategoryId(await repo.categories());
      expect((await repo.categories()).firstWhere((c) => c.id == id).name, 'เรียน');
    });

    test('ลบคาบซ้ำ: เก็บตัวแรก · คาบเวลาต่างกันไม่โดนลบ · งานทั่วไปไม่แตะ', () async {
      final repo = MemoryCalendarRepository();
      final first = await repo.addActivity(cls());
      await repo.addActivity(cls()); // ซ้ำ
      await repo.addActivity(cls()); // ซ้ำ
      await repo.addActivity(cls(start: 13 * 60)); // คนละเวลา
      await repo.addActivity(gym());
      await repo.addActivity(gym()); // งานทั่วไปชื่อซ้ำได้
      expect(await repo.removeDuplicateActivities(), 2);
      expect(await repo.removeDuplicateActivities(), 0);
      final left = await repo.activitiesForSubject(7);
      expect(left.map((a) => a.id), contains(first));
      expect(left, hasLength(2));
    });

    test('วันหยุด: วันเดิม = เปลี่ยนชื่อ · ลบได้', () async {
      final repo = MemoryCalendarRepository();
      await repo.setHoliday(DateTime(2026, 12, 5, 10), 'วันพ่อ');
      await repo.setHoliday(DateTime(2026, 12, 5), 'วันพ่อแห่งชาติ');
      await repo.setHoliday(DateTime(2026, 12, 10), 'วันรัฐธรรมนูญ');
      final h = await repo.holidays();
      expect(h.map((x) => x.name), ['วันพ่อแห่งชาติ', 'วันรัฐธรรมนูญ']);
      await repo.removeHoliday(DateTime(2026, 12, 5));
      expect(await repo.holidays(), hasLength(1));
    });

    test('เทอม: ปี+เทอมเดิมเขียนทับ · เรียงปี → เทอม · contains รวมวันสุดท้าย', () async {
      final repo = MemoryCalendarRepository();
      await repo.saveTerm(1, 2, DateTime(2027, 3, 1), DateTime(2027, 6, 30));
      await repo.saveTerm(1, 1, DateTime(2026, 11, 9), DateTime(2027, 2, 5));
      await repo.saveTerm(1, 1, DateTime(2026, 11, 9), DateTime(2027, 2, 6));
      final t = await repo.terms();
      expect(t.map((x) => x.termNo), [1, 2]);
      expect(t.first.contains(DateTime(2027, 2, 6, 23)), isTrue);
      expect(t.first.contains(DateTime(2027, 2, 7)), isFalse);
      expect(t.last.label, 'ปี 1 · เทอม 2');
    });

    test('บันทึกติว: นับรอบต่อบท (รอบเดียวกันบันทึกซ้ำไม่นับเพิ่ม) · สี/ความยาวรอบเก็บในวิชา',
        () async {
      final study = MemoryStudyRepository();
      final s = await study.addSubject('คณิต', importance: 3);
      final ch = await study.addChapter(s, 'บท 1');
      await study.logTutor(500, ch, ChapterStatus.learning);
      await study.logTutor(500, ch, ChapterStatus.learned);
      await study.logTutor(501, ch, ChapterStatus.learned);
      expect(await study.tutorCount(ch), 2);

      await study.setSubjectColor(s, 4);
      await study.setTutorMinutes(s, 45);
      final subj = (await study.subjects()).firstWhere((x) => x.id == s);
      expect(subj.colorIndex, 4);
      expect(subj.tutorMinutes, 45);
    });
  });
}
