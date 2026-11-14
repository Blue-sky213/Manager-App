/// สกิลใน SQLite (v19) · ตารางสร้างใน `createSkillV19`
library;

import 'package:sqflite/sqflite.dart';

import 'skill_models.dart';
import 'skill_repository.dart';

class SqliteSkillRepository extends SkillRepository {
  SqliteSkillRepository(this._db);
  final DatabaseExecutor _db;

  static String _d(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<int> _save(String table, int id, Map<String, Object?> row) async {
    if (id == 0) {
      id = await _db.insert(table, row);
    } else {
      await _db.update(table, row, where: 'id = ?', whereArgs: [id]);
    }
    notifyListeners();
    return id;
  }

  Future<void> _delete(String table, int id) async {
    await _db.delete(table, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  @override
  Future<List<Skill>> skills() async => [
        for (final r in await _db.query('skill', orderBy: 'id'))
          Skill(
            id: r['id'] as int,
            name: r['name'] as String,
            icon: r['icon'] as String? ?? '🎯',
            colorKey: r['color_key'] as String? ?? 'purple',
            why: r['why'] as String?,
            status: SkillStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => SkillStatus.active),
            startedAt: DateTime.parse(r['started_at'] as String),
            doneAt: r['done_at'] == null ? null : DateTime.parse(r['done_at'] as String),
          ),
      ];

  @override
  Future<int> saveSkill(Skill s) => _save('skill', s.id, {
        'name': s.name,
        'icon': s.icon,
        'color_key': s.colorKey,
        'why': s.why,
        'status': s.status.name,
        'started_at': _d(s.startedAt),
        'done_at': s.doneAt == null ? null : _d(s.doneAt!),
      });

  @override
  Future<void> deleteSkill(int id) async {
    // FK ON DELETE CASCADE ลบเป้า / บันทึก / ผลงาน / รีวิว / การผูกงานให้
    await _db.delete('skill', where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  @override
  Future<List<SkillGoal>> goals(int skillId) async => [
        for (final r in await _db.query('skill_goal', where: 'skill_id = ?', whereArgs: [skillId], orderBy: 'id'))
          SkillGoal(
            id: r['id'] as int,
            skillId: skillId,
            kind: GoalKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => GoalKind.milestone),
            title: r['title'] as String,
            unit: r['unit'] as String? ?? '',
            target: (r['target'] as num?)?.toDouble() ?? 0,
            streak: r['streak'] as int? ?? 3,
            status: GoalStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => GoalStatus.active),
            steps: SkillGoal.stepsFrom(r['steps'] as String?),
          ),
      ];

  @override
  Future<int> saveGoal(SkillGoal g) => _save('skill_goal', g.id, {
        'skill_id': g.skillId,
        'kind': g.kind.name,
        'title': g.title,
        'unit': g.unit,
        'target': g.target,
        'streak': g.streak,
        'status': g.status.name,
        'steps': g.stepsJson(),
      });

  @override
  Future<void> deleteGoal(int id) => _delete('skill_goal', id);

  @override
  Future<List<SkillLog>> logs(int skillId) async => [
        for (final r in await _db.query('skill_log', where: 'skill_id = ?', whereArgs: [skillId], orderBy: 'day DESC, id DESC'))
          SkillLog(
            id: r['id'] as int,
            skillId: skillId,
            goalId: r['goal_id'] as int?,
            day: DateTime.parse(r['day'] as String),
            minutes: r['minutes'] as int?,
            value: (r['value'] as num?)?.toDouble(),
            rating: r['rating'] as int?,
            better: r['better'] as String?,
            stuck: r['stuck'] as String?,
            next: r['next'] as String?,
            skipped: (r['skipped'] as int? ?? 0) == 1,
            occurrenceId: r['occurrence_id'] as int?,
          ),
      ];

  @override
  Future<int> saveLog(SkillLog l) => _save('skill_log', l.id, {
        'skill_id': l.skillId,
        'goal_id': l.goalId,
        'day': _d(l.day),
        'minutes': l.minutes,
        'value': l.value,
        'rating': l.rating,
        'better': l.better,
        'stuck': l.stuck,
        'next': l.next,
        'skipped': l.skipped ? 1 : 0,
        'occurrence_id': l.occurrenceId,
      });

  @override
  Future<void> deleteLog(int id) => _delete('skill_log', id);

  @override
  Future<List<SkillFile>> files(int skillId) async => [
        for (final r in await _db.query('skill_file', where: 'skill_id = ?', whereArgs: [skillId], orderBy: 'added_at DESC, id DESC'))
          SkillFile(
            id: r['id'] as int,
            skillId: skillId,
            logId: r['log_id'] as int?,
            kind: SkillFileKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => SkillFileKind.file),
            path: r['path'] as String,
            title: r['title'] as String,
            featured: (r['featured'] as int? ?? 0) == 1,
            addedAt: DateTime.parse(r['added_at'] as String),
          ),
      ];

  @override
  Future<int> saveFile(SkillFile f) => _save('skill_file', f.id, {
        'skill_id': f.skillId,
        'log_id': f.logId,
        'kind': f.kind.name,
        'path': f.path,
        'title': f.title,
        'featured': f.featured ? 1 : 0,
        'added_at': f.addedAt.toIso8601String(),
      });

  @override
  Future<void> deleteFile(int id) => _delete('skill_file', id);

  @override
  Future<SkillReview?> review(int skillId, String month) async {
    final r = (await _db.query('skill_review', where: 'skill_id = ? AND month = ?', whereArgs: [skillId, month])).firstOrNull;
    return r == null
        ? null
        : SkillReview(
            skillId: skillId, month: month, can: r['can'] as String?, weak: r['weak'] as String?, nextGoal: r['next_goal'] as String?);
  }

  @override
  Future<void> saveReview(SkillReview r) async {
    await _db.insert(
      'skill_review',
      {'skill_id': r.skillId, 'month': r.month, 'can': r.can, 'weak': r.weak, 'next_goal': r.nextGoal},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    notifyListeners();
  }

  @override
  Future<void> linkActivity(int skillId, int activityId) async {
    await _db.insert('skill_activity', {'activity_id': activityId, 'skill_id': skillId},
        conflictAlgorithm: ConflictAlgorithm.replace);
    notifyListeners();
  }

  @override
  Future<int?> skillOfActivity(int activityId) async =>
      (await _db.query('skill_activity', where: 'activity_id = ?', whereArgs: [activityId])).firstOrNull?['skill_id'] as int?;

  @override
  Future<List<int>> activitiesOf(int skillId) async => [
        for (final r in await _db.query('skill_activity', where: 'skill_id = ?', whereArgs: [skillId])) r['activity_id'] as int,
      ];
}
