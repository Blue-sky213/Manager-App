import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

/// โหลดทั้งช่วง = ผลเดียวกับโหลดทีละวัน (ทั้งงานครั้งเดียว · ทุกวัน · รายสัปดาห์ · เลือกวันเอง · ย้ายวัน)
Future<void> betweenMatchesPerDay(CalendarRepository repo) async {
  final cat = (await repo.categories()).first.id;
  final base = DateTime(2026, 11, 2); // จันทร์
  NewActivity act(String name, {RepeatKind repeat = RepeatKind.none, Set<int> weekdays = const {}, List<ScheduledDate> dates = const []}) =>
      NewActivity(
        name: name,
        categoryId: cat,
        importance: 2,
        timed: true,
        day: base,
        startMinute: 9 * 60,
        durationMin: 60,
        repeat: repeat,
        weekdays: weekdays,
        dates: dates,
      );
  await repo.addActivity(act('ครั้งเดียว'));
  await repo.addActivity(act('ทุกวัน', repeat: RepeatKind.daily));
  await repo.addActivity(act('จ พ ศ', repeat: RepeatKind.weekly, weekdays: const {1, 3, 5}));
  await repo.addActivity(act('เลือกวัน', repeat: RepeatKind.dates, dates: [
    ScheduledDate(DateTime(2026, 11, 4), startMinute: 13 * 60, durationMin: 30),
    ScheduledDate(DateTime(2026, 11, 20)),
  ]));

  final from = DateTime(2026, 10, 30), to = DateTime(2026, 11, 22);
  final range = await repo.occurrencesBetween(from, to);
  expect(range.length, 24); // ทุกวันมี key
  for (var d = from; !d.isAfter(to); d = DateTime(d.year, d.month, d.day + 1)) {
    final one = await repo.occurrencesOn(d);
    expect(range[d]!.map((o) => (o.id, o.title, o.startAt)).toList(), one.map((o) => (o.id, o.title, o.startAt)).toList(),
        reason: dayKey(d));
  }
  expect(range[DateTime(2026, 11, 4)]!.map((o) => o.title), containsAll(['ทุกวัน', 'จ พ ศ', 'เลือกวัน']));
  expect(range[DateTime(2026, 11, 1)], isEmpty); // ก่อนเริ่ม
}

/// นับว่าหน้าสถิติ (ช่วง 372 วัน) โหลดกี่ครั้ง
class _CountingRepo extends MemoryCalendarRepository {
  int yearLoads = 0;

  @override
  Future<Map<DateTime, List<Occurrence>>> occurrencesBetween(DateTime from, DateTime to) {
    if (to.difference(from).inDays > 300) yearLoads++;
    return super.occurrencesBetween(from, to);
  }
}

void main() {
  test('RAM: โหลดทั้งช่วง = โหลดทีละวัน', () => betweenMatchesPerDay(MemoryCalendarRepository()));

  test('SQLite: โหลดทั้งช่วง = โหลดทีละวัน', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createStudySchema(db);
    await createSettingSchema(db);
    await createCalendarSchema(db);
    await createCalendarV5(db);
    await createCalendarV7(db);
    await createStudyPlanV8(db);
    await createTutorV9(db);
    await createTermV10(db);
    await createClassInfoV11(db);
    await createSubjectLinkV12(db);
    await createStickerV16(db);
    await createRound7V17(db);
    await betweenMatchesPerDay(SqliteCalendarRepository(db));
    await db.close();
  });

  testWidgets('หน้าสถิติที่ซ่อนอยู่ ไม่โหลดใหม่ทุกครั้งที่ข้อมูลเปลี่ยน · เปิดหน้าแล้วโหลดครั้งเดียว', (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = _CountingRepo();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    final first = cal.yearLoads;
    expect(first, 1); // โหลดตอนเปิดแอป

    // เปลี่ยนข้อมูล 3 ครั้งระหว่างอยู่หน้าวันนี้
    for (var i = 0; i < 3; i++) {
      cal.refresh();
      await tester.pumpAndSettle();
    }
    expect(cal.yearLoads, first);

    await tester.tap(find.text('สถิติ').first);
    await tester.pumpAndSettle();
    expect(cal.yearLoads, first + 1); // ค้างไว้ → โหลดครั้งเดียวตอนเปิด
    cal.refresh();
    await tester.pumpAndSettle();
    expect(cal.yearLoads, first + 2); // เปิดอยู่ = โหลดทันทีเหมือนเดิม
    expect(tester.takeException(), isNull);
  });
}
