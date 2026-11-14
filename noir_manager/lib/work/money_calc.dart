/// คิดเงิน (ไม่มี UI · เทสได้ตรง ๆ)
library;

import 'money_models.dart';

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
bool _inMonth(DateTime d, DateTime month) => d.year == month.year && d.month == month.month;

class MonthSummary {
  const MonthSummary(this.income, this.expense, this.byCategory);
  final double income;
  final double expense;

  /// หมวดรายจ่าย → ยอด (มาก → น้อย)
  final List<(String, double)> byCategory;
  double get net => income - expense;
}

MonthSummary monthSummary(Iterable<MoneyEntry> entries, DateTime month) {
  var inc = 0.0, exp = 0.0;
  final cats = <String, double>{};
  for (final e in entries) {
    if (!_inMonth(e.day, month)) continue;
    if (e.kind == MoneyKind.income) {
      inc += e.amount;
    } else {
      exp += e.amount;
      cats[e.category] = (cats[e.category] ?? 0) + e.amount;
    }
  }
  final list = [for (final e in cats.entries) (e.key, e.value)]..sort((a, b) => b.$2.compareTo(a.$2));
  return MonthSummary(inc, exp, list);
}

/// วันตัดเงินของ [sub] ในเดือน [month] · รายปีที่ไม่ใช่เดือนนั้น = null
DateTime? billDateIn(Subscription sub, DateTime month) {
  if (sub.cycle == BillCycle.yearly && sub.billMonth != month.month) return null;
  final last = DateTime(month.year, month.month + 1, 0).day;
  return DateTime(month.year, month.month, sub.billDay.clamp(1, last));
}

enum BillState { paid, changed, overdue, dueSoon, later, notThisMonth }

/// สถานะค่าบริการเดือนนี้: จ่ายแล้ว (ยอดเปลี่ยน = ส้ม) · เลยกำหนด · ใกล้ตัด (≤ 3 วัน) · ยังไม่ถึง
(BillState, MoneyEntry?) billState(Subscription sub, Iterable<MoneyEntry> entries, DateTime month, DateTime today) {
  final paid = entries.where((e) => e.subscriptionId == sub.id && _inMonth(e.day, month)).firstOrNull;
  if (paid != null) {
    final changed = sub.amount != null && (paid.amount - sub.amount!).abs() > 0.009;
    return (changed ? BillState.changed : BillState.paid, paid);
  }
  final due = billDateIn(sub, month);
  if (due == null) return (BillState.notThisMonth, null);
  final t = _day(today);
  if (t.isAfter(due)) return (BillState.overdue, null);
  if (due.difference(t).inDays <= 3) return (BillState.dueSoon, null);
  return (BillState.later, null);
}

/// ค่าบริการรวมต่อเดือน (ที่เปิดอยู่)
double subscriptionsPerMonth(Iterable<Subscription> subs) => subs.where((s) => s.active).fold(0, (a, s) => a + s.perMonth);

class Payback {
  const Payback(this.returned, this.ratio, this.eta);
  final double returned;
  final double ratio;

  /// คาดว่าคืนทุนเดือนไหน (ตามรายรับเฉลี่ย 3 เดือนล่าสุด) · null = ยังคาดไม่ได้ / คืนแล้ว
  final DateTime? eta;
}

Payback paybackOf(Investment inv, Iterable<MoneyEntry> entries, DateTime today) {
  final mine = entries.where((e) => e.investmentId == inv.id && e.kind == MoneyKind.income).toList();
  final returned = mine.fold(0.0, (a, e) => a + e.amount);
  final ratio = inv.amount <= 0 ? 1.0 : (returned / inv.amount).clamp(0, 1).toDouble();
  if (returned >= inv.amount) return Payback(returned, 1, null);
  final from = DateTime(today.year, today.month - 2, 1);
  final recent = mine.where((e) => !e.day.isBefore(from)).fold(0.0, (a, e) => a + e.amount) / 3;
  if (recent <= 0) return Payback(returned, ratio, null);
  final months = ((inv.amount - returned) / recent).ceil();
  return Payback(returned, ratio, DateTime(today.year, today.month + months, 1));
}

/// 6 เดือนล่าสุด (เก่า → ใหม่): (เดือน, รายรับ, รายจ่าย)
List<(DateTime, double, double)> lastMonths(Iterable<MoneyEntry> entries, DateTime month, {int n = 6}) => [
      for (var i = n - 1; i >= 0; i--)
        () {
          final m = DateTime(month.year, month.month - i, 1);
          final s = monthSummary(entries, m);
          return (m, s.income, s.expense);
        }(),
    ];

String baht(double v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}฿$b';
}

/// CSV (Excel / โปรแกรมบัญชี) · 1 แถว = 1 รายการ
String moneyCsv(Iterable<MoneyEntry> entries) {
  String q(String s) => s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
  String d(DateTime x) => '${x.year}-${x.month.toString().padLeft(2, '0')}-${x.day.toString().padLeft(2, '0')}';
  final b = StringBuffer('day,type,amount,category,note\n');
  for (final e in entries.toList()..sort((a, b) => a.day.compareTo(b.day))) {
    b.writeln([d(e.day), e.kind == MoneyKind.income ? 'income' : 'expense', e.amount.toStringAsFixed(2), q(e.category), q(e.note ?? '')].join(','));
  }
  return b.toString();
}
