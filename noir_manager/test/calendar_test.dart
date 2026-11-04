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
}
