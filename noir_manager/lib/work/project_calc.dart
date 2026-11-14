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
