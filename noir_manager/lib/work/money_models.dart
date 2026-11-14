/// การเงิน (รอบ 8D): รายรับ / รายจ่าย · ค่าบริการรายเดือน (ติ๊กตัดเงินแล้ว) · เงินลงทุน → คืนทุน
library;

enum MoneyKind { income, expense }

class MoneyEntry {
  const MoneyEntry({
    this.id = 0,
    required this.day,
    required this.kind,
    required this.amount,
    required this.category,
    this.note,
    this.projectId,
    this.investmentId,
    this.subscriptionId,
  });

  final int id;
  final DateTime day;
  final MoneyKind kind;

  /// บาท (บวกเสมอ · ประเภทบอกว่าเข้า/ออก)
  final double amount;
  final String category;
  final String? note;

  /// ผูกโปรเจกต์ (รอบ 8E) · ผูกเงินลงทุน (รายรับที่ช่วยคืนทุน) · มาจากค่าบริการ (ติ๊กตัดเงินแล้ว)
  final int? projectId;
  final int? investmentId;
  final int? subscriptionId;

  double get signed => kind == MoneyKind.income ? amount : -amount;
}

enum BillCycle { monthly, yearly }

/// ค่าบริการ (Adobe · AI · โดเมน ฯลฯ) · [amount] null = ยังไม่รู้ยอด (ใส่ตอนติ๊ก)
class Subscription {
  const Subscription({
    this.id = 0,
    required this.name,
    this.amount,
    this.cycle = BillCycle.monthly,
    this.billDay = 1,
    this.billMonth,
    this.active = true,
  });

  final int id;
  final String name;
  final double? amount;
  final BillCycle cycle;

  /// วันที่ตัดเงิน (1–31 · เดือนสั้นใช้วันสุดท้าย)
  final int billDay;

  /// รายปี: เดือนที่ตัด (1–12)
  final int? billMonth;
  final bool active;

  /// ต่อเดือน (รายปี ÷ 12)
  double get perMonth => (amount ?? 0) / (cycle == BillCycle.yearly ? 12 : 1);
}

/// เงินลงทุน (อุปกรณ์ · ทุนเริ่มต้นโปรเจกต์) · รายรับที่ผูกไว้ = เงินที่คืนแล้ว
class Investment {
  const Investment({this.id = 0, required this.name, required this.amount, required this.startDay, this.note});
  final int id;
  final String name;
  final double amount;
  final DateTime startDay;
  final String? note;
}

const expenseCategories = ['อาหาร', 'เดินทาง', 'ค่าบริการ', 'อุปกรณ์', 'วัสดุ / ค่าแรง', 'บ้าน', 'อื่น ๆ'];
const incomeCategories = ['งานรับจ้าง', 'งวดงาน', 'ขายของ', 'สปอนเซอร์', 'อื่น ๆ'];

/// งบค่าบริการรวมต่อเดือน (setting)
const subBudgetKey = 'sub_budget';
