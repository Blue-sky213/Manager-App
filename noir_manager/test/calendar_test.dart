import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';

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

    test('ยังไม่รู้วัน → Reminder Inbox → เลือกวันแทน', () async {
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
}
