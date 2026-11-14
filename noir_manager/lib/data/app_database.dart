import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart'
    show databaseFactoryFfi, sqfliteFfiInit;

import '../calendar/sqlite_calendar_repository.dart';
import '../calendar/stickers.dart';
import 'backup.dart';
import 'seed_data.dart';
import 'study_repository.dart';

/// เวอร์ชันโครงตาราง: ถ้าวันหลังเพิ่มตาราง/คอลัมน์ ให้เพิ่มเลขนี้ + เขียน onUpgrade
const int _schemaVersion = 18;

/// เลขเวอร์ชันฐานข้อมูล (โชว์ในหน้าตั้งค่า)
const int appSchemaVersion = _schemaVersion; // v2 setting · v3 cleared_at · v4 ปฏิทิน · v5 Preset · v6 วิชาง่าย 2 รอบ · v7 คาบผูกวิชา + เวลาจริง · v8 แผนการเรียน · v9 เรียน/ติว + ประเภท/สถานะบท · v10 เทอม/วันหยุด/บันทึกติว + ย้ายค่าวิชาออกจาก setting · v11 ประเภทคาบ/ห้อง/กลุ่ม · v12 เส้นความสัมพันธ์วิชา · v13 คะแนนเก็บ/เกรด · v14 จำนวนขาดเรียน + บันทึกคาบเรียน · v15 หัวข้อ + งานที่สั่งในคาบ · v16 สติกเกอร์อารมณ์ · v17 รอบ 7 · v18 สติกเกอร์พอดี

/// เปิด (หรือสร้างครั้งแรก) ไฟล์ฐานข้อมูล noir_manager.db
/// ที่อยู่ไฟล์ DB ที่เปิดล่าสุด (ใช้กับระบบสำรองข้อมูล)
String? appDatabasePath;

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
  // กู้คืนที่จองไว้จากหน้าตั้งค่า → ทับไฟล์ก่อนเปิด
  await BackupService.applyPendingRestore(path);
  appDatabasePath = path;

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
      await createTutorV9(db);
      await createTermV10(db);
      await createClassInfoV11(db);
      await createSubjectLinkV12(db);
      await createGradeV13(db);
      await createClassLogV14(db);
      await createClassLogV15(db);
      await createStickerV16(db);
      await createRound7V17(db);
      await createStickerFitV18(db);
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
      if (oldVersion < 9) await createTutorV9(db);
      if (oldVersion < 10) await createTermV10(db);
      if (oldVersion < 11) await createClassInfoV11(db);
      if (oldVersion < 12) await createSubjectLinkV12(db);
      if (oldVersion < 13) await createGradeV13(db);
      if (oldVersion < 14) await createClassLogV14(db);
      if (oldVersion < 15) await createClassLogV15(db);
      if (oldVersion < 16) await createStickerV16(db);
      if (oldVersion < 17) await createRound7V17(db);
      if (oldVersion < 18) await createStickerFitV18(db);
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

/// v9: บทมีประเภท (ทฤษฎี/ปฏิบัติ/ผสม) + สถานะ · งานแยกประเภท เรียน / สอบ / ติว
Future<void> createTutorV9(DatabaseExecutor db) async {
  await addColumnIfMissing(db, 'chapter', 'kind', "TEXT NOT NULL DEFAULT 'theory'");
  await addColumnIfMissing(db, 'chapter', 'status', "TEXT NOT NULL DEFAULT 'todo'");
  // งานเดิมที่ผูกวิชา: ชื่อ "สอบ…" = exam · ที่เหลือ = class
  await db.execute('''
    UPDATE activity SET kind = CASE
      WHEN name LIKE 'สอบ%' THEN 'exam' ELSE 'class' END
    WHERE subject_id IS NOT NULL AND kind = 'todo' ''');
}

/// v10:
/// 1. ตาราง term (ภาคเรียน) · holiday (วันหยุด) · tutor_log (รอบติวไหนติวบทไหน)
/// 2. สีวิชา + ความยาวรอบติว ย้ายจาก setting (subject_color_<id>, tutor_min_<id>) มาเป็นคอลัมน์ของ subject
/// 3. หมวด "เรียน" มีรหัสระบบ system_key = 'study' → เปลี่ยนชื่อหมวดแล้วระบบติวไม่พัง
Future<void> createTermV10(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS term (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      year       INTEGER NOT NULL,
      term_no    INTEGER NOT NULL,
      start_date TEXT    NOT NULL,
      end_date   TEXT    NOT NULL,
      UNIQUE (year, term_no)
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS holiday (
      day  TEXT PRIMARY KEY,
      name TEXT NOT NULL
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS tutor_log (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      occurrence_id INTEGER NOT NULL REFERENCES occurrence(id) ON DELETE CASCADE,
      chapter_id    INTEGER REFERENCES chapter(id) ON DELETE SET NULL,
      status        TEXT    NOT NULL,
      logged_at     TEXT    NOT NULL
    )''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_tutor_log_chapter ON tutor_log(chapter_id)');

  // ---- ย้ายค่าวิชาออกจาก setting ----
  await addColumnIfMissing(db, 'subject', 'tutor_minutes', 'INTEGER NOT NULL DEFAULT 90');
  await db.execute('''
    UPDATE subject SET tutor_minutes = (
      SELECT CAST(value AS INTEGER) FROM setting WHERE key = 'tutor_min_' || subject.id)
    WHERE EXISTS (SELECT 1 FROM setting WHERE key = 'tutor_min_' || subject.id)''');
  await db.execute('''
    UPDATE subject SET color = (
      SELECT value FROM setting WHERE key = 'subject_color_' || subject.id)
    WHERE EXISTS (SELECT 1 FROM setting WHERE key = 'subject_color_' || subject.id)''');
  await db.execute(
      "DELETE FROM setting WHERE key LIKE 'tutor_min_%' OR key LIKE 'subject_color_%'");

  // ---- หมวดเรียน: ผูกด้วยรหัส ไม่ใช่ชื่อ ----
  await addColumnIfMissing(db, 'category', 'system_key', 'TEXT');
  await db.execute('''
    UPDATE category SET system_key = 'study'
    WHERE id = (SELECT MIN(id) FROM category WHERE name = 'เรียน')
      AND NOT EXISTS (SELECT 1 FROM category WHERE system_key = 'study')''');
}

/// v11: ข้อมูลคาบเรียน — ประเภท (theory/lab) · ห้อง · กลุ่มเรียน
/// เพิ่มคอลัมน์อย่างเดียว ไม่แตะข้อมูลเดิม · คาบเก่า = null (ขึ้นว่า "ไม่ระบุประเภท")
Future<void> createClassInfoV11(DatabaseExecutor db) async {
  await addColumnIfMissing(db, 'activity', 'class_type', 'TEXT');
  await addColumnIfMissing(db, 'activity', 'room', 'TEXT');
  await addColumnIfMissing(db, 'activity', 'section', 'TEXT');
}

/// v12: เส้นความสัมพันธ์ในแผนผัง — from_id ต้องเรียนก่อน to_id
/// ตารางใหม่อย่างเดียว ไม่แตะข้อมูลเดิม · ลบวิชา → เส้นของวิชานั้นหายตาม (CASCADE)
Future<void> createSubjectLinkV12(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS subject_link (
      from_id INTEGER NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
      to_id   INTEGER NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
      PRIMARY KEY (from_id, to_id),
      CHECK (from_id <> to_id)
    )''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_subject_link_to ON subject_link(to_id)');
}

/// v13: ระบบเกรด — ส่วนคะแนน (งาน/สอบย่อย/สอบ) → ชิ้นคะแนน · ตั้งค่าเกรดต่อวิชา
/// ตารางใหม่อย่างเดียว ไม่แตะข้อมูลเดิม · ลบวิชา → คะแนนของวิชานั้นหายตาม (CASCADE)
Future<void> createGradeV13(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS grade_part (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id INTEGER NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
      name       TEXT NOT NULL,
      weight     REAL NOT NULL,
      sort       INTEGER NOT NULL DEFAULT 0
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS grade_item (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      part_id INTEGER NOT NULL REFERENCES grade_part(id) ON DELETE CASCADE,
      name    TEXT NOT NULL,
      full_score REAL NOT NULL,
      got_score  REAL,
      sort    INTEGER NOT NULL DEFAULT 0
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS grade_setup (
      subject_id  INTEGER PRIMARY KEY REFERENCES subject(id) ON DELETE CASCADE,
      scale       TEXT,
      absent_over INTEGER NOT NULL DEFAULT 0,
      missed_exam INTEGER NOT NULL DEFAULT 0,
      official    TEXT
    )''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grade_part_subject ON grade_part(subject_id)');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_grade_item_part ON grade_item(part_id)');
}

/// v14: ขาดเรียนเป็นจำนวนคาบ (แอปคิด % เอง) · บันทึกว่าแต่ละคาบเรียนบทไหน จบบทไหม
/// เพิ่มคอลัมน์ + ตารางใหม่อย่างเดียว ไม่แตะข้อมูลเดิม
Future<void> createClassLogV14(DatabaseExecutor db) async {
  await addColumnIfMissing(db, 'grade_setup', 'absent_count', 'INTEGER NOT NULL DEFAULT 0');
  await addColumnIfMissing(db, 'grade_setup', 'class_total', 'INTEGER'); // null = นับจากปฏิทิน
  await addColumnIfMissing(db, 'grade_setup', 'absent_limit', 'REAL NOT NULL DEFAULT 20');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS class_log (
      id            INTEGER PRIMARY KEY AUTOINCREMENT,
      subject_id    INTEGER NOT NULL REFERENCES subject(id) ON DELETE CASCADE,
      occurrence_id INTEGER REFERENCES occurrence(id) ON DELETE SET NULL,
      chapter_id    INTEGER REFERENCES chapter(id) ON DELETE SET NULL,
      day           TEXT NOT NULL,
      finished      INTEGER NOT NULL DEFAULT 0,
      note          TEXT
    )''');
  await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_class_log_subject ON class_log(subject_id)');
}

/// v15: บันทึกคาบเก็บหัวข้อที่เรียน + งาน/การบ้านที่อาจารย์สั่ง (ชื่อ · กำหนดส่ง · งานในปฏิทิน)
Future<void> createClassLogV15(DatabaseExecutor db) async {
  await addColumnIfMissing(db, 'class_log', 'topics', 'TEXT'); // ชื่อหัวข้อคั่นด้วย \n
  await addColumnIfMissing(db, 'class_log', 'homework', 'TEXT');
  await addColumnIfMissing(db, 'class_log', 'due_at', 'TEXT');
  await addColumnIfMissing(db, 'class_log', 'task_activity_id', 'INTEGER');
}

/// v16: สติกเกอร์อารมณ์รายวัน · ชุด → ชิ้น → แปะในวัน · ใส่ชุดในตัวแอปให้ครั้งเดียว
Future<void> createStickerV16(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sticker_pack (
      id      INTEGER PRIMARY KEY AUTOINCREMENT,
      name    TEXT NOT NULL,
      builtin INTEGER NOT NULL DEFAULT 0,
      enabled INTEGER NOT NULL DEFAULT 1,
      sort    INTEGER NOT NULL DEFAULT 0
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS sticker (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      pack_id    INTEGER NOT NULL REFERENCES sticker_pack(id) ON DELETE CASCADE,
      name       TEXT NOT NULL,
      emoji      TEXT,
      image_path TEXT,
      sort       INTEGER NOT NULL DEFAULT 0
    )''');
  await db.execute('''
    CREATE TABLE IF NOT EXISTS day_sticker (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      day        TEXT NOT NULL,
      sticker_id INTEGER NOT NULL REFERENCES sticker(id) ON DELETE CASCADE,
      note       TEXT
    )''');
  await db.execute('CREATE INDEX IF NOT EXISTS idx_day_sticker_day ON day_sticker(day)');
  final has = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM sticker_pack WHERE builtin = 1')) ?? 0;
  if (has > 0) return;
  for (final (pi, (name, items)) in builtinStickerPacks.indexed) {
    final pack = await db.insert('sticker_pack', {'name': name, 'builtin': 1, 'sort': pi});
    for (final (i, (n, e)) in items.indexed) {
      await db.insert('sticker', {'pack_id': pack, 'name': n, 'emoji': e, 'sort': i});
    }
  }
}

/// v18 (รอบ 8B): สติกเกอร์ปรับให้พอดี (ซูม · เลื่อน) · เพิ่มคอลัมน์อย่างเดียว ค่าเริ่มต้น = หน้าตาเดิม
Future<void> createStickerFitV18(DatabaseExecutor db) async {
  final has = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'sticker'")).isNotEmpty;
  if (!has) return; // เทสบางตัวสร้าง schema ไม่ครบ
  await addColumnIfMissing(db, 'sticker', 'scale', 'REAL NOT NULL DEFAULT 1');
  await addColumnIfMissing(db, 'sticker', 'dx', 'REAL NOT NULL DEFAULT 0');
  await addColumnIfMissing(db, 'sticker', 'dy', 'REAL NOT NULL DEFAULT 0');
}

/// v17 (รอบ 7): เพิ่มคอลัมน์อย่างเดียว ไม่แตะข้อมูลเดิม
/// - หมวด: ค่าเริ่มต้น (ความสำคัญ · ความยาว) · แทนได้ · ล็อกเมื่อเริ่ม · กลุ่มสถิติ · ซ่อน
/// - งาน: ยืดหยุ่น (บางวันว่างได้) · ครั้ง: ช่วงที่ว่างจากงาน
/// - สติกเกอร์ในวัน: ตำแหน่ง (x, y 0–1) · ไฮไลต์ · แปะอัตโนมัติ (missed / late)
/// - เช็กอินเช้า: นอนจริง · ตื่น · พลัง 1–5 (ไว้วิเคราะห์ย้อนหลัง)
Future<void> createRound7V17(DatabaseExecutor db) async {
  // เทสบางตัวสร้าง schema ไม่ครบ → เพิ่มเฉพาะตารางที่มี
  Future<bool> has(String t) async =>
      (await db.rawQuery("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?", [t])).isNotEmpty;
  if (await has('category')) {
    await addColumnIfMissing(db, 'category', 'default_importance', 'INTEGER');
    await addColumnIfMissing(db, 'category', 'default_minutes', 'INTEGER');
    await addColumnIfMissing(db, 'category', 'replaceable', 'INTEGER NOT NULL DEFAULT 1');
    await addColumnIfMissing(db, 'category', 'lock_on_start', 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(db, 'category', 'stats_group', 'TEXT');
    await addColumnIfMissing(db, 'category', 'hidden', 'INTEGER NOT NULL DEFAULT 0');
    // ไอคอนเริ่มต้นของหมวดที่มีอยู่ (ถ้ายังไม่มี) · ผู้ใช้เปลี่ยนได้
    for (final (name, icon) in const [('เรียน', '🎓'), ('ออกกำลังกาย', '💪'), ('สตรีม', '🎮'), ('งาน', '💼'), ('อื่น ๆ', '📌')]) {
      await db.execute("UPDATE category SET icon = ? WHERE name = ? AND (icon IS NULL OR icon = '')", [icon, name]);
    }
  }
  if (await has('activity')) await addColumnIfMissing(db, 'activity', 'flexible', 'INTEGER NOT NULL DEFAULT 0');
  if (await has('occurrence')) {
    await addColumnIfMissing(db, 'occurrence', 'free_start', 'TEXT');
    await addColumnIfMissing(db, 'occurrence', 'free_end', 'TEXT');
  }
  if (await has('day_sticker')) {
    await addColumnIfMissing(db, 'day_sticker', 'x', 'REAL');
    await addColumnIfMissing(db, 'day_sticker', 'y', 'REAL');
    await addColumnIfMissing(db, 'day_sticker', 'highlight', 'INTEGER NOT NULL DEFAULT 0');
    await addColumnIfMissing(db, 'day_sticker', 'auto', 'TEXT');
  }
  await db.execute('''
    CREATE TABLE IF NOT EXISTS checkin (
      day        TEXT PRIMARY KEY,
      slept_at   TEXT,
      woke_at    TEXT,
      energy     INTEGER,
      miss_reason TEXT
    )''');
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
