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
    // ก่อนแก้ (17 พ.ย.): ~950 ms/เดือน ทั้งครั้งแรกและดูซ้ำ
    expect(warm.reduce((a, b) => a > b ? a : b), lessThan(250));

    // แคชต้องไม่ค้าง: เพิ่มงานใหม่ → เดือนเดิมเห็นทันที
    final cat = (await repo.categories()).first.id;
    await repo.addActivity(NewActivity(
        name: 'งานใหม่ทุกวันอังคาร', categoryId: cat, importance: 2, timed: false, day: DateTime(2026, 12, 1),
        repeat: RepeatKind.weekly, weekdays: {2}));
    final dec = await repo.occurrencesBetween(DateTime(2026, 12, 1), DateTime(2026, 12, 31));
    expect(dec.values.expand((l) => l).where((o) => o.title == 'งานใหม่ทุกวันอังคาร').length, 5);
    await db.close();
  });

  test('เลขครั้ง: คิดรอบเดียว (sessionIndex) = คิดทีละครั้ง (sessionCount) ทุกวัน', () {
    for (final a in [
      Activity(id: 1, name: 'w', categoryId: 1, importance: 2, timed: true, startMinute: 600, durationMin: 60,
          startDate: DateTime(2026, 9, 1), repeat: RepeatKind.weekly, weekdays: const {1, 3, 5}, endDate: DateTime(2027, 2, 28)),
      Activity(id: 2, name: 'd', categoryId: 1, importance: 2, timed: false, startMinute: null, durationMin: null,
          startDate: DateTime(2026, 10, 3), repeat: RepeatKind.daily, weekdays: const {}),
    ]) {
      final skip = {DateTime(2026, 11, 4), DateTime(2026, 10, 10)};
      final idx = sessionIndex(a, skipped: skip, upTo: DateTime(2027, 1, 31));
      for (var d = DateTime(2026, 8, 25); d.isBefore(DateTime(2027, 1, 31)); d = DateTime(d.year, d.month, d.day + 1)) {
        final want = sessionCount(a, d, skipped: skip);
        final n = idx.n[d];
        final got = n == null ? null : SessionCount(n, idx.total);
        expect(got, want, reason: '${a.name} ${dayKey(d)}');
      }
    }
  });
}
