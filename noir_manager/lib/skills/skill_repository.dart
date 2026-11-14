/// ที่เก็บข้อมูลสกิล (รอบ 8C) · RAM (เทส / โหมดตัวอย่าง) + SQLite (ของจริง · v19)
/// เข้าถึงผ่าน `CalendarRepository.skillRepo` (งานฝึกผูกกับงานในปฏิทิน)
library;

import 'package:flutter/foundation.dart';

import 'skill_models.dart';

abstract class SkillRepository extends ChangeNotifier {
  Future<List<Skill>> skills();

  /// id = 0 → เพิ่มใหม่ · คืน id
  Future<int> saveSkill(Skill s);

  /// ลบสกิล + เป้า + บันทึก + ผลงาน + การผูกงาน (งานในปฏิทินไม่ถูกลบ)
  Future<void> deleteSkill(int id);

  Future<List<SkillGoal>> goals(int skillId);
  Future<int> saveGoal(SkillGoal g);
  Future<void> deleteGoal(int id);

  /// ใหม่ → เก่า
  Future<List<SkillLog>> logs(int skillId);
  Future<int> saveLog(SkillLog l);
  Future<void> deleteLog(int id);

  Future<List<SkillFile>> files(int skillId);
  Future<int> saveFile(SkillFile f);
  Future<void> deleteFile(int id);

  Future<SkillReview?> review(int skillId, String month);
  Future<void> saveReview(SkillReview r);

  /// งานในปฏิทินที่เป็น "ช่วงฝึก" ของสกิลนี้
  Future<void> linkActivity(int skillId, int activityId);
  Future<int?> skillOfActivity(int activityId);
  Future<List<int>> activitiesOf(int skillId);
}

class MemorySkillRepository extends SkillRepository {
  int _next = 1;
  final _skills = <int, Skill>{};
  final _goals = <int, SkillGoal>{};
  final _logs = <int, SkillLog>{};
  final _files = <int, SkillFile>{};
  final _reviews = <String, SkillReview>{};
  final _links = <int, int>{}; // activityId → skillId

  T _done<T>(T v) {
    notifyListeners();
    return v;
  }

  @override
  Future<List<Skill>> skills() async => _skills.values.toList()..sort((a, b) => a.id - b.id);

  @override
  Future<int> saveSkill(Skill s) async {
    final id = s.id == 0 ? _next++ : s.id;
    _skills[id] = Skill(
        id: id, name: s.name, icon: s.icon, colorKey: s.colorKey, why: s.why, status: s.status, startedAt: s.startedAt, doneAt: s.doneAt);
    return _done(id);
  }

  @override
  Future<void> deleteSkill(int id) async {
    _skills.remove(id);
    _goals.removeWhere((_, g) => g.skillId == id);
    _logs.removeWhere((_, l) => l.skillId == id);
    _files.removeWhere((_, f) => f.skillId == id);
    _reviews.removeWhere((_, r) => r.skillId == id);
    _links.removeWhere((_, s) => s == id);
    notifyListeners();
  }

  @override
  Future<List<SkillGoal>> goals(int skillId) async => _goals.values.where((g) => g.skillId == skillId).toList()..sort((a, b) => a.id - b.id);

  @override
  Future<int> saveGoal(SkillGoal g) async {
    final id = g.id == 0 ? _next++ : g.id;
    _goals[id] = SkillGoal(
        id: id,
        skillId: g.skillId,
        kind: g.kind,
        title: g.title,
        unit: g.unit,
        target: g.target,
        streak: g.streak,
        status: g.status,
        steps: g.steps);
    return _done(id);
  }

  @override
  Future<void> deleteGoal(int id) async {
    _goals.remove(id);
    notifyListeners();
  }

  @override
  Future<List<SkillLog>> logs(int skillId) async => _logs.values.where((l) => l.skillId == skillId).toList()
    ..sort((a, b) => a.day != b.day ? b.day.compareTo(a.day) : b.id - a.id);

  @override
  Future<int> saveLog(SkillLog l) async {
    final id = l.id == 0 ? _next++ : l.id;
    _logs[id] = SkillLog(
        id: id,
        skillId: l.skillId,
        goalId: l.goalId,
        day: l.day,
        minutes: l.minutes,
        value: l.value,
        rating: l.rating,
        better: l.better,
        stuck: l.stuck,
        next: l.next,
        skipped: l.skipped,
        occurrenceId: l.occurrenceId);
    return _done(id);
  }

  @override
  Future<void> deleteLog(int id) async {
    _logs.remove(id);
    _files.removeWhere((_, f) => f.logId == id);
    notifyListeners();
  }

  @override
  Future<List<SkillFile>> files(int skillId) async =>
      _files.values.where((f) => f.skillId == skillId).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  @override
  Future<int> saveFile(SkillFile f) async {
    final id = f.id == 0 ? _next++ : f.id;
    _files[id] = SkillFile(
        id: id,
        skillId: f.skillId,
        logId: f.logId,
        kind: f.kind,
        path: f.path,
        title: f.title,
        featured: f.featured,
        addedAt: f.addedAt);
    return _done(id);
  }

  @override
  Future<void> deleteFile(int id) async {
    _files.remove(id);
    notifyListeners();
  }

  @override
  Future<SkillReview?> review(int skillId, String month) async => _reviews['$skillId:$month'];

  @override
  Future<void> saveReview(SkillReview r) async {
    _reviews['${r.skillId}:${r.month}'] = r;
    notifyListeners();
  }

  @override
  Future<void> linkActivity(int skillId, int activityId) async {
    _links[activityId] = skillId;
    notifyListeners();
  }

  @override
  Future<int?> skillOfActivity(int activityId) async => _links[activityId];

  @override
  Future<List<int>> activitiesOf(int skillId) async => [for (final e in _links.entries) if (e.value == skillId) e.key];
}
