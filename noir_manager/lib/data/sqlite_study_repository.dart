import 'package:sqflite/sqflite.dart';

import '../study/mastery.dart';
import 'study_models.dart';
import 'study_repository.dart';

/// StudyRepository ตัวจริง: อ่าน/เขียนไฟล์ SQLite ในเครื่อง
class SqliteStudyRepository implements StudyRepository {
  SqliteStudyRepository(this._db);

  final Database _db;

  @override
  Future<List<Subject>> subjects() async {
    final rows = await _db.query('subject', orderBy: 'id');
    return rows.map(Subject.fromRow).toList();
  }

  @override
  Future<int> addSubject(String name, {int importance = 2}) {
    return _db.insert('subject', {
      'name': name,
      'importance': importance,
      'sessions_per_week': sessionsForImportance(importance),
    });
  }

  @override
  Future<void> setSubjectPlan(int subjectId,
      {String? code, String? credits, int? year, int? term}) async {
    await _db.update(
      'subject',
      {
        if (code != null) 'code': code,
        if (credits != null) 'credits': credits,
        if (year != null) 'plan_year': year,
        if (term != null) 'plan_term': term,
      },
      where: 'id = ?',
      whereArgs: [subjectId],
    );
  }

  @override
  Future<void> renameSubject(int subjectId, String name) async {
    await _db.update('subject', {'name': name},
        where: 'id = ?', whereArgs: [subjectId]);
  }

  @override
  Future<void> setSessionsPerWeek(int subjectId, int sessions) async {
    final rows = await _db.query('subject',
        columns: ['importance'], where: 'id = ?', whereArgs: [subjectId]);
    if (rows.isEmpty) return;
    await _db.update(
      'subject',
      {'sessions_per_week': clampSessions(rows.first['importance'] as int, sessions)},
      where: 'id = ?',
      whereArgs: [subjectId],
    );
  }

  @override
  Future<void> setSubjectImportance(int subjectId, int importance) async {
    await _db.update(
      'subject',
      {
        'importance': importance,
        'sessions_per_week': sessionsForImportance(importance),
      },
      where: 'id = ?',
      whereArgs: [subjectId],
    );
  }

  @override
  Future<void> deleteSubject(int subjectId) async {
    // CASCADE: ลบบท → หัวข้อย่อย → คะแนน ของวิชานี้ตามไปทั้งหมด
    await _db.delete('subject', where: 'id = ?', whereArgs: [subjectId]);
  }

  @override
  Future<void> setChapterKind(int chapterId, ChapterKind kind) async {
    await _db.update('chapter', {'kind': kind.name},
        where: 'id = ?', whereArgs: [chapterId]);
  }

  @override
  Future<void> setSubjectColor(int subjectId, int colorIndex) async {
    await _db.update('subject', {'color': '$colorIndex'},
        where: 'id = ?', whereArgs: [subjectId]);
  }

  @override
  Future<void> setTutorMinutes(int subjectId, int minutes) async {
    await _db.update('subject', {'tutor_minutes': minutes},
        where: 'id = ?', whereArgs: [subjectId]);
  }

  @override
  Future<void> logTutor(int occurrenceId, int? chapterId, ChapterStatus status) async {
    await _db.insert('tutor_log', {
      'occurrence_id': occurrenceId,
      'chapter_id': chapterId,
      'status': status.name,
      'logged_at': DateTime.now().toIso8601String(),
    });
  }

  @override
  Future<int> tutorCount(int chapterId) async {
    final r = await _db.rawQuery(
        'SELECT COUNT(DISTINCT occurrence_id) AS n FROM tutor_log WHERE chapter_id = ?',
        [chapterId]);
    return r.first['n'] as int? ?? 0;
  }

  @override
  Future<void> setChapterStatus(int chapterId, ChapterStatus status) async {
    await _db.update('chapter', {'status': status.name},
        where: 'id = ?', whereArgs: [chapterId]);
  }

  @override
  Future<void> renameChapter(int chapterId, String name) async {
    await _db.update('chapter', {'name': name},
        where: 'id = ?', whereArgs: [chapterId]);
  }

  @override
  Future<void> renameSubtopic(int subtopicId, String name) async {
    await _db.update('subtopic', {'name': name},
        where: 'id = ?', whereArgs: [subtopicId]);
  }

  @override
  Future<List<ChapterWithTopics>> chapters(int subjectId) async {
    final chapterRows = await _db.query(
      'chapter',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'sort_order, id',
    );

    // หัวข้อย่อยทั้งวิชา (คำสั่งเดียว)
    final topicRows = await _db.rawQuery('''
      SELECT s.id, s.chapter_id, s.name, s.sort_order, s.exam_flag
      FROM subtopic s
      JOIN chapter c ON c.id = s.chapter_id
      WHERE c.subject_id = ?
      ORDER BY s.sort_order, s.id
    ''', [subjectId]);

    // คะแนนทุกรอบของวิชานี้ ตัดรอบที่เก่ากว่า cleared_at (เป็นโมฆะแล้ว) ทิ้ง
    final scoreRows = await _db.rawQuery('''
      SELECT a.id, a.subtopic_id, a.score, a.taken_at
      FROM assessment a
      JOIN subtopic s ON s.id = a.subtopic_id
      JOIN chapter c ON c.id = s.chapter_id
      WHERE c.subject_id = ?
        AND (s.cleared_at IS NULL OR a.taken_at >= s.cleared_at)
      ORDER BY a.taken_at, a.id
    ''', [subjectId]);

    // จัดกลุ่มคะแนนตามหัวข้อ: subtopicId → [คะแนน...]
    final scoresByTopic = <int, List<ScorePoint>>{};
    for (final r in scoreRows) {
      scoresByTopic.putIfAbsent(r['subtopic_id'] as int, () => []).add(
          ScorePoint(r['id'] as int, r['score'] as int,
              DateTime.parse(r['taken_at'] as String)));
    }

    final topics = [
      for (final r in topicRows)
        Subtopic(
          id: r['id'] as int,
          chapterId: r['chapter_id'] as int,
          name: r['name'] as String,
          sortOrder: r['sort_order'] as int,
          examFlag: (r['exam_flag'] as int) == 1,
          scores: scoresByTopic[r['id'] as int] ?? const [],
        ),
    ];

    return [
      for (final row in chapterRows)
        ChapterWithTopics(
          Chapter.fromRow(row),
          topics.where((t) => t.chapterId == row['id']).toList(),
        ),
    ];
  }

  @override
  Future<int> addChapter(int subjectId, String name) async {
    final next = Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COALESCE(MAX(sort_order), 0) + 1 FROM chapter WHERE subject_id = ?',
          [subjectId],
        )) ??
        1;
    return _db.insert('chapter', {
      'subject_id': subjectId,
      'name': name,
      'sort_order': next,
    });
  }

  @override
  Future<void> deleteChapter(int chapterId) async {
    // ON DELETE CASCADE ลบหัวข้อย่อยและคะแนนข้างในให้เอง
    await _db.delete('chapter', where: 'id = ?', whereArgs: [chapterId]);
  }

  @override
  Future<int> addSubtopic(int chapterId, String name) async {
    final next = Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COALESCE(MAX(sort_order), 0) + 1 FROM subtopic WHERE chapter_id = ?',
          [chapterId],
        )) ??
        1;
    return _db.insert('subtopic', {
      'chapter_id': chapterId,
      'name': name,
      'sort_order': next,
    });
  }

  @override
  Future<void> deleteSubtopic(int subtopicId) async {
    await _db.delete('subtopic', where: 'id = ?', whereArgs: [subtopicId]);
  }

  @override
  Future<void> setExamFlag(int subtopicId, bool flag) async {
    await _db.update(
      'subtopic',
      {'exam_flag': flag ? 1 : 0},
      where: 'id = ?',
      whereArgs: [subtopicId],
    );
  }

  @override
  Future<String?> getSetting(String key) async {
    final rows = await _db.query('setting',
        where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String value) async {
    // replace = มี key นี้แล้วเขียนทับ ยังไม่มีก็เพิ่มใหม่
    await _db.insert('setting', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  @override
  Future<void> resetHistoryFrom(int subtopicId, DateTime from) async {
    await _db.update(
      'subtopic',
      {'cleared_at': from.toIso8601String(), 'needs_recheck': 0},
      where: 'id = ?',
      whereArgs: [subtopicId],
    );
  }

  @override
  Future<List<ScoreRecord>> scoreHistory(int subtopicId) async {
    final rows = await _db.rawQuery('''
      SELECT a.id, a.score, a.taken_at,
        (s.cleared_at IS NOT NULL AND a.taken_at < s.cleared_at) AS voided
      FROM assessment a
      JOIN subtopic s ON s.id = a.subtopic_id
      WHERE a.subtopic_id = ?
      ORDER BY a.taken_at, a.id
    ''', [subtopicId]);
    return [
      for (final r in rows)
        ScoreRecord(
          id: r['id'] as int,
          score: r['score'] as int,
          at: DateTime.parse(r['taken_at'] as String),
          voided: (r['voided'] as int) == 1,
        ),
    ];
  }

  @override
  Future<void> updateAssessment(int assessmentId, int score) async {
    await _db.update('assessment', {'score': score},
        where: 'id = ?', whereArgs: [assessmentId]);
  }

  @override
  Future<void> deleteAssessment(int assessmentId) async {
    await _db.delete('assessment', where: 'id = ?', whereArgs: [assessmentId]);
  }

  @override
  Future<void> undoReset(int subtopicId) async {
    await _db.update('subtopic', {'cleared_at': null},
        where: 'id = ?', whereArgs: [subtopicId]);
  }

  @override
  Future<GradingMode> gradingMode() async {
    final rows = await _db.query('setting',
        where: 'key = ?', whereArgs: ['grading_mode'], limit: 1);
    final value = rows.isEmpty ? null : rows.first['value'] as String?;
    return value == 'advanced' ? GradingMode.advanced : GradingMode.ez;
  }

  @override
  Future<void> setGradingMode(GradingMode mode) async {
    // replace = ถ้ามี key นี้แล้วให้เขียนทับ ถ้ายังไม่มีให้เพิ่มใหม่
    await _db.insert(
      'setting',
      {'key': 'grading_mode', 'value': mode.name},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> addAssessment(int subtopicId, int score, {DateTime? at}) async {
    // transaction = ทำ 2 คำสั่งนี้ "สำเร็จทั้งคู่หรือไม่ทำเลย"
    await _db.transaction((txn) async {
      await txn.insert('assessment', {
        'subtopic_id': subtopicId,
        'score': score,
        'taken_at': (at ?? DateTime.now()).toIso8601String(),
      });
      await txn.update(
        'subtopic',
        {'status': 'assessed', 'needs_recheck': score < 60 ? 1 : 0},
        where: 'id = ?',
        whereArgs: [subtopicId],
      );
    });
  }
}
