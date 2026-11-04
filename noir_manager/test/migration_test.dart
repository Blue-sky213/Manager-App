import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/sqlite_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';

/// เทสการอัปเกรดฐานข้อมูลด้วย SQLite จริง (ในหน่วยความจำ)
void main() {
  sqfliteFfiInit();

  test('v7: ตาราง activity มี subject_id อยู่แล้ว → อัปเกรดไม่พัง และรันซ้ำได้', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createStudySchema(db);
    await createSettingSchema(db);
    await createCalendarSchema(db); // v4: มี subject_id ใน activity
    await createCalendarV5(db);

    await createCalendarV7(db);
    await createCalendarV7(db); // รันซ้ำก็ไม่พัง
    await createStudyPlanV8(db);
    await createStudyPlanV8(db);

    final occ = await db.rawQuery('PRAGMA table_info(occurrence)');
    final names = occ.map((c) => c['name']).toSet();
    expect(names, containsAll(['actual_start', 'actual_end']));
    final subj = (await db.rawQuery('PRAGMA table_info(subject)')).map((c) => c['name']);
    expect(subj, containsAll(['code', 'credits', 'plan_year', 'plan_term']));
    await db.close();
  });
}
