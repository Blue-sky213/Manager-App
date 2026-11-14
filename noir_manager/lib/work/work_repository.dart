/// ที่เก็บข้อมูลเมนู "งาน" (รอบ 8D การเงิน · 8E โปรเจกต์) · RAM + SQLite
/// เข้าถึงผ่าน `CalendarRepository.workRepo`
library;

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import 'money_models.dart';

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
}
