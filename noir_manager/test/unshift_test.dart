import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';

/// รอบ 18: กด "เลื่อนไปรอบถัดไป" พลาด → ยกเลิกได้ · วันสุดท้ายหดกลับ · ครั้งที่งอกมาหายไป
Future<void> unshiftRules(CalendarRepository repo) async {
  final start = DateTime(2026, 11, 16); // จันทร์
  final id = await repo.addActivity(NewActivity(
    name: 'ไลฟ์ · Noir Lev',
    categoryId: null,
    importance: 3,
    timed: true,
    day: start,
    startMinute: 20 * 60,
    durationMin: 150,
    repeat: RepeatKind.weekly,
    weekdays: const {1, 3, 5},
    endDate: DateTime(2026, 11, 27), // ศุกร์
  ));
  final fri = DateTime(2026, 11, 20);
  final occ = (await repo.occurrencesOn(fri)).single;
  final newEnd = await repo.shiftToNextRound(occ.id, 'กดเลื่อนเอง');
  expect(newEnd, DateTime(2026, 11, 30)); // ศุกร์ → จันทร์ถัดไป
  expect((await repo.occurrencesOn(DateTime(2026, 11, 30))).length, 1); // ครั้งที่งอกมา
  expect((await repo.occurrencesOn(fri)).single.status, OccurrenceStatus.shifted);

  await repo.unshiftRound(occ.id);
  final back = (await repo.occurrencesOn(fri)).single;
  expect(back.status, OccurrenceStatus.planned);
  expect(back.reason, isNull);
  expect((await repo.activity(id)).endDate, DateTime(2026, 11, 27));
  expect(await repo.occurrencesOn(DateTime(2026, 11, 30)), isEmpty);
  // กดซ้ำ = ไม่ทำอะไร
  await repo.unshiftRound(occ.id);
  expect((await repo.activity(id)).endDate, DateTime(2026, 11, 27));
}

void main() {
  test('RAM: ยกเลิกการเลื่อนไปรอบถัดไป', () => unshiftRules(MemoryCalendarRepository()));

  test('SQLite: ยกเลิกการเลื่อนไปรอบถัดไป', () async {
    sqfliteFfiInit();
    final dir = await Directory.systemTemp.createTemp('noir_unshift_');
    final db = await databaseFactoryFfi.openDatabase('${dir.path}/n.db',
        options: OpenDatabaseOptions(
          version: appSchemaVersion,
          onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
          onCreate: (db, _) => createAllTables(db),
        ));
    await unshiftRules(SqliteCalendarRepository(db));
    await db.close();
  });

  test('วันก่อนหน้าตามกฎการทำซ้ำ', () {
    final a = Activity(
      id: 1,
      name: 'x',
      categoryId: null,
      importance: 2,
      timed: false,
      startMinute: null,
      durationMin: null,
      repeat: RepeatKind.weekly,
      weekdays: const {1, 3, 5},
      startDate: DateTime(2026, 11, 1),
    );
    expect(prevSlotBefore(a, DateTime(2026, 11, 30)), DateTime(2026, 11, 27));
    expect(prevSlotBefore(a, DateTime(2026, 11, 25)), DateTime(2026, 11, 23));
  });
}
