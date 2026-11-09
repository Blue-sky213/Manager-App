import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/holiday_flow.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';

/// วันหยุด → กล่องเลื่อน 4 ทาง (must-have #6 ส่วนที่ 2)
void main() {
  sqfliteFfiInit();

  final thu = DateTime(2026, 11, 5); // พฤหัส
  DateTime week(int n) => DateTime(2026, 11, 5 + 7 * (n - 1));
  final lastThu = week(7); // 17 ธ.ค.

  // คาบทุกพฤหัส 5 พ.ย. – 17 ธ.ค. = 7 ครั้ง
  NewActivity lecture({DateTime? endDate, bool open = false}) => NewActivity(
        name: 'DataCOM',
        categoryId: 1,
        importance: 3,
        timed: true,
        day: thu,
        startMinute: 9 * 60,
        durationMin: 60,
        repeat: RepeatKind.weekly,
        weekdays: const {4},
        endDate: open ? null : (endDate ?? lastThu),
        kind: ActivityKind.classSession,
      );

  group('ฟังก์ชันล้วน', () {
    test('รอบถัดไปหลังวันสุดท้าย: ทุกพฤหัส → พฤหัสถัดไป · ทุกวัน → พรุ่งนี้', () {
      final a = lecture().toActivity(id: 1);
      expect(nextSlotAfter(a, lastThu), DateTime(2026, 12, 24));
      final daily = NewActivity(
        name: 'วิ่ง',
        categoryId: 2,
        importance: 2,
        timed: false,
        day: thu,
        repeat: RepeatKind.daily,
        weekdays: const {},
      ).toActivity(id: 2);
      expect(nextSlotAfter(daily, DateTime(2026, 12, 31)), DateTime(2027, 1, 1));
    });

    test('งานครั้งเดียว / เลือกวันเอง → เลื่อนไปรอบถัดไปไม่ได้', () {
      final once = NewActivity(
        name: 'สอบ',
        categoryId: 1,
        importance: 3,
        timed: false,
        day: thu,
        repeat: RepeatKind.none,
        weekdays: const {},
      ).toActivity(id: 3);
      expect(canShiftToNextRound(once), isFalse);
      expect(nextSlotAfter(once, thu), isNull);
    });

    test('ค่าเริ่มต้น: เรียน → รอนัด · อื่น ๆ → ยกเลิก · ที่จำไว้ชนะ', () {
      expect(defaultHolidayChoice(true), HolidayChoice.inbox);
      expect(defaultHolidayChoice(false), HolidayChoice.cancel);
      expect(defaultHolidayChoice(true, remembered: 'shift'), HolidayChoice.shift);
      expect(defaultHolidayChoice(false, remembered: 'อะไรก็ไม่รู้'), HolidayChoice.cancel);
    });

    test('เลขข้ามวันที่เลื่อนไปรอบถัดไป · วันที่เลื่อนเองไม่มีเลข', () {
      final a = lecture(endDate: DateTime(2026, 12, 24)).toActivity(id: 1);
      final skip = {week(3)};
      expect(sessionCount(a, week(3), skipped: skip), isNull);
      expect(sessionCount(a, week(4), skipped: skip), const SessionCount(3, 7));
      expect(sessionCount(a, DateTime(2026, 12, 24), skipped: skip), const SessionCount(7, 7));
    });
  });

  // กฎเดียวกันต้องผ่านทั้งตัว RAM และ SQLite จริง
  Future<void> shiftRules(CalendarRepository repo) async {
    final id = await repo.addActivity(lecture());

    final w3 = (await repo.occurrencesOn(week(3))).single;
    expect(w3.session, const SessionCount(3, 7));

    final newEnd = await repo.shiftToNextRound(w3.id, 'วันหยุด: ทดสอบ');
    expect(newEnd, DateTime(2026, 12, 24));
    expect((await repo.activity(id)).endDate, DateTime(2026, 12, 24));

    final after = (await repo.occurrencesOn(week(3))).single;
    expect(after.status, OccurrenceStatus.shifted);
    expect(after.session, isNull);
    expect(after.reason, 'วันหยุด: ทดสอบ');

    // เนื้อหาครั้งที่ 3 ไหลไปสัปดาห์หน้า · N เท่าเดิม · มีครั้งที่ 7 ใหม่ 24 ธ.ค.
    expect((await repo.occurrencesOn(week(4))).single.session, const SessionCount(3, 7));
    expect((await repo.occurrencesOn(lastThu)).single.session, const SessionCount(6, 7));
    expect((await repo.occurrencesOn(DateTime(2026, 12, 24))).single.session,
        const SessionCount(7, 7));

    // งานไม่มีวันสิ้นสุด → เลื่อนได้ ไม่ต้องขยาย
    final open = await repo.addActivity(lecture(open: true));
    final o1 = (await repo.occurrencesOn(week(2))).firstWhere((o) => o.activityId == open);
    expect(await repo.shiftToNextRound(o1.id, 'วันหยุด'), isNull);
    expect((await repo.activity(open)).endDate, isNull);

    // จำตัวเลือกวันหยุด
    expect(await repo.getSetting(holidayChoiceKey('cat_1')), isNull);
    await repo.setSetting(holidayChoiceKey('cat_1'), HolidayChoice.shift.name);
    expect(await repo.getSetting(holidayChoiceKey('cat_1')), 'shift');

    // จัดกลุ่มงานที่ตรงวันหยุด: คาบเรียน = หมวดเรียน · ถือเป็นงานเรียน
    final groups = await collectHolidayItems(repo, week(5), week(5));
    final items = groups.values.expand((l) => l).toList();
    expect(items, hasLength(2)); // คาบมีวันสิ้นสุด + คาบไม่มีวันสิ้นสุด
    expect(items.every((i) => i.isStudy && i.canShift), isTrue);
  }

  test('ตัว RAM: เลื่อนไปรอบถัดไป · ขยายวันสุดท้าย · เลขไม่ขาด', () async {
    await shiftRules(MemoryCalendarRepository());
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
    await shiftRules(SqliteCalendarRepository(db));
    await db.close();
  });
}
