import 'package:sqflite/sqflite.dart';

import 'calendar_models.dart';
import 'calendar_repository.dart';

/// สร้างตารางฝั่งปฏิทิน (ฐานข้อมูล v4) + ใส่หมวดและเวลานอนตั้งต้น
Future<void> createCalendarSchema(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE category (
      id         INTEGER PRIMARY KEY AUTOINCREMENT,
      name       TEXT    NOT NULL,
      color      TEXT    NOT NULL,
      icon       TEXT,
      sort_order INTEGER NOT NULL
    )''');

  await db.execute('''
    CREATE TABLE activity (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      name         TEXT    NOT NULL,
      category_id  INTEGER REFERENCES category(id) ON DELETE SET NULL,
      kind         TEXT    NOT NULL DEFAULT 'todo',
      importance   INTEGER NOT NULL DEFAULT 2,
      timed        INTEGER NOT NULL,
      start_minute INTEGER,
      duration_min INTEGER,
      repeat       TEXT    NOT NULL DEFAULT 'none',
      weekdays     TEXT    NOT NULL DEFAULT '',
      start_date   TEXT    NOT NULL,
      end_date     TEXT,
      subject_id   INTEGER REFERENCES subject(id) ON DELETE SET NULL,
      icon         TEXT
    )''');

  // origin_day = วันที่งานซ้ำ "ควรเกิด" (ครั้งที่เลื่อนมา = NULL)
  // UNIQUE กันสร้างครั้งเดียวกันซ้ำ เวลาเปิดดูวันเดิมหลายรอบ
  await db.execute('''
    CREATE TABLE occurrence (
      id          INTEGER PRIMARY KEY AUTOINCREMENT,
      activity_id INTEGER NOT NULL REFERENCES activity(id) ON DELETE CASCADE,
      origin_day  TEXT,
      day         TEXT    NOT NULL,
      start_at    TEXT,
      end_at      TEXT,
      title       TEXT,
      status      TEXT    NOT NULL DEFAULT 'planned',
      reason      TEXT,
      note        TEXT,
      moved_from  INTEGER REFERENCES occurrence(id) ON DELETE SET NULL
    )''');
  await db.execute(
      'CREATE UNIQUE INDEX idx_occ_origin ON occurrence(activity_id, origin_day)');
  await db.execute('CREATE INDEX idx_occ_day ON occurrence(day)');
  await db.execute('CREATE INDEX idx_occ_status ON occurrence(status)');

  await db.execute('''
    CREATE TABLE life_base (
      weekday     INTEGER PRIMARY KEY,
      bed_minute  INTEGER NOT NULL,
      wake_minute INTEGER NOT NULL,
      sleep_goal  REAL
    )''');

  for (var i = 0; i < seedCategories.length; i++) {
    await db.insert('category', {
      'name': seedCategories[i].$1,
      'color': seedCategories[i].$2,
      'sort_order': i + 1,
    });
  }
  for (final d in defaultLifeBase()) {
    await db.insert('life_base', {
      'weekday': d.weekday,
      'bed_minute': d.bedMinute,
      'wake_minute': d.wakeMinute,
    });
  }
}

/// CalendarRepository ตัวจริง: อ่าน/เขียนไฟล์ SQLite
class SqliteCalendarRepository extends CalendarRepository {
  SqliteCalendarRepository(this._db);

  final Database _db;

  /// SELECT ที่ใช้ซ้ำ: งานแต่ละครั้ง + ชื่อ/หมวด/ความสำคัญจากกิจกรรมต้นแบบ
  static const _occurrenceSelect = '''
    SELECT o.*, a.name AS a_name, a.category_id, a.importance, a.repeat
    FROM occurrence o
    JOIN activity a ON a.id = o.activity_id
  ''';

  @override
  Future<List<ActivityCategory>> categories() async {
    final rows = await _db.query('category', orderBy: 'sort_order, id');
    return rows.map(ActivityCategory.fromRow).toList();
  }

  @override
  Future<int> addActivity(NewActivity a) async {
    final id = await _db.insert('activity', {
      'name': a.name,
      'category_id': a.categoryId,
      'importance': a.importance,
      'timed': a.timed ? 1 : 0,
      'start_minute': a.timed ? a.startMinute : null,
      'duration_min': a.timed ? a.durationMin : null,
      'repeat': a.repeat.name,
      'weekdays': weekdaysToText(a.weekdays),
      'start_date': dayKey(a.day),
    });
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteActivity(int activityId) async {
    await _db.delete('activity', where: 'id = ?', whereArgs: [activityId]);
    notifyListeners();
  }

  @override
  Future<List<Occurrence>> occurrencesOn(DateTime day) async {
    final key = dayKey(day);

    // 1) สร้าง "ครั้ง" ของงานที่ควรมีในวันนี้ (ถ้ามีอยู่แล้ว UNIQUE จะ IGNORE ให้)
    final acts = await _db.query('activity',
        where: 'start_date <= ? AND (end_date IS NULL OR end_date >= ?)',
        whereArgs: [key, key]);
    final batch = _db.batch();
    for (final row in acts) {
      final a = Activity.fromRow(row);
      if (!occursOn(a, day)) continue;
      final start = a.timed ? atMinute(day, a.startMinute!) : null;
      batch.insert(
        'occurrence',
        {
          'activity_id': a.id,
          'origin_day': key,
          'day': key,
          'start_at': start?.toIso8601String(),
          'end_at': start?.add(Duration(minutes: a.durationMin!)).toIso8601String(),
          'status': OccurrenceStatus.planned.name,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);

    // 2) อ่านทุกครั้งของวันนี้: ล็อกเวลาก่อน (เรียงตามเวลา) แล้วค่อยงานแบบลิสต์
    final rows = await _db.rawQuery(
        '$_occurrenceSelect WHERE o.day = ? '
        'ORDER BY o.start_at IS NULL, o.start_at, o.id',
        [key]);
    return rows.map(Occurrence.fromRow).toList();
  }

  @override
  Future<List<Occurrence>> inbox() async {
    final rows = await _db.rawQuery(
        '$_occurrenceSelect WHERE o.status = ? ORDER BY o.day, o.id',
        [OccurrenceStatus.inbox.name]);
    return rows.map(Occurrence.fromRow).toList();
  }

  Future<void> _setStatus(int id, OccurrenceStatus s, {String? reason}) async {
    await _db.update('occurrence', {'status': s.name, 'reason': reason},
        where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  @override
  Future<void> setDone(int occurrenceId, bool done) => _setStatus(
      occurrenceId, done ? OccurrenceStatus.done : OccurrenceStatus.planned);

  @override
  Future<void> cancel(int occurrenceId, String reason) =>
      _setStatus(occurrenceId, OccurrenceStatus.cancelled, reason: reason);

  @override
  Future<void> sendToInbox(int occurrenceId) =>
      _setStatus(occurrenceId, OccurrenceStatus.inbox);

  @override
  Future<int> moveOccurrence(int occurrenceId, DateTime day,
      {DateTime? start, DateTime? end}) async {
    late int newId;
    // transaction: ปิดครั้งเดิม + สร้างครั้งใหม่ ต้องสำเร็จพร้อมกัน
    await _db.transaction((txn) async {
      final old = (await txn.query('occurrence',
              where: 'id = ?', whereArgs: [occurrenceId], limit: 1))
          .first;
      await txn.update('occurrence', {'status': OccurrenceStatus.moved.name},
          where: 'id = ?', whereArgs: [occurrenceId]);
      newId = await txn.insert('occurrence', {
        'activity_id': old['activity_id'],
        'origin_day': null,
        'day': dayKey(day),
        'start_at': start?.toIso8601String(),
        'end_at': end?.toIso8601String(),
        'title': old['title'],
        'status': OccurrenceStatus.planned.name,
        'moved_from': occurrenceId,
      });
    });
    notifyListeners();
    return newId;
  }

  @override
  Future<void> moveSeries(
      int activityId, DateTime fromDay, int startMinute, int durationMin) async {
    await _db.transaction((txn) async {
      await txn.update(
          'activity', {'start_minute': startMinute, 'duration_min': durationMin},
          where: 'id = ?', whereArgs: [activityId]);
      // ครั้งที่สร้างไว้แล้วตั้งแต่ fromDay และยังเป็นแผนเดิม → เปลี่ยนเวลาตาม
      final rows = await txn.query('occurrence',
          columns: ['id', 'day'],
          where: 'activity_id = ? AND origin_day >= ? AND status = ?',
          whereArgs: [activityId, dayKey(fromDay), OccurrenceStatus.planned.name]);
      for (final r in rows) {
        final start = atMinute(DateTime.parse(r['day'] as String), startMinute);
        await txn.update(
            'occurrence',
            {
              'start_at': start.toIso8601String(),
              'end_at': start.add(Duration(minutes: durationMin)).toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [r['id']]);
      }
    });
    notifyListeners();
  }

  @override
  Future<List<LifeBaseDay>> lifeBase() async {
    final rows = await _db.query('life_base', orderBy: 'weekday');
    if (rows.length < 7) return defaultLifeBase();
    return [
      for (final r in rows)
        LifeBaseDay(
          weekday: r['weekday'] as int,
          bedMinute: r['bed_minute'] as int,
          wakeMinute: r['wake_minute'] as int,
        ),
    ];
  }

  @override
  Future<void> setLifeBase(List<LifeBaseDay> days) async {
    final batch = _db.batch();
    for (final d in days) {
      batch.insert(
        'life_base',
        {
          'weekday': d.weekday,
          'bed_minute': d.bedMinute,
          'wake_minute': d.wakeMinute,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    notifyListeners();
  }
}
