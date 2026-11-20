/// ที่เก็บข้อมูลสกิล (รอบ 8C) · RAM (เทส / โหมดตัวอย่าง) + SQLite (ของจริง · v19)
/// เข้าถึงผ่าน `CalendarRepository.skillRepo` (งานฝึกผูกกับงานในปฏิทิน)
library;

import 'package:flutter/foundation.dart';

import 'skill_models.dart';

abstract class SkillRepository extends ChangeNotifier {
  /// ข้อมูลเปลี่ยนจากภายนอก (ซิงก์บัญชี) → ให้หน้าที่ฟังอยู่โหลดใหม่
  void refresh() => notifyListeners();

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

  // ---- แผนผัง (รอบ 9B · v22) ----
  Future<List<SkillBranch>> branches();
  Future<int> saveBranch(SkillBranch b);

  /// ลบสาย · สกิลในสายไม่ถูกลบ (กลายเป็น "ยังไม่จัดสาย")
  Future<void> deleteBranch(int id);

  /// ทักษะย่อยทุกสกิล (เรียงตาม sort)
  Future<List<SkillNode>> nodes();
  Future<int> saveNode(SkillNode n);
  Future<void> deleteNode(int id);

  /// หัวข้อทุกบท (มีประวัติคะแนน) · รอบ 13 · v23
  Future<List<SkillTopic>> topics();
  Future<int> saveTopic(SkillTopic t);
  Future<void> deleteTopic(int id);
  Future<void> addTopicScore(int topicId, int score, {DateTime? at});

  Future<List<SkillNeed>> needs();
  Future<void> addNeed(int skillId, int needId);
  Future<void> removeNeed(int skillId, int needId);
}

class MemorySkillRepository extends SkillRepository {
  int _next = 1;
  final _skills = <int, Skill>{};
  final _goals = <int, SkillGoal>{};
  final _logs = <int, SkillLog>{};
  final _files = <int, SkillFile>{};
  final _reviews = <String, SkillReview>{};
  final _links = <int, int>{}; // activityId → skillId
  final _branches = <int, SkillBranch>{};
  final _nodes = <int, SkillNode>{};
  final _topics = <int, SkillTopic>{};
  final _needs = <SkillNeed>[];

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
        id: id,
        branchId: s.branchId,
        name: s.name,
        icon: s.icon,
        colorKey: s.colorKey,
        why: s.why,
        status: s.status,
        startedAt: s.startedAt,
        doneAt: s.doneAt);
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
    final gone = {for (final n in _nodes.values) if (n.skillId == id) n.id};
    _nodes.removeWhere((_, n) => n.skillId == id);
    _topics.removeWhere((_, t) => gone.contains(t.nodeId));
    _needs.removeWhere((n) => n.skillId == id || n.needId == id);
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

  @override
  Future<List<SkillBranch>> branches() async =>
      _branches.values.toList()..sort((a, b) => a.sort != b.sort ? a.sort - b.sort : a.id - b.id);

  @override
  Future<int> saveBranch(SkillBranch b) async {
    final id = b.id == 0 ? _next++ : b.id;
    _branches[id] = SkillBranch(id: id, name: b.name, icon: b.icon, colorKey: b.colorKey, sort: b.sort);
    return _done(id);
  }

  @override
  Future<void> deleteBranch(int id) async {
    _branches.remove(id);
    for (final s in _skills.values.where((s) => s.branchId == id).toList()) {
      _skills[s.id] = s.copyWith(clearBranch: true);
    }
    notifyListeners();
  }

  @override
  Future<List<SkillNode>> nodes() async =>
      _nodes.values.toList()..sort((a, b) => a.sort != b.sort ? a.sort - b.sort : a.id - b.id);

  @override
  Future<int> saveNode(SkillNode n) async {
    final id = n.id == 0 ? _next++ : n.id;
    _nodes[id] = SkillNode(id: id, skillId: n.skillId, name: n.name, sort: n.sort, done: n.done, url: n.url);
    return _done(id);
  }

  @override
  Future<void> deleteNode(int id) async {
    _nodes.remove(id);
    _topics.removeWhere((_, t) => t.nodeId == id);
    notifyListeners();
  }

  @override
  Future<List<SkillTopic>> topics() async =>
      _topics.values.toList()..sort((a, b) => a.sort != b.sort ? a.sort - b.sort : a.id - b.id);

  @override
  Future<int> saveTopic(SkillTopic t) async {
    final id = t.id == 0 ? _next++ : t.id;
    _topics[id] = SkillTopic(
        id: id, nodeId: t.nodeId, name: t.name, sort: t.sort, url: t.url, note: t.note, scores: _topics[id]?.scores ?? t.scores);
    return _done(id);
  }

  @override
  Future<void> deleteTopic(int id) async {
    _topics.remove(id);
    notifyListeners();
  }

  @override
  Future<void> addTopicScore(int topicId, int score, {DateTime? at}) async {
    final t = _topics[topicId];
    if (t == null) return;
    _topics[topicId] = SkillTopic(
        id: t.id,
        nodeId: t.nodeId,
        name: t.name,
        sort: t.sort,
        url: t.url,
        note: t.note,
        scores: [...t.scores, TopicScore(score.clamp(0, 100), at ?? DateTime.now(), id: _next++)]);
    notifyListeners();
  }

  @override
  Future<List<SkillNeed>> needs() async => List.of(_needs);

  @override
  Future<void> addNeed(int skillId, int needId) async {
    if (_needs.any((n) => n.skillId == skillId && n.needId == needId)) return;
    _needs.add(SkillNeed(skillId, needId));
    notifyListeners();
  }

  @override
  Future<void> removeNeed(int skillId, int needId) async {
    _needs.removeWhere((n) => n.skillId == skillId && n.needId == needId);
    notifyListeners();
  }
}
