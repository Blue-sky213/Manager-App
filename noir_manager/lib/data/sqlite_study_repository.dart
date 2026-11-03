import 'package:sqflite/sqflite.dart';

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
  Future<List<ChapterWithTopics>> chapters(int subjectId) async {
    final chapterRows = await _db.query(
      'chapter',
      where: 'subject_id = ?',
      whereArgs: [subjectId],
      orderBy: 'sort_order, id',
    );

    // ดึงหัวข้อย่อยทั้งวิชาในคำสั่งเดียว พร้อมคำนวณ "คะแนนล่าสุด" และ "เคยต่ำกว่า 60"
    final topicRows = await _db.rawQuery('''
      SELECT s.id, s.chapter_id, s.name, s.sort_order, s.exam_flag,
        (SELECT a.score FROM assessment a
          WHERE a.subtopic_id = s.id
          ORDER BY a.taken_at DESC, a.id DESC
          LIMIT 1) AS latest_score,
        EXISTS (SELECT 1 FROM assessment a
          WHERE a.subtopic_id = s.id AND a.score < 60) AS ever_below
      FROM subtopic s
      JOIN chapter c ON c.id = s.chapter_id
      WHERE c.subject_id = ?
      ORDER BY s.sort_order, s.id
    ''', [subjectId]);

    final topics = topicRows.map(Subtopic.fromRow).toList();

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
