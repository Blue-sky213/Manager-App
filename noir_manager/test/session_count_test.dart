import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';

/// "ครั้งที่ n/N" (must-have #6 ส่วนแรก)
void main() {
  sqfliteFfiInit();

  final mon = DateTime(2026, 11, 2); // จันทร์
  final lastMon = DateTime(2026, 12, 14); // จันทร์ที่ 7

  // คาบเรียนทุกจันทร์ 2 พ.ย. – 14 ธ.ค. = 7 ครั้ง
  NewActivity lecture({DateTime? endDate}) => NewActivity(
        name: 'DataCOM',
        categoryId: 1,
        importance: 3,
        timed: true,
        day: mon,
        startMinute: 9 * 60,
        durationMin: 180,
        repeat: RepeatKind.weekly,
        weekdays: const {1},
        endDate: endDate ?? lastMon,
        kind: ActivityKind.classSession,
      );

  DateTime week(int n) => DateTime(2026, 11, 2 + 7 * (n - 1));

  group('นับเลข (ฟังก์ชันล้วน)', () {
    test('ทุกจันทร์ 7 ครั้ง → ครั้งที่ 3 คือ 16 พ.ย.', () {
      final a = lecture().toActivity(id: 1);
      expect(sessionCount(a, week(1)), const SessionCount(1, 7));
      expect(sessionCount(a, week(3))!.label, 'ครั้งที่ 3/7');
      expect(sessionCount(a, lastMon), const SessionCount(7, 7));
    });

    test('ไม่มี "ถึงวันที่" → บอกแค่ ครั้งที่ n', () {
      final a = NewActivity(
        name: 'วิ่ง',
        categoryId: 2,
        importance: 2,
        timed: false,
        day: mon,
        repeat: RepeatKind.daily,
        weekdays: const {},
      ).toActivity(id: 1);
      final s = sessionCount(a, DateTime(2026, 11, 11))!;
      expect(s.n, 10);
      expect(s.total, isNull);
      expect(s.label, 'ครั้งที่ 10');
    });

    test('เลือกวันเอง 3 วัน → วันกลางคือ 2/3', () {
      final a = NewActivity(
        name: 'ติวสอบ',
        categoryId: 1,
        importance: 2,
        timed: false,
        day: mon,
        repeat: RepeatKind.dates,
        weekdays: const {},
        dates: [
          ScheduledDate(DateTime(2026, 11, 20)),
          ScheduledDate(DateTime(2026, 11, 5)),
          ScheduledDate(DateTime(2026, 11, 12)),
        ],
      ).toActivity(id: 1);
      expect(sessionCount(a, DateTime(2026, 11, 12)), const SessionCount(2, 3));
    });

    test('งานครั้งเดียว / วันที่ไม่ใช่วันของงาน → ไม่มีเลข', () {
      final a = lecture().toActivity(id: 1);
      expect(sessionCount(a, DateTime(2026, 11, 3)), isNull); // อังคาร
      final once = NewActivity(
        name: 'สอบ',
        categoryId: 1,
        importance: 3,
        timed: false,
        day: mon,
        repeat: RepeatKind.none,
        weekdays: const {},
      ).toActivity(id: 2);
      expect(sessionCount(once, mon), isNull);
    });
  });

  // กฎเดียวกันต้องผ่านทั้งตัว RAM และ SQLite จริง (SQL ไล่ moved_from แบบ recursive)
  Future<void> moveRules(CalendarRepository repo) async {
    await repo.addActivity(lecture());

    final w2 = (await repo.occurrencesOn(week(2))).single;
    expect(w2.session!.label, 'ครั้งที่ 2/7');

    // เลื่อน 2 ทอด: จันทร์ → อังคาร → พุธ · เนื้อหาครั้งที่ 2 ยังเป็นครั้งที่ 2
    final id1 = await repo.moveOccurrence(w2.id, DateTime(2026, 11, 10));
    await repo.moveOccurrence(id1, DateTime(2026, 11, 11));
    final moved = (await repo.occurrencesOn(DateTime(2026, 11, 11))).single;
    expect(moved.session, const SessionCount(2, 7));

    // ยกเลิกครั้งที่ 3 → ยังกินเลข · ครั้งถัดไปคือ 4
    final w3 = (await repo.occurrencesOn(week(3))).single;
    await repo.cancel(w3.id, 'อาจารย์ติดธุระ');
    final w3After = (await repo.occurrencesOn(week(3))).single;
    expect(w3After.session, const SessionCount(3, 7));
    expect((await repo.occurrencesOn(week(4))).single.session, const SessionCount(4, 7));

    // ส่งเข้ารอนัดก็ยังรู้ว่าเป็นครั้งไหน
    final w5 = (await repo.occurrencesOn(week(5))).single;
    await repo.sendToInbox(w5.id);
    expect((await repo.inbox()).single.session, const SessionCount(5, 7));
  }

  test('ตัว RAM: เลื่อน 2 ทอดเลขเดิม · ยกเลิกยังกินเลข · รอนัดรู้เลข', () async {
    await moveRules(MemoryCalendarRepository());
  });

  test('ตัว SQLite จริง: กฎเดียวกัน', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(
            onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createStudySchema(db);
    await createSettingSchema(db);
    await createCalendarSchema(db);
    await createCalendarV5(db);
    await createCalendarV7(db);
    await createStudyPlanV8(db);
    await createTutorV9(db);
    await createTermV10(db);
    await createClassInfoV11(db); // ให้ตรงกับ schema ล่าสุดของแอป
    await createSubjectLinkV12(db);
    await moveRules(SqliteCalendarRepository(db));
    await db.close();
  });
}
