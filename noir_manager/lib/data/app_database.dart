import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../calendar/sqlite_calendar_repository.dart';
import 'seed_data.dart';
import 'study_repository.dart';

/// เวอร์ชันโครงตาราง: ถ้าวันหลังเพิ่มตาราง/คอลัมน์ ให้เพิ่มเลขนี้ + เขียน onUpgrade
const int _schemaVersion = 8; // v2 setting · v3 cleared_at · v4 ปฏิทิน · v5 Preset · v6 วิชาง่าย 2 รอบ · v7 คาบผูกวิชา + เวลาจริง · v8 แผนการเรียน

/// เปิด (หรือสร้างครั้งแรก) ไฟล์ฐานข้อมูล noir_manager.db
Future<Database> openAppDatabase() async {
  // Windows/Linux ไม่มี SQLite ในตัวแบบ Android → สลับไปใช้ตัว FFI
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // Windows: C:\Users\<ชื่อ>\AppData\Roaming\<บริษัท>\noir_manager\
  final dir = await getApplicationSupportDirectory();
  final path = p.join(dir.path, 'noir_manager.db');

  return openDatabase(
    path,
    version: _schemaVersion,
    // SQLite ปิดการเช็ก Foreign Key ไว้เป็นค่าเริ่มต้น ต้องเปิดเองทุกครั้งที่ต่อ
    onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
    // เครื่องใหม่ (ยังไม่มีไฟล์): สร้างทุกตารางในครั้งเดียว
    onCreate: (db, version) async {
      await createStudySchema(db);
      await createSettingSchema(db);
      await createCalendarSchema(db);
      await createCalendarV5(db);
      await createCalendarV7(db);
      await createStudyPlanV8(db);
      await seedStudyData(db);
    },
    // เครื่องที่มีไฟล์ v1 อยู่แล้ว (เครื่องนัวร์): เพิ่มเฉพาะส่วนที่ขาด ข้อมูลเดิมไม่หาย
    onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await createSettingSchema(db);
      if (oldVersion < 3) {
        await db.execute('ALTER TABLE subtopic ADD COLUMN cleared_at TEXT');
      }
      if (oldVersion < 4) await createCalendarSchema(db);
      if (oldVersion < 5) await createCalendarV5(db);
      if (oldVersion < 6) {
        // แผน v0.2: วิชาง่ายขั้นต่ำ 2 รอบ/สัปดาห์
        await db.execute(
            'UPDATE subject SET sessions_per_week = 2 WHERE sessions_per_week < 2');
      }
      if (oldVersion < 7) await createCalendarV7(db);
      if (oldVersion < 8) await createStudyPlanV8(db);
    },
  );
}

/// สร้างตาราง Study Tree 4 ตาราง (ตาม Data Model)
Future<void> createStudySchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE subject (
      id                INTEGER PRIMARY KEY AUTOINCREMENT,
      name              TEXT    NOT NULL,
      importance        INTEGER NOT NULL DEFAULT 2,
      sessions_per_week INTEGER NOT NULL DEFAULT 2,
      color             TEXT,
      icon              TEXT,
      status            TEXT    NOT NULL DEFAULT 'active',
      finished_on       TEXT
    )''');

  await db.execute('''
    CREATE TABLE chapter (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id INTEGER NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
      name       TEXT    NOT NULL,
      sort_order INTEGER NOT NULL
    )''');

  await db.execute('''
    CREATE TABLE subtopic (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      chapter_id    INTEGER NOT NULL REFERENCES chapter(id) ON DELETE CASCADE,
      name          TEXT    NOT NULL,
      sort_order    INTEGER NOT NULL,
      exam_flag     INTEGER NOT NULL DEFAULT 0,
      status        TEXT    NOT NULL DEFAULT 'not_started',
      needs_recheck INTEGER NOT NULL DEFAULT 0,
      note          TEXT,
      cleared_at    TEXT
    )''');

  await db.execute('''
    CREATE TABLE assessment (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      subtopic_id INTEGER NOT NULL REFERENCES subtopic(id) ON DELETE CASCADE,
      score       INTEGER NOT NULL CHECK (score BETWEEN 0 AND 100),
      taken_at    TEXT    NOT NULL,
      note        TEXT
    )''');

  // index = สารบัญ ช่วยให้หาแถวลูกของแต่ละแม่ได้เร็ว
  await db.execute('CREATE INDEX idx_chapter_subject ON chapter(subject_id)');
  await db.execute('CREATE INDEX idx_subtopic_chapter ON subtopic(chapter_id)');
  await db.execute(
      'CREATE INDEX idx_assessment_subtopic ON assessment(subtopic_id, taken_at)');
}

/// v8: วิชามีรหัส · หน่วยกิต · ปี/เทอมในแผนการเรียน
/// + ผูกคาบเรียน/วันสอบตัวอย่างที่ใส่ไว้ก่อน v7 เข้ากับวิชา (จับคู่จากชื่องาน)
Future<void> createStudyPlanV8(DatabaseExecutor db) async {
  await addColumnIfMissing(db, 'subject', 'code', 'TEXT');
  await addColumnIfMissing(db, 'subject', 'credits', 'TEXT');
  await addColumnIfMissing(db, 'subject', 'plan_year', 'INTEGER');
  await addColumnIfMissing(db, 'subject', 'plan_term', 'INTEGER');
  await db.execute('''
    UPDATE activity SET subject_id = (
      SELECT s.id FROM subject s
      WHERE activity.name IN ('เรียน · ' || s.name, 'สอบกลางภาค · ' || s.name,
                              'สอบปลายภาค · ' || s.name)
      LIMIT 1)
    WHERE subject_id IS NULL''');
}

/// ตารางตั้งค่าแบบ key → value เช่น grading_mode → ez / advanced
Future<void> createSettingSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE setting (
      key   TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )''');
}

/// ใส่วิชา DaVinci เป็นข้อมูลตั้งต้น (ทำครั้งเดียวตอนสร้างไฟล์)
Future<void> seedStudyData(DatabaseExecutor db) async {
  final subjectId = await db.insert('subject', {
    'name': seedSubjectName,
    'importance': seedSubjectImportance,
    'sessions_per_week': sessionsForImportance(seedSubjectImportance),
  });

  for (var c = 0; c < seedChapters.length; c++) {
    final chapterId = await db.insert('chapter', {
      'subject_id': subjectId,
      'name': seedChapters[c].name,
      'sort_order': c + 1,
    });
    final topics = seedChapters[c].subtopics;
    for (var t = 0; t < topics.length; t++) {
      await db.insert('subtopic', {
        'chapter_id': chapterId,
        'name': topics[t],
        'sort_order': t + 1,
      });
    }
  }
}
