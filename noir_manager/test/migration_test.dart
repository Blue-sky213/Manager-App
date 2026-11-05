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
    await createTutorV9(db);
    await createTutorV9(db);

    final occ = await db.rawQuery('PRAGMA table_info(occurrence)');
    final names = occ.map((c) => c['name']).toSet();
    expect(names, containsAll(['actual_start', 'actual_end']));
    final subj = (await db.rawQuery('PRAGMA table_info(subject)')).map((c) => c['name']);
    expect(subj, containsAll(['code', 'credits', 'plan_year', 'plan_term']));
    final ch = (await db.rawQuery('PRAGMA table_info(chapter)')).map((c) => c['name']);
    expect(ch, containsAll(['kind', 'status']));
    await db.close();
  });

  test('v10: ย้ายสี/ความยาวรอบติวจาก setting → subject · หมวดเรียนได้รหัส study · รันซ้ำได้',
      () async {
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

    final a = await db.insert('subject', {'name': 'คณิต', 'importance': 3, 'sessions_per_week': 3});
    final b = await db.insert('subject', {'name': 'อังกฤษ', 'importance': 1, 'sessions_per_week': 2});
    await db.insert('setting', {'key': 'tutor_min_$a', 'value': '45'});
    await db.insert('setting', {'key': 'subject_color_$a', 'value': '5'});
    await db.insert('setting', {'key': 'grading_mode', 'value': 'ez'});

    await createTermV10(db);
    await createTermV10(db); // รันซ้ำก็ไม่พัง

    final rows = {
      for (final r in await db.query('subject')) r['id']: r,
    };
    expect(rows[a]!['tutor_minutes'], 45);
    expect(rows[a]!['color'], '5');
    expect(rows[b]!['tutor_minutes'], 90); // ไม่เคยตั้ง = ค่าเริ่มต้น
    expect(rows[b]!['color'], isNull);

    final keys = (await db.query('setting')).map((r) => r['key']).toList();
    expect(keys, ['grading_mode']); // ค่าเก่าถูกล้าง ค่าอื่นอยู่ครบ

    final study = await db.query('category', where: "system_key = 'study'");
    expect(study.single['name'], 'เรียน');

    final tables = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table'"))
        .map((r) => r['name']);
    expect(tables, containsAll(['term', 'holiday', 'tutor_log']));

    // เทอม: ปี+เทอมเดิมเขียนทับ ไม่ซ้ำ
    final repo = SqliteCalendarRepository(db);
    await repo.saveTerm(1, 1, DateTime(2026, 6, 15), DateTime(2026, 10, 16));
    await repo.saveTerm(1, 1, DateTime(2026, 6, 22), DateTime(2026, 10, 23));
    final terms = await repo.terms();
    expect(terms.length, 1);
    expect(terms.single.start, DateTime(2026, 6, 22));
    expect(terms.single.contains(DateTime(2026, 8, 1, 13)), isTrue);
    await db.close();
  });
}
