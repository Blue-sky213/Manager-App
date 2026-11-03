import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import 'seed_data.dart';
import 'study_repository.dart';

/// เวอร์ชันโครงตาราง: ถ้าวันหลังเพิ่มตาราง/คอลัมน์ ให้เพิ่มเลขนี้ + เขียน onUpgrade
const int _schemaVersion = 1;

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
    onCreate: (db, version) async {
      await createStudySchema(db);
      await seedStudyData(db);
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
      note          TEXT
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
