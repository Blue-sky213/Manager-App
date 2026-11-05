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

/// ฐานข้อมูล v5: Preset + โหมดเลือกวันเอง (activity_date) + Preset ตั้งต้น "Stream"
/// v7: คาบเรียนผูกกับวิชา + เวลาเริ่ม/เลิกจริง (ทำสถิติเลิกเร็ว/ช้า)
///
/// ตาราง activity ของ v4 มีคอลัมน์ subject_id อยู่แล้ว (เตรียมไว้ตาม Data Model)
/// → เพิ่มเฉพาะคอลัมน์ที่ยังไม่มี ไม่งั้น SQLite แจ้ง "duplicate column name"
Future<void> createCalendarV7(DatabaseExecutor db) async {
  await addColumnIfMissing(db, 'activity', 'subject_id', 'INTEGER');
  await addColumnIfMissing(db, 'occurrence', 'actual_start', 'TEXT');
  await addColumnIfMissing(db, 'occurrence', 'actual_end', 'TEXT');
}

/// ALTER TABLE ... ADD COLUMN แบบปลอดภัย: เช็กชื่อคอลัมน์ที่มีอยู่ก่อน (PRAGMA table_info)
Future<void> addColumnIfMissing(
    DatabaseExecutor db, String table, String column, String type) async {
  final cols = await db.rawQuery('PRAGMA table_info($table)');
  if (cols.any((c) => c['name'] == column)) return;
  await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
}

Future<void> createCalendarV5(DatabaseExecutor db) async {
  await db.execute('''
    CREATE TABLE preset (
      id           INTEGER PRIMARY KEY AUTOINCREMENT,
      name         TEXT    NOT NULL,
      category_id  INTEGER REFERENCES category(id) ON DELETE SET NULL,
      importance   INTEGER NOT NULL DEFAULT 2,
      start_minute INTEGER,
      duration_min INTEGER
    )''');
  await db.execute(
      'ALTER TABLE activity ADD COLUMN preset_id INTEGER REFERENCES preset(id) ON DELETE SET NULL');
  // วันที่เลือกเอง + เวลาเฉพาะวัน (NULL = ใช้เวลาหลักของงาน)
  await db.execute('''
    CREATE TABLE activity_date (
      activity_id  INTEGER NOT NULL REFERENCES activity(id) ON DELETE CASCADE,
      day          TEXT    NOT NULL,
      start_minute INTEGER,
      duration_min INTEGER,
      PRIMARY KEY (activity_id, day)
    )''');

  final stream = await db.query('category',
      columns: ['id'], where: 'name = ?', whereArgs: ['สตรีม'], limit: 1);
  await db.insert('preset', {
    'name': 'Stream',
    'category_id': stream.isEmpty ? null : stream.first['id'],
    'importance': 3,
    'start_minute': 20 * 60,
    'duration_min': 4 * 60,
  });
}

/// CalendarRepository ตัวจริง: อ่าน/เขียนไฟล์ SQLite
class SqliteCalendarRepository extends CalendarRepository {
  SqliteCalendarRepository(this._db);

  final Database _db;

  /// SELECT ที่ใช้ซ้ำ: งานแต่ละครั้ง + ชื่อ/หมวด/ความสำคัญจากกิจกรรมต้นแบบ
  static const _occurrenceSelect = '''
    SELECT o.*, a.name AS a_name, a.category_id, a.importance, a.repeat, a.subject_id, a.kind AS a_kind,
      -- root_day: ไล่ moved_from ย้อนกลับจนเจอครั้งต้นทางที่มี origin_day (เลื่อนกี่ทอดก็ได้)
      (WITH RECURSIVE chain(cday, cfrom) AS (
         SELECT o.origin_day, o.moved_from
         UNION ALL
         SELECT p.origin_day, p.moved_from FROM occurrence p
           JOIN chain ON p.id = chain.cfrom
           WHERE chain.cday IS NULL)
       SELECT cday FROM chain WHERE cday IS NOT NULL LIMIT 1) AS root_day
    FROM occurrence o
    JOIN activity a ON a.id = o.activity_id
  ''';

  @override
  Future<List<ActivityCategory>> categories() async {
    final rows = await _db.query('category', orderBy: 'sort_order, id');
    return rows.map(ActivityCategory.fromRow).toList();
  }

  /// ค่าของแถว activity จากฟอร์ม
  Map<String, Object?> _activityRow(NewActivity n) {
    final a = n.toActivity();
    return {
      'name': a.name,
      'category_id': a.categoryId,
      'importance': a.importance,
      'timed': a.timed ? 1 : 0,
      'start_minute': a.startMinute,
      'duration_min': a.durationMin,
      'repeat': a.repeat.name,
      'weekdays': weekdaysToText(a.weekdays),
      'start_date': dayKey(a.startDate),
      'end_date': a.endDate == null ? null : dayKey(a.endDate!),
      'preset_id': a.presetId,
      'subject_id': a.subjectId,
      'kind': activityKindDb(a.kind),
    };
  }

  Future<void> _writeDates(DatabaseExecutor db, int activityId, NewActivity n) async {
    await db.delete('activity_date',
        where: 'activity_id = ?', whereArgs: [activityId]);
    if (n.repeat != RepeatKind.dates) return;
    for (final d in n.dates) {
      await db.insert(
        'activity_date',
        {
          'activity_id': activityId,
          'day': dayKey(d.day),
          'start_minute': d.startMinute,
          'duration_min': d.durationMin,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  @override
  Future<int> addActivity(NewActivity a) async {
    late int id;
    await _db.transaction((txn) async {
      id = await txn.insert('activity', _activityRow(a));
      await _writeDates(txn, id, a);
    });
    notifyListeners();
    return id;
  }

  @override
  Future<Activity> activity(int activityId) async {
    final row = (await _db.query('activity',
            where: 'id = ?', whereArgs: [activityId], limit: 1))
        .first;
    final dates = await _db.query('activity_date',
        where: 'activity_id = ?', whereArgs: [activityId], orderBy: 'day');
    return Activity.fromRow(row, dates: {
      for (final d in dates)
        d['day'] as String: ScheduledDate(
          DateTime.parse(d['day'] as String),
          startMinute: d['start_minute'] as int?,
          durationMin: d['duration_min'] as int?,
        ),
    });
  }

  @override
  Future<void> updateActivity(int activityId, NewActivity a,
      {DateTime? from}) async {
    final fromKey = dayKey(from ?? DateTime.now());
    await _db.transaction((txn) async {
      await txn.update('activity', _activityRow(a),
          where: 'id = ?', whereArgs: [activityId]);
      await _writeDates(txn, activityId, a);
      // ลบ "ครั้งที่ยังเป็นแผน" ตั้งแต่ from → เปิดดูวันนั้นอีกครั้งจะสร้างใหม่ตามค่าใหม่
      await txn.delete('occurrence',
          where: 'activity_id = ? AND origin_day >= ? AND status = ?',
          whereArgs: [activityId, fromKey, OccurrenceStatus.planned.name]);
    });
    notifyListeners();
  }

  @override
  Future<void> updateOccurrenceTime(
      int occurrenceId, DateTime start, DateTime end) async {
    await _db.update('occurrence',
        {'start_at': start.toIso8601String(), 'end_at': end.toIso8601String()},
        where: 'id = ?', whereArgs: [occurrenceId]);
    notifyListeners();
  }

  @override
  Future<List<Preset>> presets() async {
    final rows = await _db.query('preset', orderBy: 'name');
    return rows.map(Preset.fromRow).toList();
  }

  @override
  Future<int> addPreset(String name, NewActivity v) async {
    final id = await _db.insert('preset', {
      'name': name,
      'category_id': v.categoryId,
      'importance': v.importance,
      'start_minute': v.timed ? v.startMinute : null,
      'duration_min': v.timed ? v.durationMin : null,
    });
    notifyListeners();
    return id;
  }

  @override
  Future<void> deletePreset(int presetId) async {
    // งานที่ใช้ Preset นี้ไม่ถูกลบ แค่หลุดจากกลุ่ม (ON DELETE SET NULL)
    await _db.delete('preset', where: 'id = ?', whereArgs: [presetId]);
    notifyListeners();
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
        where: "repeat = 'dates' OR "
            '(start_date <= ? AND (end_date IS NULL OR end_date >= ?))',
        whereArgs: [key, key]);
    // วันที่เลือกเอง (เฉพาะของวันนี้) แยกตามกิจกรรม
    final dateRows = await _db
        .query('activity_date', where: 'day = ?', whereArgs: [key]);
    final datesOf = {
      for (final d in dateRows)
        d['activity_id'] as int: ScheduledDate(day,
            startMinute: d['start_minute'] as int?,
            durationMin: d['duration_min'] as int?),
    };
    final batch = _db.batch();
    for (final row in acts) {
      final id = row['id'] as int;
      final a = Activity.fromRow(row,
          dates: datesOf[id] == null ? const {} : {key: datesOf[id]!});
      if (!occursOn(a, day)) continue;
      final time = timeFor(a, day);
      final start = time == null ? null : atMinute(day, time.$1);
      batch.insert(
        'occurrence',
        {
          'activity_id': a.id,
          'origin_day': key,
          'day': key,
          'start_at': start?.toIso8601String(),
          'end_at': start?.add(Duration(minutes: time!.$2)).toIso8601String(),
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
    return attachSessions(rows.map(Occurrence.fromRow).toList());
  }

  @override
  Future<void> setActualTimes(int occurrenceId, {DateTime? start, DateTime? end}) async {
    await _db.update(
      'occurrence',
      {'actual_start': start?.toIso8601String(), 'actual_end': end?.toIso8601String()},
      where: 'id = ?',
      whereArgs: [occurrenceId],
    );
    notifyListeners();
  }

  @override
  Future<List<Activity>> activitiesForSubject(int subjectId) async {
    final rows = await _db.query('activity',
        where: 'subject_id = ?', whereArgs: [subjectId], orderBy: 'start_date, id');
    return rows.map((r) => Activity.fromRow(r)).toList();
  }

  @override
  Future<List<Occurrence>> occurrencesForSubject(int subjectId) async {
    final rows = await _db.rawQuery(
        '$_occurrenceSelect WHERE a.subject_id = ? ORDER BY o.day, o.start_at',
        [subjectId]);
    return attachSessions(rows.map(Occurrence.fromRow).toList());
  }

  @override
  Future<List<Occurrence>> inbox() async {
    final rows = await _db.rawQuery(
        '$_occurrenceSelect WHERE o.status = ? ORDER BY o.day, o.id',
        [OccurrenceStatus.inbox.name]);
    return attachSessions(rows.map(Occurrence.fromRow).toList());
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

  @override
  Future<List<Term>> terms() async {
    final rows = await _db.query('term', orderBy: 'year, term_no');
    return rows.map(Term.fromRow).toList();
  }

  @override
  Future<void> saveTerm(int year, int termNo, DateTime start, DateTime end) async {
    // UNIQUE(year, term_no) + replace = ปี/เทอมเดิมเขียนทับ
    await _db.insert(
      'term',
      {'year': year, 'term_no': termNo, 'start_date': dayKey(start), 'end_date': dayKey(end)},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  @override
  Future<void> deleteTerm(int termId) async {
    await _db.delete('term', where: 'id = ?', whereArgs: [termId]);
    notifyListeners();
  }

  @override
  Future<List<Holiday>> holidays() async {
    final rows = await _db.query('holiday', orderBy: 'day');
    return [
      for (final r in rows) Holiday(DateTime.parse(r['day'] as String), r['name'] as String),
    ];
  }

  @override
  Future<void> setHoliday(DateTime day, String name) async {
    await _db.insert('holiday', {'day': dayKey(day), 'name': name},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<void> removeHoliday(DateTime day) async {
    await _db.delete('holiday', where: 'day = ?', whereArgs: [dayKey(day)]);
    notifyListeners();
  }

  @override
  Future<DateTime?> shiftToNextRound(int occurrenceId, String reason) async {
    DateTime? newEnd;
    // transaction: ปิดครั้งนี้ + ขยายวันสุดท้าย ต้องสำเร็จพร้อมกัน
    await _db.transaction((txn) async {
      final occ = (await txn.query('occurrence',
              where: 'id = ?', whereArgs: [occurrenceId], limit: 1))
          .first;
      final row = (await txn.query('activity',
              where: 'id = ?', whereArgs: [occ['activity_id']], limit: 1))
          .first;
      final a = Activity.fromRow(row);
      if (!canShiftToNextRound(a)) {
        throw StateError('งานนี้ไม่มีกฎการทำซ้ำ เลื่อนไปรอบถัดไปไม่ได้');
      }
      await txn.update(
          'occurrence', {'status': OccurrenceStatus.shifted.name, 'reason': reason},
          where: 'id = ?', whereArgs: [occurrenceId]);
      if (a.endDate != null) {
        newEnd = nextSlotAfter(a, a.endDate!);
        await txn.update('activity', {'end_date': dayKey(newEnd!)},
            where: 'id = ?', whereArgs: [a.id]);
      }
    });
    notifyListeners();
    return newEnd;
  }

  @override
  Future<Set<DateTime>> shiftedDays(int activityId) async {
    final rows = await _db.rawQuery(
        '$_occurrenceSelect WHERE o.activity_id = ? AND o.status = ?',
        [activityId, OccurrenceStatus.shifted.name]);
    return {
      for (final r in rows)
        if (r['root_day'] != null) DateTime.parse(r['root_day'] as String),
    };
  }

  @override
  Future<String?> getSetting(String key) async {
    final rows =
        await _db.query('setting', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    await _db.insert('setting', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<int> removeDuplicateActivities() async {
    final rows = await _db.query('activity', where: "kind IN ('class', 'exam')");
    final ids = duplicateActivityIds(rows.map(Activity.fromRow));
    if (ids.isEmpty) return 0;
    // CASCADE: ครั้งของงานที่ซ้ำถูกลบตามไปด้วย
    final batch = _db.batch();
    for (final id in ids) {
      batch.delete('activity', where: 'id = ?', whereArgs: [id]);
    }
    await batch.commit(noResult: true);
    notifyListeners();
    return ids.length;
  }
}
