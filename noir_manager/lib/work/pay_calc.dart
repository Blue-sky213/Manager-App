/// เช็คอินงาน + ค่าจ้าง (รอบ 22 · อนุมัติ 24 พ.ย.)
/// กติกา: 8 ชม. แรกของวัน = ปกติ (เข้ากี่โมงก็ได้) · พักอัตโนมัติ 1 ชม. เมื่อทำ ≥ 6 ชม.
/// นับช่วงละ 30 นาที ปัดลง (ทั้ง OT และชั่วโมงที่ขาด) · รายเดือน: OT ชดเชยชั่วโมงที่ขาดก่อน (1:1) แล้วจ่ายส่วนที่เหลือ
/// วันหยุดที่ทำแทนวันที่ขาด = สลับวันหยุด (เป็นวันธรรมดา) · วันหยุดที่ทำเพิ่มเฉย ๆ = อัตราวันหยุด
library;

import 'dart:convert';
import 'dart:math' as math;

enum PayType { monthly, daily, hourly, piece, project }

const payTypeLabel = {
  PayType.monthly: 'รายเดือน',
  PayType.daily: 'รายวัน',
  PayType.hourly: 'รายชั่วโมง',
  PayType.piece: 'ตามชิ้นงาน',
  PayType.project: 'รายโปรเจกต์',
};

/// วันทำงานที่ไม่มีเช็คอิน
enum AbsenceKind { absent, leave, off }

const absenceLabel = {AbsenceKind.absent: 'ขาดงาน', AbsenceKind.leave: 'ลาได้เงิน', AbsenceKind.off: 'วันหยุดพิเศษ'};

/// เงินเพิ่ม (+) / เงินหัก (−) ทุกเดือน
class PayExtra {
  const PayExtra(this.name, this.amount);
  final String name;
  final double amount;
  Map<String, Object?> toJson() => {'name': name, 'amount': amount};
  static PayExtra fromJson(Map<String, Object?> j) => PayExtra('${j['name'] ?? ''}', (j['amount'] as num?)?.toDouble() ?? 0);
}

const payConfigKey = 'pay_config';

class PayConfig {
  const PayConfig({
    this.type = PayType.monthly,
    this.monthly = 15000,
    this.daily = 500,
    this.hourly = 62.5,
    this.piece = 0,
    this.workDays = const {1, 2, 3, 4, 5, 6},
    this.normalMin = 480,
    this.breakMin = 60,
    this.breakAfterMin = 360,
    this.otRate = 1.5,
    this.holOtRate = 3,
    this.roundMin = 30,
    this.payDay = 1,
    this.extras = const [],
  });

  final PayType type;
  final double monthly, daily, hourly, piece;

  /// วันทำงาน (DateTime.weekday: 1 = จันทร์ … 7 = อาทิตย์)
  final Set<int> workDays;
  final int normalMin, breakMin, breakAfterMin, roundMin, payDay;
  final double otRate, holOtRate;
  final List<PayExtra> extras;

  /// รายเดือน: เงินเดือน ÷ 30 ÷ ชม.ปกติ (ตามกฎหมาย) · รายวัน: ค่าแรงวัน ÷ ชม.ปกติ
  double get hourRate => switch (type) {
        PayType.monthly => monthly / 30 / (normalMin / 60),
        PayType.daily => daily / (normalMin / 60),
        _ => hourly,
      };
  double get dayRate => hourRate * normalMin / 60;
  double get otHour => hourRate * otRate;

  /// ทำงานวันหยุด: รายเดือน ×1 (วันหยุดได้เงินอยู่แล้ว) · แบบอื่น ×2
  double get holHour => hourRate * (type == PayType.monthly ? 1 : 2);
  double get holOtHour => hourRate * holOtRate;
  bool get timed => type != PayType.piece && type != PayType.project;

  PayConfig copyWith({
    PayType? type,
    double? monthly,
    double? daily,
    double? hourly,
    double? piece,
    Set<int>? workDays,
    List<PayExtra>? extras,
  }) =>
      PayConfig(
        type: type ?? this.type,
        monthly: monthly ?? this.monthly,
        daily: daily ?? this.daily,
        hourly: hourly ?? this.hourly,
        piece: piece ?? this.piece,
        workDays: workDays ?? this.workDays,
        normalMin: normalMin,
        breakMin: breakMin,
        breakAfterMin: breakAfterMin,
        otRate: otRate,
        holOtRate: holOtRate,
        roundMin: roundMin,
        payDay: payDay,
        extras: extras ?? this.extras,
      );

  String encode() => jsonEncode({
        'type': type.name,
        'monthly': monthly,
        'daily': daily,
        'hourly': hourly,
        'piece': piece,
        'work_days': workDays.toList()..sort(),
        'normal_min': normalMin,
        'break_min': breakMin,
        'break_after_min': breakAfterMin,
        'ot_rate': otRate,
        'hol_ot_rate': holOtRate,
        'round_min': roundMin,
        'pay_day': payDay,
        'extras': [for (final e in extras) e.toJson()],
      });

  /// อ่านไม่ได้ / ไม่มี = ค่าตั้งต้น (ตั้งไว้ให้พร้อมใช้)
  static PayConfig decode(String? raw) {
    if (raw == null || raw.isEmpty) return const PayConfig();
    try {
      final j = jsonDecode(raw) as Map<String, Object?>;
      double d(String k, double def) => (j[k] as num?)?.toDouble() ?? def;
      int i(String k, int def) => (j[k] as num?)?.toInt() ?? def;
      return PayConfig(
        type: PayType.values.firstWhere((t) => t.name == j['type'], orElse: () => PayType.monthly),
        monthly: d('monthly', 15000),
        daily: d('daily', 500),
        hourly: d('hourly', 62.5),
        piece: d('piece', 0),
        workDays: {for (final x in (j['work_days'] as List?) ?? const [1, 2, 3, 4, 5, 6]) (x as num).toInt()},
        normalMin: i('normal_min', 480),
        breakMin: i('break_min', 60),
        breakAfterMin: i('break_after_min', 360),
        otRate: d('ot_rate', 1.5),
        holOtRate: d('hol_ot_rate', 3),
        roundMin: math.max(1, i('round_min', 30)),
        payDay: i('pay_day', 1),
        extras: [for (final e in (j['extras'] as List?) ?? const []) PayExtra.fromJson((e as Map).cast<String, Object?>())],
      );
    } catch (_) {
      return const PayConfig();
    }
  }
}

/// 1 รอบเข้า–ออกงาน · [endMin] null = ยังทำอยู่ · นาทีนับจากเที่ยงคืนของ [day] (เลยเที่ยงคืนได้ > 1440)
class WorkSession {
  const WorkSession({this.id = 0, required this.day, required this.startMin, this.endMin, this.compFor, this.pieces, this.note});
  final int id;
  final DateTime day;
  final int startMin;
  final int? endMin;

  /// ทำวันหยุดแทนวันที่ขาด (สลับวันหยุด)
  final DateTime? compFor;
  final int? pieces;
  final String? note;

  bool get open => endMin == null;

  WorkSession copyWith({int? id, int? startMin, int? endMin, bool clearEnd = false, DateTime? compFor, bool clearComp = false, int? pieces}) =>
      WorkSession(
        id: id ?? this.id,
        day: day,
        startMin: startMin ?? this.startMin,
        endMin: clearEnd ? null : (endMin ?? this.endMin),
        compFor: clearComp ? null : (compFor ?? this.compFor),
        pieces: pieces ?? this.pieces,
        note: note,
      );
}

DateTime dateOf(DateTime d) => DateTime(d.year, d.month, d.day);
bool isSameDate(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

class DayResult {
  const DayResult({
    this.worked = 0,
    this.breakMin = 0,
    this.normal = 0,
    this.otRaw = 0,
    this.ot = 0,
    this.holN = 0,
    this.holOT = 0,
    this.short = 0,
    this.shortDed = 0,
    this.holiday = false,
    this.swap = false,
    this.live = false,
    this.pieces = 0,
    this.swapFor,
  });

  /// วันทำงานที่ขาด ซึ่งวันหยุดนี้ทำแทน (สลับวันหยุด)
  final DateTime? swapFor;

  /// นาทีที่ทำ (หักพักแล้ว)
  final int worked, breakMin, normal, otRaw, ot, holN, holOT, short, shortDed, pieces;
  final bool holiday, swap, live;
  bool get empty => worked == 0 && !live;
}

int _floor(int v, int step) => v <= 0 ? 0 : (v ~/ step) * step;

/// คิด 1 วัน · [nowMin] = เวลาตอนนี้ (สำหรับรอบที่ยังไม่กดเลิก)
/// [swapFor] = วันที่ขาดที่วันหยุดนี้ทำแทน (calcMonth จับคู่ให้เอง)
DayResult calcDay(PayConfig c, DateTime day, List<WorkSession> sessions, {int? nowMin, DateTime? swapFor, bool paired = false}) {
  final holiday = !c.workDays.contains(day.weekday);
  if (sessions.isEmpty) return DayResult(holiday: holiday);
  var raw = 0;
  var live = false, pieces = 0;
  DateTime? comp;
  for (final s in sessions) {
    final end = s.endMin ?? nowMin ?? s.startMin;
    if (s.open) live = true;
    raw += math.max(0, end - s.startMin);
    pieces += s.pieces ?? 0;
    comp ??= s.compFor;
  }
  final brk = raw >= c.breakAfterMin ? c.breakMin : 0;
  final w = math.max(0, raw - brk);
  // [paired] = calcMonth จับคู่ให้แล้ว (ใช้ผลนั้นอย่างเดียว) · คิดวันเดียว = ใช้ที่ผู้ใช้เลือกไว้
  final pair = paired ? swapFor : (swapFor ?? comp);
  final swap = holiday && pair != null;
  if (holiday && !swap) {
    final n = math.min(w, c.normalMin);
    return DayResult(worked: w, breakMin: brk, holN: n, holOT: _floor(w - n, c.roundMin), holiday: true, live: live, pieces: pieces);
  }
  final n = math.min(w, c.normalMin);
  final short = live ? 0 : math.max(0, c.normalMin - w);
  return DayResult(
    worked: w,
    breakMin: brk,
    normal: n,
    otRaw: w - n,
    ot: _floor(w - n, c.roundMin),
    short: short,
    shortDed: _floor(short, c.roundMin),
    holiday: holiday,
    swap: swap,
    swapFor: swap ? pair : null,
    live: live,
    pieces: pieces,
  );
}

/// เวลาเลิกงานที่ครบชั่วโมงปกติ (รวมพัก) · [extraMin] = ชั่วโมงติดลบที่อยากชดเชยวันนี้
int finishAt(PayConfig c, int startMin, {int extraMin = 0}) =>
    startMin + c.normalMin + extraMin + (c.normalMin + extraMin >= c.breakAfterMin ? c.breakMin : 0);

class MonthResult {
  const MonthResult({
    required this.config,
    required this.days,
    required this.pay,
    this.absent = const [],
    this.compensated = const [],
    this.unresolved = const [],
    this.ot = 0,
    this.shortDed = 0,
    this.normal = 0,
    this.holN = 0,
    this.holOT = 0,
    this.worked = 0,
    this.pieces = 0,
  });

  final PayConfig config;
  final Map<DateTime, DayResult> days;
  final double pay;

  /// วันขาดงานที่โดนหัก · ขาดแต่ทำวันหยุดแทนแล้ว · วันทำงานที่ยังไม่ได้บอกว่าเป็นอะไร
  final List<DateTime> absent, compensated, unresolved;
  final int ot, shortDed, normal, holN, holOT, worked, pieces;

  /// รายเดือน: OT สะสม − ชั่วโมงที่ขาด (บวก = จ่าย OT · ลบ = หัก)
  int get bank => ot - shortDed;
  int get usedForShort => math.min(ot, shortDed);
  double get extrasTotal => config.extras.fold(0.0, (a, e) => a + e.amount);
}

/// คิดทั้งเดือน (ถึง [today] ถ้าเป็นเดือนปัจจุบัน)
MonthResult calcMonth(
  PayConfig c,
  int year,
  int month,
  List<WorkSession> sessions,
  Map<DateTime, AbsenceKind> absences, {
  required DateTime today,
  int? nowMin,
}) {
  final last = DateTime(year, month + 1, 0).day;
  final t = dateOf(today);
  final byDay = <DateTime, List<WorkSession>>{};
  for (final s in sessions) {
    if (s.day.year == year && s.day.month == month) (byDay[dateOf(s.day)] ??= []).add(s);
  }
  // สลับวันหยุดอัตโนมัติ (นัวร์ 24 พ.ย.): ทำงานวันหยุดในเดือนที่มีวันขาดงาน = ทำแทนวันนั้นก่อนเสมอ
  // กันการหยุดวันธรรมดาแล้วมาทำวันหยุดเพื่อได้ OT มากกว่า · เหลือวันหยุดที่ไม่มีวันขาดให้แทน = อัตราวันหยุด
  final absentDays = [
    for (final e in absences.entries)
      if (e.value == AbsenceKind.absent && e.key.year == year && e.key.month == month && !e.key.isAfter(t) && !byDay.containsKey(dateOf(e.key)))
        dateOf(e.key)
  ]..sort();
  final holDays = [for (final d in byDay.keys) if (!c.workDays.contains(d.weekday) && !d.isAfter(t)) d]..sort();
  final swapOf = <DateTime, DateTime>{};
  final free = {...absentDays};
  for (final d in holDays) {
    // จับคู่ที่ผู้ใช้เลือกไว้เองก่อน
    final chosen = byDay[d]!.map((s) => s.compFor).whereType<DateTime>().map(dateOf).where(free.contains).firstOrNull;
    if (chosen != null) {
      swapOf[d] = chosen;
      free.remove(chosen);
    }
  }
  for (final d in holDays) {
    if (swapOf.containsKey(d) || free.isEmpty) continue;
    final first = (free.toList()..sort()).first;
    swapOf[d] = first;
    free.remove(first);
  }
  final compDays = swapOf.values.toSet();
  final days = <DateTime, DayResult>{};
  final absent = <DateTime>[], compensated = <DateTime>[], unresolved = <DateTime>[];
  var ot = 0, shortDed = 0, normal = 0, holN = 0, holOT = 0, worked = 0, pieces = 0;
  for (var d = 1; d <= last; d++) {
    final day = DateTime(year, month, d);
    if (day.isAfter(t)) break;
    final ss = byDay[day] ?? const [];
    final r = calcDay(c, day, ss, nowMin: isSameDate(day, t) ? nowMin : null, swapFor: swapOf[day], paired: true);
    days[day] = r;
    if (ss.isEmpty) {
      final a = absences[day];
      if (a == AbsenceKind.absent) {
        (compDays.contains(day) ? compensated : absent).add(day);
      } else if (a == null && c.workDays.contains(day.weekday) && day.isBefore(t) && c.timed) {
        unresolved.add(day);
      }
      continue;
    }
    ot += r.ot;
    shortDed += r.shortDed;
    normal += r.normal;
    holN += r.holN;
    holOT += r.holOT;
    worked += r.worked;
    pieces += r.pieces;
  }
  final extras = c.extras.fold(0.0, (a, e) => a + e.amount);
  final h = c.hourRate;
  final double pay = switch (c.type) {
    PayType.monthly => c.monthly -
        absent.length * c.dayRate +
        ((ot - shortDed) >= 0 ? (ot - shortDed) / 60 * c.otHour : (ot - shortDed) / 60 * h) +
        holN / 60 * c.holHour +
        holOT / 60 * c.holOtHour,
    PayType.daily || PayType.hourly => normal / 60 * h + ot / 60 * c.otHour + holN / 60 * c.holHour + holOT / 60 * c.holOtHour,
    PayType.piece => pieces * c.piece,
    PayType.project => 0,
  };
  return MonthResult(
    config: c,
    days: days,
    pay: pay + extras,
    absent: absent,
    compensated: compensated,
    unresolved: unresolved,
    ot: ot,
    shortDed: shortDed,
    normal: normal,
    holN: holN,
    holOT: holOT,
    worked: worked,
    pieces: pieces,
  );
}

/// 1,234.50
String money2(double v) {
  final neg = v < 0;
  final cents = (v.abs() * 100).round();
  final s = (cents ~/ 100).toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '${neg ? '−' : ''}$b.${(cents % 100).toString().padLeft(2, '0')}';
}

/// 08:05
String clock(int min) {
  final m = ((min % 1440) + 1440) % 1440;
  return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
}

/// 8 ชม. · 7:30 ชม.
String hrsText(int min) {
  final h = min ~/ 60, m = min % 60;
  return m == 0 ? '$h ชม.' : '$h:${m.toString().padLeft(2, '0')} ชม.';
}
