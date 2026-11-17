// ความเร็วเปลี่ยนเดือนในปฏิทิน (นัวร์: เปลี่ยนเดือนแล้วหน่วง ~1 วิ หลังใส่แผน 6 เดือน)
// วัดทุกอย่างที่หน้าปฏิทินโหลดตอนเปลี่ยนเดือน บน SQLite จริง (ตารางครบ v ล่าสุด) + แผนของนัวร์
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/noir_plan.dart';

/// สิ่งที่ CalendarPage.reload ทำตอนมุมมองเดือน
Future<int> monthLoad(CalendarRepository repo, DateTime month) async {
  final sw = Stopwatch()..start();
  final vis = monthGridDays(month);
  await repo.occurrencesBetween(vis.first, vis.last);
  await repo.lifeBase();
  await repo.categories();
  await repo.holidays();
  await repo.daySticker(vis.first, vis.last);
  return sw.elapsedMilliseconds;
}

void main() {
  test('เปลี่ยนเดือน (แผน 6 เดือน): ครั้งแรก / กลับมาดูซ้ำ', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createAllTables(db);
    final repo = SqliteCalendarRepository(db);
    final today = DateTime(2026, 11, 17);
    await applyNoirPlan(repo, today);
    // เดือนที่ผ่านมา: ติ๊กทำแล้ว/เลื่อนบ้าง เหมือนใช้งานจริง
    final past = await repo.occurrencesBetween(DateTime(2026, 11, 1), today);
    var i = 0;
    for (final l in past.values) {
      for (final o in l) {
        if (i++ % 3 == 0) await repo.setDone(o.id, true);
      }
    }

    final cold = <int>[], warm = <int>[];
    for (var m = 0; m < 6; m++) {
      cold.add(await monthLoad(repo, DateTime(2026, 11 + m, 1)));
    }
    for (var m = 0; m < 6; m++) {
      warm.add(await monthLoad(repo, DateTime(2026, 11 + m, 1)));
    }
    // ignore: avoid_print
    print('PERF month cold=$cold warm=$warm');
    expect(warm.reduce((a, b) => a > b ? a : b), lessThan(3000));
    await db.close();
  });
}
