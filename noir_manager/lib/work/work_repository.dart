/// ที่เก็บข้อมูลเมนู "งาน" (รอบ 8D การเงิน · 8E โปรเจกต์) · RAM + SQLite
/// เข้าถึงผ่าน `CalendarRepository.workRepo`
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'money_models.dart';
import 'project_models.dart';

abstract class WorkRepository extends ChangeNotifier {
  /// รายการเงินในช่วง (รวมทั้งสองวัน)
  Future<List<MoneyEntry>> entries(DateTime from, DateTime to);
  Future<int> saveEntry(MoneyEntry e);
  Future<void> deleteEntry(int id);

  Future<List<Subscription>> subscriptions();
  Future<int> saveSubscription(Subscription s);
  Future<void> deleteSubscription(int id);

  Future<List<Investment>> investments();
  Future<int> saveInvestment(Investment i);
  Future<void> deleteInvestment(int id);

  // ---------- โปรเจกต์ (รอบ 8E · v21) ----------
  Future<List<Project>> projects();
  Future<int> saveProject(Project p);

  /// ลบโปรเจกต์ + ทีม + ขั้นงาน + งวด + ไฟล์ · รายการเงินยังอยู่ (แค่ไม่ผูก)
  Future<void> deleteProject(int id);
  Future<List<ProjectMember>> members(int projectId);
  Future<int> saveMember(ProjectMember m);
  Future<void> deleteMember(int id);
  Future<List<ProjectTask>> tasks(int projectId);
  Future<int> saveTask(ProjectTask t);
  Future<void> deleteTask(int id);
  Future<List<ProjectPayment>> payments(int projectId);
  Future<int> savePayment(ProjectPayment p);
  Future<void> deletePayment(int id);
  Future<List<ProjectFile>> projectFiles(int projectId);
  Future<int> saveProjectFile(ProjectFile f);
  Future<void> deleteProjectFile(int id);
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

class MemoryWorkRepository extends WorkRepository {
  int _next = 1;
  final _entries = <int, MoneyEntry>{};
  final _subs = <int, Subscription>{};
  final _invs = <int, Investment>{};

  int _id(int id) => id == 0 ? _next++ : id;

  @override
  Future<List<MoneyEntry>> entries(DateTime from, DateTime to) async => _entries.values
      .where((e) => !e.day.isBefore(_day(from)) && !e.day.isAfter(_day(to)))
      .toList()
    ..sort((a, b) => a.day != b.day ? b.day.compareTo(a.day) : b.id - a.id);

  @override
  Future<int> saveEntry(MoneyEntry e) async {
    final id = _id(e.id);
    _entries[id] = MoneyEntry(
        id: id,
        day: _day(e.day),
        kind: e.kind,
        amount: e.amount,
        category: e.category,
        note: e.note,
        projectId: e.projectId,
        investmentId: e.investmentId,
        subscriptionId: e.subscriptionId);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteEntry(int id) async {
    _entries.remove(id);
    notifyListeners();
  }

  @override
  Future<List<Subscription>> subscriptions() async => _subs.values.toList()..sort((a, b) => a.billDay - b.billDay);

  @override
  Future<int> saveSubscription(Subscription s) async {
    final id = _id(s.id);
    _subs[id] = Subscription(
        id: id, name: s.name, amount: s.amount, cycle: s.cycle, billDay: s.billDay, billMonth: s.billMonth, active: s.active);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteSubscription(int id) async {
    _subs.remove(id);
    notifyListeners();
  }

  @override
  Future<List<Investment>> investments() async => _invs.values.toList()..sort((a, b) => a.id - b.id);

  @override
  Future<int> saveInvestment(Investment i) async {
    final id = _id(i.id);
    _invs[id] = Investment(id: id, name: i.name, amount: i.amount, startDay: i.startDay, note: i.note);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteInvestment(int id) async {
    _invs.remove(id);
    // รายรับที่เคยผูกไว้ยังอยู่ (แค่ไม่ผูกแล้ว)
    for (final e in _entries.values.where((e) => e.investmentId == id).toList()) {
      _entries[e.id] = MoneyEntry(
          id: e.id, day: e.day, kind: e.kind, amount: e.amount, category: e.category, note: e.note, projectId: e.projectId, subscriptionId: e.subscriptionId);
    }
    notifyListeners();
  }

  final _projects = <int, Project>{};
  final _members = <int, ProjectMember>{};
  final _tasks = <int, ProjectTask>{};
  final _payments = <int, ProjectPayment>{};
  final _pfiles = <int, ProjectFile>{};

  @override
  Future<List<Project>> projects() async => _projects.values.toList()..sort((a, b) => a.id - b.id);

  @override
  Future<int> saveProject(Project p) async {
    final id = _id(p.id);
    _projects[id] = Project(
        id: id,
        name: p.name,
        client: p.client,
        type: p.type,
        status: p.status,
        price: p.price,
        start: p.start,
        due: p.due,
        travelMinutes: p.travelMinutes,
        note: p.note);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteProject(int id) async {
    _projects.remove(id);
    _members.removeWhere((_, x) => x.projectId == id);
    _tasks.removeWhere((_, x) => x.projectId == id);
    _payments.removeWhere((_, x) => x.projectId == id);
    _pfiles.removeWhere((_, x) => x.projectId == id);
    for (final e in _entries.values.where((e) => e.projectId == id).toList()) {
      _entries[e.id] = MoneyEntry(
          id: e.id, day: e.day, kind: e.kind, amount: e.amount, category: e.category, note: e.note, investmentId: e.investmentId, subscriptionId: e.subscriptionId);
    }
    notifyListeners();
  }

  @override
  Future<List<ProjectMember>> members(int projectId) async => _members.values.where((x) => x.projectId == projectId).toList()..sort((a, b) => a.id - b.id);

  @override
  Future<int> saveMember(ProjectMember m) async {
    final id = _id(m.id);
    _members[id] = ProjectMember(id: id, projectId: m.projectId, name: m.name, role: m.role, duty: m.duty);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteMember(int id) async {
    _members.remove(id);
    notifyListeners();
  }

  @override
  Future<List<ProjectTask>> tasks(int projectId) async => _tasks.values.where((x) => x.projectId == projectId).toList()..sort((a, b) => a.id - b.id);

  @override
  Future<int> saveTask(ProjectTask t) async {
    final id = _id(t.id);
    _tasks[id] = ProjectTask(id: id, projectId: t.projectId, title: t.title, owner: t.owner, due: t.due, done: t.done, activityId: t.activityId);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteTask(int id) async {
    _tasks.remove(id);
    notifyListeners();
  }

  @override
  Future<List<ProjectPayment>> payments(int projectId) async => _payments.values.where((x) => x.projectId == projectId).toList()..sort((a, b) => a.id - b.id);

  @override
  Future<int> savePayment(ProjectPayment p) async {
    final id = _id(p.id);
    _payments[id] = ProjectPayment(
        id: id, projectId: p.projectId, label: p.label, amount: p.amount, condition: p.condition, due: p.due, entryId: p.entryId);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deletePayment(int id) async {
    _payments.remove(id);
    notifyListeners();
  }

  @override
  Future<List<ProjectFile>> projectFiles(int projectId) async =>
      _pfiles.values.where((x) => x.projectId == projectId).toList()..sort((a, b) => b.addedAt.compareTo(a.addedAt));

  @override
  Future<int> saveProjectFile(ProjectFile f) async {
    final id = _id(f.id);
    _pfiles[id] = ProjectFile(id: id, projectId: f.projectId, kind: f.kind, path: f.path, title: f.title, addedAt: f.addedAt);
    notifyListeners();
    return id;
  }

  @override
  Future<void> deleteProjectFile(int id) async {
    _pfiles.remove(id);
    notifyListeners();
  }
}

class SqliteWorkRepository extends WorkRepository {
  SqliteWorkRepository(this._db);
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
  Future<List<MoneyEntry>> entries(DateTime from, DateTime to) async => [
        for (final r in await _db.query('money_entry',
            where: 'day >= ? AND day <= ?', whereArgs: [_d(from), _d(to)], orderBy: 'day DESC, id DESC'))
          MoneyEntry(
            id: r['id'] as int,
            day: DateTime.parse(r['day'] as String),
            kind: r['kind'] == 'income' ? MoneyKind.income : MoneyKind.expense,
            amount: (r['amount'] as num).toDouble(),
            category: r['category'] as String,
            note: r['note'] as String?,
            projectId: r['project_id'] as int?,
            investmentId: r['investment_id'] as int?,
            subscriptionId: r['subscription_id'] as int?,
          ),
      ];

  @override
  Future<int> saveEntry(MoneyEntry e) => _save('money_entry', e.id, {
        'day': _d(e.day),
        'kind': e.kind.name,
        'amount': e.amount,
        'category': e.category,
        'note': e.note,
        'project_id': e.projectId,
        'investment_id': e.investmentId,
        'subscription_id': e.subscriptionId,
      });

  @override
  Future<void> deleteEntry(int id) => _delete('money_entry', id);

  @override
  Future<List<Subscription>> subscriptions() async => [
        for (final r in await _db.query('subscription', orderBy: 'bill_day, id'))
          Subscription(
            id: r['id'] as int,
            name: r['name'] as String,
            amount: (r['amount'] as num?)?.toDouble(),
            cycle: r['cycle'] == 'yearly' ? BillCycle.yearly : BillCycle.monthly,
            billDay: r['bill_day'] as int? ?? 1,
            billMonth: r['bill_month'] as int?,
            active: (r['active'] as int? ?? 1) == 1,
          ),
      ];

  @override
  Future<int> saveSubscription(Subscription s) => _save('subscription', s.id, {
        'name': s.name,
        'amount': s.amount,
        'cycle': s.cycle.name,
        'bill_day': s.billDay,
        'bill_month': s.billMonth,
        'active': s.active ? 1 : 0,
      });

  @override
  Future<void> deleteSubscription(int id) => _delete('subscription', id);

  @override
  Future<List<Investment>> investments() async => [
        for (final r in await _db.query('investment', orderBy: 'id'))
          Investment(
            id: r['id'] as int,
            name: r['name'] as String,
            amount: (r['amount'] as num).toDouble(),
            startDay: DateTime.parse(r['start_day'] as String),
            note: r['note'] as String?,
          ),
      ];

  @override
  Future<int> saveInvestment(Investment i) =>
      _save('investment', i.id, {'name': i.name, 'amount': i.amount, 'start_day': _d(i.startDay), 'note': i.note});

  @override
  Future<void> deleteInvestment(int id) => _delete('investment', id);

  // ---------- โปรเจกต์ (v21) ----------
  static DateTime? _date(Object? v) => v == null ? null : DateTime.parse(v as String);
  static String? _dn(DateTime? d) => d == null ? null : _d(d);

  @override
  Future<List<Project>> projects() async => [
        for (final r in await _db.query('project', orderBy: 'id'))
          Project(
            id: r['id'] as int,
            name: r['name'] as String,
            client: r['client'] as String?,
            type: r['type'] as String? ?? 'other',
            status: ProjectStatus.values.firstWhere((s) => s.name == r['status'], orElse: () => ProjectStatus.quote),
            price: (r['price'] as num?)?.toDouble(),
            start: _date(r['start_day']),
            due: _date(r['due_day']),
            travelMinutes: r['travel_minutes'] as int?,
            note: r['note'] as String?,
          ),
      ];

  @override
  Future<int> saveProject(Project p) => _save('project', p.id, {
        'name': p.name,
        'client': p.client,
        'type': p.type,
        'status': p.status.name,
        'price': p.price,
        'start_day': _dn(p.start),
        'due_day': _dn(p.due),
        'travel_minutes': p.travelMinutes,
        'note': p.note,
      });

  @override
  Future<void> deleteProject(int id) async {
    // FK CASCADE ลบทีม / ขั้นงาน / งวด / ไฟล์ · รายการเงินแค่ไม่ผูก
    await _db.update('money_entry', {'project_id': null}, where: 'project_id = ?', whereArgs: [id]);
    await _delete('project', id);
  }

  @override
  Future<List<ProjectMember>> members(int projectId) async => [
        for (final r in await _db.query('project_member', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'id'))
          ProjectMember(id: r['id'] as int, projectId: projectId, name: r['name'] as String, role: r['role'] as String?, duty: r['duty'] as String?),
      ];

  @override
  Future<int> saveMember(ProjectMember m) =>
      _save('project_member', m.id, {'project_id': m.projectId, 'name': m.name, 'role': m.role, 'duty': m.duty});

  @override
  Future<void> deleteMember(int id) => _delete('project_member', id);

  @override
  Future<List<ProjectTask>> tasks(int projectId) async => [
        for (final r in await _db.query('project_task', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'id'))
          ProjectTask(
            id: r['id'] as int,
            projectId: projectId,
            title: r['title'] as String,
            owner: r['owner'] as String?,
            due: _date(r['due_day']),
            done: (r['done'] as int? ?? 0) == 1,
            activityId: r['activity_id'] as int?,
          ),
      ];

  @override
  Future<int> saveTask(ProjectTask t) => _save('project_task', t.id, {
        'project_id': t.projectId,
        'title': t.title,
        'owner': t.owner,
        'due_day': _dn(t.due),
        'done': t.done ? 1 : 0,
        'activity_id': t.activityId,
      });

  @override
  Future<void> deleteTask(int id) => _delete('project_task', id);

  @override
  Future<List<ProjectPayment>> payments(int projectId) async => [
        for (final r in await _db.query('project_payment', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'id'))
          ProjectPayment(
            id: r['id'] as int,
            projectId: projectId,
            label: r['label'] as String,
            amount: (r['amount'] as num).toDouble(),
            condition: r['condition'] as String?,
            due: _date(r['due_day']),
            entryId: r['entry_id'] as int?,
          ),
      ];

  @override
  Future<int> savePayment(ProjectPayment p) => _save('project_payment', p.id, {
        'project_id': p.projectId,
        'label': p.label,
        'amount': p.amount,
        'condition': p.condition,
        'due_day': _dn(p.due),
        'entry_id': p.entryId,
      });

  @override
  Future<void> deletePayment(int id) => _delete('project_payment', id);

  @override
  Future<List<ProjectFile>> projectFiles(int projectId) async => [
        for (final r in await _db.query('project_file', where: 'project_id = ?', whereArgs: [projectId], orderBy: 'added_at DESC, id DESC'))
          ProjectFile(
            id: r['id'] as int,
            projectId: projectId,
            kind: ProjectFileKind.values.firstWhere((k) => k.name == r['kind'], orElse: () => ProjectFileKind.file),
            path: r['path'] as String,
            title: r['title'] as String,
            addedAt: DateTime.parse(r['added_at'] as String),
          ),
      ];

  @override
  Future<int> saveProjectFile(ProjectFile f) => _save('project_file', f.id, {
        'project_id': f.projectId,
        'kind': f.kind.name,
        'path': f.path,
        'title': f.title,
        'added_at': f.addedAt.toIso8601String(),
      });

  @override
  Future<void> deleteProjectFile(int id) => _delete('project_file', id);
}
