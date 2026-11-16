/// ตัวเลขของโปรเจกต์ (ไม่มี UI)
library;

import 'money_models.dart';
import 'project_models.dart';

class ProjectMoney {
  const ProjectMoney({required this.price, required this.cost, required this.received, required this.paidCount, required this.paymentCount});
  final double price;

  /// รายจ่ายที่ผูกโปรเจกต์
  final double cost;

  /// รายรับที่ผูกโปรเจกต์ (งวดที่รับแล้ว + อื่น ๆ)
  final double received;
  final int paidCount;
  final int paymentCount;

  double get profit => price - cost;
  double get remaining => (price - received).clamp(0, double.infinity).toDouble();
}

ProjectMoney projectMoney(Project p, Iterable<MoneyEntry> entries, List<ProjectPayment> payments) {
  final mine = entries.where((e) => e.projectId == p.id);
  final double price = p.price ?? payments.fold<double>(0, (a, x) => a + x.amount);
  return ProjectMoney(
    price: price,
    cost: mine.where((e) => e.kind == MoneyKind.expense).fold(0, (a, e) => a + e.amount),
    received: mine.where((e) => e.kind == MoneyKind.income).fold(0, (a, e) => a + e.amount),
    paidCount: payments.where((x) => x.received).length,
    paymentCount: payments.length,
  );
}

/// งวดตามเปอร์เซ็นต์ (เช่น 30 / 40 / 30) → ยอดเงิน (เศษไปงวดสุดท้าย ให้รวมพอดีราคา)
List<double> splitByPercent(double price, List<double> percents) {
  final out = [for (final p in percents) (price * p / 100).roundToDouble()];
  if (out.isNotEmpty) out[out.length - 1] += price - out.fold(0.0, (a, b) => a + b);
  return out;
}

/// ขั้นงานถัดไปที่ยังไม่เสร็จ (ใกล้กำหนดสุด)
ProjectTask? nextTask(List<ProjectTask> tasks) {
  final open = tasks.where((t) => !t.done).toList()
    ..sort((a, b) => (a.due ?? DateTime(9999)).compareTo(b.due ?? DateTime(9999)));
  return open.firstOrNull;
}

// ---------------- ภาพรวมงาน (รอบ 9C) ----------------

DateTime _d(DateTime d) => DateTime(d.year, d.month, d.day);

/// ขั้นงานแบ่งตามกำหนด: เลยแล้ว · 7 วันนี้ · ทีหลัง · ไม่มีกำหนด
enum TaskBucket { overdue, week, later, none }

TaskBucket taskBucket(ProjectTask t, DateTime today) {
  if (t.due == null) return TaskBucket.none;
  final days = _d(t.due!).difference(_d(today)).inDays;
  if (days < 0) return TaskBucket.overdue;
  if (days <= 7) return TaskBucket.week;
  return TaskBucket.later;
}

String taskBucketText(TaskBucket b) => switch (b) {
      TaskBucket.overdue => 'เลยกำหนด',
      TaskBucket.week => '7 วันนี้',
      TaskBucket.later => 'ทีหลัง',
      TaskBucket.none => 'ไม่มีกำหนด',
    };

/// ขั้นงานที่ยังไม่เสร็จทุกโปรเจกต์ (ไม่นับโปรเจกต์ที่เก็บเงินแล้ว) · ใกล้กำหนด → ไกล · ไม่มีกำหนดไว้ท้าย
List<(Project, ProjectTask)> openTasks(List<Project> projects, Map<int, List<ProjectTask>> tasks) => [
      for (final p in projects)
        if (p.status != ProjectStatus.paid)
          for (final t in tasks[p.id] ?? const <ProjectTask>[])
            if (!t.done) (p, t)
    ]..sort((a, b) => (a.$2.due ?? DateTime(9999)).compareTo(b.$2.due ?? DateTime(9999)));

/// งวดที่ยังไม่ได้รับ (โปรเจกต์ที่ยืนยันแล้วขึ้นไป · ใบเสนอราคายังไม่นับ) · ครบกำหนดก่อน → หลัง
List<(Project, ProjectPayment)> pendingPayments(List<Project> projects, Map<int, List<ProjectPayment>> payments) => [
      for (final p in projects)
        if (p.status != ProjectStatus.quote)
          for (final x in payments[p.id] ?? const <ProjectPayment>[])
            if (!x.received) (p, x)
    ]..sort((a, b) => (a.$2.due ?? DateTime(9999)).compareTo(b.$2.due ?? DateTime(9999)));

class WorkSummary {
  const WorkSummary({
    required this.doing,
    required this.nextDue,
    required this.pending,
    required this.nextPay,
    required this.profitYear,
    required this.closedYear,
    required this.tasksDone,
    required this.tasksTotal,
    required this.overdue,
  });

  /// กำลังทำ (ยืนยันแล้ว + กำลังทำ)
  final int doing;

  /// ส่งมอบถัดไป (กำหนดเสร็จที่ใกล้ที่สุดของงานที่ยังไม่ส่ง)
  final DateTime? nextDue;

  /// เงินรอเก็บ
  final double pending;
  final (Project, ProjectPayment)? nextPay;

  /// กำไรของงานที่เก็บเงินครบในปีนี้
  final double profitYear;
  final int closedYear;
  final int tasksDone;
  final int tasksTotal;
  final int overdue;
}

WorkSummary workSummary(List<Project> projects, Map<int, List<ProjectTask>> tasks, Map<int, List<ProjectPayment>> payments,
    List<MoneyEntry> entries, DateTime today) {
  final active = projects.where((p) => p.status == ProjectStatus.confirmed || p.status == ProjectStatus.doing).toList();
  final dues = [for (final p in active) if (p.due != null && !p.due!.isBefore(_d(today))) p.due!]..sort();
  final pend = pendingPayments(projects, payments);
  // ปีที่ปิดงาน = วันที่รับเงินงวดสุดท้าย (ไม่มี = กำหนดเสร็จ)
  DateTime? closedOn(Project p) {
    final got = [for (final x in payments[p.id] ?? const <ProjectPayment>[]) if (x.entryId != null) x.entryId!];
    final days = [for (final e in entries) if (got.contains(e.id)) e.day]..sort();
    return days.lastOrNull ?? p.due;
  }

  final closed = projects.where((p) => p.status == ProjectStatus.paid && closedOn(p)?.year == today.year).toList();
  final all = [for (final p in projects) if (p.status != ProjectStatus.paid) ...?tasks[p.id]];
  return WorkSummary(
    doing: active.length,
    nextDue: dues.firstOrNull,
    pending: pend.fold(0, (a, x) => a + x.$2.amount),
    nextPay: pend.firstOrNull,
    profitYear: closed.fold(0, (a, p) => a + projectMoney(p, entries, payments[p.id] ?? const []).profit),
    closedYear: closed.length,
    tasksDone: all.where((t) => t.done).length,
    tasksTotal: all.length,
    overdue: all.where((t) => !t.done && taskBucket(t, today) == TaskBucket.overdue).length,
  );
}
