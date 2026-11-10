import 'package:sqflite/sqflite.dart';

import '../study/grading.dart';
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
  Future<List<GradePart>> gradeParts(int subjectId) async {
    final parts = await _db.query('grade_part',
        where: 'subject_id = ?', whereArgs: [subjectId], orderBy: 'sort, id');
    if (parts.isEmpty) return const [];
    final ids = [for (final p in parts) p['id'] as int];
    final items = await _db.query('grade_item',
        where: 'part_id IN (${List.filled(ids.length, '?').join(',')})',
        whereArgs: ids,
        orderBy: 'sort, id');
    return [
      for (final p in parts)
        GradePart(
          id: p['id'] as int,
          name: p['name'] as String,
          weight: (p['weight'] as num).toDouble(),
          items: [
            for (final i in items.where((i) => i['part_id'] == p['id']))
              GradeItem(
                id: i['id'] as int,
                name: i['name'] as String,
                full: (i['full_score'] as num).toDouble(),
                got: (i['got_score'] as num?)?.toDouble(),
              ),
          ],
        ),
    ];
  }

  @override
  Future<int> addGradePart(int subjectId, String name, double weight,
      {int items = 1, double? itemFull}) {
    return _db.transaction((txn) async {
      final sort = Sqflite.firstIntValue(await txn.rawQuery(
              'SELECT COALESCE(MAX(sort), -1) + 1 FROM grade_part WHERE subject_id = ?',
              [subjectId])) ??
          0;
      final id = await txn.insert('grade_part',
          {'subject_id': subjectId, 'name': name, 'weight': weight, 'sort': sort});
      final n = items < 1 ? 1 : items;
      for (var k = 0; k < n; k++) {
        await txn.insert('grade_item', {
          'part_id': id,
          'name': n == 1 ? name : '$name ${k + 1}',
          'full_score': itemFull ?? weight / n,
          'sort': k,
        });
      }
      return id;
    });
  }

  @override
  Future<void> updateGradePart(int partId, {String? name, double? weight}) async {
    final v = <String, Object?>{'name': ?name, 'weight': ?weight};
    if (v.isEmpty) return;
    await _db.update('grade_part', v, where: 'id = ?', whereArgs: [partId]);
  }

  @override
  Future<void> deleteGradePart(int partId) =>
      _db.delete('grade_part', where: 'id = ?', whereArgs: [partId]);

  @override
  Future<int> addGradeItem(int partId, String name, double full) async {
    final sort = Sqflite.firstIntValue(await _db.rawQuery(
            'SELECT COALESCE(MAX(sort), -1) + 1 FROM grade_item WHERE part_id = ?', [partId])) ??
        0;
    return _db.insert('grade_item',
        {'part_id': partId, 'name': name, 'full_score': full, 'sort': sort});
  }

  @override
  Future<void> updateGradeItem(int itemId,
      {String? name, double? full, double? got, bool clearGot = false}) async {
    final v = <String, Object?>{'name': ?name, 'full_score': ?full, 'got_score': ?got};
    if (clearGot) v['got_score'] = null;
    if (v.isEmpty) return;
    await _db.update('grade_item', v, where: 'id = ?', whereArgs: [itemId]);
  }

  @override
  Future<void> deleteGradeItem(int itemId) =>
      _db.delete('grade_item', where: 'id = ?', whereArgs: [itemId]);

  @override
  Future<GradeSetup> gradeSetup(int subjectId) async {
    final rows = await _db.query('grade_setup', where: 'subject_id = ?', whereArgs: [subjectId]);
    if (rows.isEmpty) return const GradeSetup();
    final r = rows.first;
    return GradeSetup(
      scale: parseScale(r['scale'] as String?),
      flags: GradeFlags(
        absentCount: r['absent_count'] as int? ?? 0,
        classTotal: r['class_total'] as int?,
        absentLimit: (r['absent_limit'] as num?)?.toDouble() ?? 20,
        missedExam: (r['missed_exam'] as int? ?? 0) == 1,
      ),
      official: r['official'] as String?,
    );
  }

  @override
  Future<void> setGradeSetup(int subjectId, GradeSetup setup) async {
    await _db.insert(
      'grade_setup',
      {
        'subject_id': subjectId,
        'scale': encodeScale(setup.scale),
        'absent_count': setup.flags.absentCount,
        'class_total': setup.flags.classTotal,
        'absent_limit': setup.flags.absentLimit,
        'missed_exam': setup.flags.missedExam ? 1 : 0,
        'official': setup.official,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  @override
  Future<List<ClassLog>> classLogs(int subjectId) async {
    final rows = await _db.query('class_log',
        where: 'subject_id = ?', whereArgs: [subjectId], orderBy: 'day DESC, id DESC');
    return [
      for (final r in rows)
        ClassLog(
          id: r['id'] as int,
          subjectId: r['subject_id'] as int,
          occurrenceId: r['occurrence_id'] as int?,
          chapterId: r['chapter_id'] as int?,
          day: DateTime.parse(r['day'] as String),
          finished: (r['finished'] as int? ?? 0) == 1,
          note: r['note'] as String?,
        ),
    ];
  }

  @override
  Future<int> logClass(int subjectId, DateTime day,
      {int? occurrenceId, int? chapterId, bool finished = false, String? note}) async {
    final values = {
      'subject_id': subjectId,
      'occurrence_id': occurrenceId,
      'chapter_id': chapterId,
      'day': _dayText(day),
      'finished': finished ? 1 : 0,
      'note': (note == null || note.trim().isEmpty) ? null : note.trim(),
    };
    final int id;
    final old = occurrenceId == null
        ? const <Map<String, Object?>>[]
        : await _db.query('class_log', columns: ['id'], where: 'occurrence_id = ?', whereArgs: [occurrenceId]);
    if (old.isNotEmpty) {
      id = old.first['id'] as int;
      await _db.update('class_log', values, where: 'id = ?', whereArgs: [id]);
    } else {
      id = await _db.insert('class_log', values);
    }
    if (chapterId != null) await _promoteChapter(chapterId);
    return id;
  }

  /// บทที่เรียนในคาบแล้ว: ยังไม่เริ่ม → กำลังติว (รอบติวจะหยิบบทนี้ก่อน)
  Future<void> _promoteChapter(int chapterId) async {
    await _db.update('chapter', {'status': ChapterStatus.learning.name},
        where: 'id = ? AND status = ?', whereArgs: [chapterId, ChapterStatus.todo.name]);
  }

  @override
  Future<void> deleteClassLog(int logId) => _db.delete('class_log', where: 'id = ?', whereArgs: [logId]);

  String _dayText(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Future<List<SubjectLink>> subjectLinks() async {
    final rows = await _db.query('subject_link', orderBy: 'from_id, to_id');
    return [for (final r in rows) (from: r['from_id'] as int, to: r['to_id'] as int)];
  }

  @override
  Future<void> addSubjectLink(int fromId, int toId) async {
    if (fromId == toId) return;
    await _db.insert('subject_link', {'from_id': fromId, 'to_id': toId},
        conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  @override
  Future<void> removeSubjectLink(int fromId, int toId) async {
    await _db.delete('subject_link',
        where: 'from_id = ? AND to_id = ?', whereArgs: [fromId, toId]);
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
