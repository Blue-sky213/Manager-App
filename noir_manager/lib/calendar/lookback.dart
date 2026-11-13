/// สถิติย้อนหลัง (รอบ 7 · O): งานสำคัญ ตรงเวลา / ช้า / พลาด เทียบกับ ชั่วโมงนอน · พลังตอนเช้า · หมวด · วัน
/// ใช้หาว่า "พลาดเพราะอะไร" · ทุกข้อสรุปบอกจำนวนวันที่ใช้คิด กันสรุปเกินจริง
library;

import 'calendar_models.dart';
import 'day_judge.dart' show importantOf;
import 'stickers.dart';

/// ผลของ 1 วัน
class DayLog {
  const DayLog({
    required this.day,
    required this.important,
    required this.onTime,
    required this.late,
    required this.missed,
    this.sleepHours,
    this.energy,
    this.reason,
    this.missedCats = const [],
    this.moods = const [],
  });

  final DateTime day;
  final int important;
  final int onTime;
  final int late;
  final int missed;

  /// นอนเมื่อคืน (ก่อนวันนี้) จากเช็กอินเช้า
  final double? sleepHours;
  final int? energy;

  /// เหตุผลที่พลาด (ตอบตอนเช้าวันถัดไป)
  final String? reason;
  final List<int?> missedCats;
  final List<String> moods;

  /// วันนี้ทำงานสำคัญครบทันเวลา
  bool get clean => important > 0 && late == 0 && missed == 0;
}

class Lookback {
  const Lookback({
    required this.logs,
    required this.onTime,
    required this.late,
    required this.missed,
    required this.sleep,
    required this.energy,
    required this.missedByCat,
    required this.missedByWeekday,
    required this.reasons,
    required this.insights,
  });

  final List<DayLog> logs;
  final int onTime;
  final int late;
  final int missed;

  /// (ชื่อกลุ่ม, วันที่ครบทันเวลา, วันทั้งหมด)
  final List<(String, int, int)> sleep;
  final List<(String, int, int)> energy;
  final Map<int?, int> missedByCat;
  final Map<int, int> missedByWeekday;
  final Map<String, int> reasons;
  final List<String> insights;

  int get total => onTime + late + missed;
  double? get onTimeRate => total == 0 ? null : onTime * 100 / total;
}

/// วิเคราะห์ช่วง [days] (วันก่อน [today] เท่านั้น = ตัดสินแล้ว)
Lookback analyzeLookback({
  required Map<DateTime, List<Occurrence>> days,
  required Map<DateTime, Checkin> checkins,
  required Map<DateTime, List<DaySticker>> stickers,
  required DateTime today,
}) {
  final logs = <DayLog>[];
  for (final e in days.entries) {
    final d = dayOnly(e.key);
    if (!d.isBefore(today)) continue;
    final imp = importantOf(e.value);
    if (imp.isEmpty) continue;
    final st = stickers[d] ?? const [];
    final wasLate = st.any((s) => s.auto == 'late');
    final done = imp.where((o) => o.status == OccurrenceStatus.done).length;
    final missed = imp.where((o) => o.status == OccurrenceStatus.planned).toList();
    final next = checkins[d.add(const Duration(days: 1))];
    logs.add(DayLog(
      day: d,
      important: imp.length,
      onTime: wasLate ? 0 : done,
      late: wasLate ? done : 0,
      missed: missed.length,
      sleepHours: checkins[d]?.sleepHours,
      energy: checkins[d]?.energy,
      reason: missed.isEmpty && !wasLate ? null : next?.missReason,
      missedCats: [for (final o in missed) o.categoryId],
      moods: [for (final s in st) if (s.auto == null) s.sticker.name],
    ));
  }
  logs.sort((a, b) => a.day.compareTo(b.day));

  (String, int, int) bucket(String name, bool Function(DayLog) f) {
    final ds = logs.where(f).toList();
    return (name, ds.where((l) => l.clean).length, ds.length);
  }

  final sleep = [
    bucket('< 6 ชม.', (l) => l.sleepHours != null && l.sleepHours! < 6),
    bucket('6–7 ชม.', (l) => l.sleepHours != null && l.sleepHours! >= 6 && l.sleepHours! < 7),
    bucket('≥ 7 ชม.', (l) => l.sleepHours != null && l.sleepHours! >= 7),
  ];
  final energy = [
    bucket('😴 1–2', (l) => l.energy != null && l.energy! <= 2),
    bucket('🙂 3', (l) => l.energy == 3),
    bucket('⚡ 4–5', (l) => l.energy != null && l.energy! >= 4),
  ];
  final byCat = <int?, int>{};
  final byWd = <int, int>{};
  final reasons = <String, int>{};
  for (final l in logs) {
    for (final cat in l.missedCats) {
      byCat[cat] = (byCat[cat] ?? 0) + 1;
    }
    if (l.missed > 0 || l.late > 0) byWd[l.day.weekday] = (byWd[l.day.weekday] ?? 0) + 1;
    if (l.reason != null) reasons[l.reason!] = (reasons[l.reason!] ?? 0) + 1;
  }

  // ข้อสังเกต: ต้องมีอย่างน้อย 3 วันทั้งสองฝั่งจึงสรุป
  final insights = <String>[];
  double miss((String, int, int) b) => b.$3 == 0 ? 0 : 1 - b.$2 / b.$3;
  final short = sleep[0];
  final enough = (sleep[1].$1, sleep[1].$2 + sleep[2].$2, sleep[1].$3 + sleep[2].$3);
  if (short.$3 >= 3 && enough.$3 >= 3 && miss(short) > miss(enough)) {
    final x = miss(enough) == 0 ? null : miss(short) / miss(enough);
    insights.add('คืนที่นอน < 6 ชม. วันถัดไปพลาด/ช้าบ่อยกว่า${x == null ? '' : ' ${x.toStringAsFixed(1)} เท่า'} '
        '(${(miss(short) * 100).round()}% vs ${(miss(enough) * 100).round()}% · จาก ${short.$3 + enough.$3} วัน)');
  }
  final low = energy[0];
  final high = energy[2];
  if (low.$3 >= 3 && high.$3 >= 3 && miss(low) > miss(high)) {
    insights.add('เช้าที่พลังต่ำ (1–2) ทำครบน้อยกว่าเช้าที่พลังสูง '
        '(${(100 - miss(low) * 100).round()}% vs ${(100 - miss(high) * 100).round()}% · จาก ${low.$3 + high.$3} วัน)');
  }
  if (byWd.isNotEmpty) {
    final top = byWd.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value >= 2) insights.add('พลาด/ช้าบ่อยสุดวัน${_wdLong[top.key - 1]} (${top.value} ครั้ง)');
  }
  if (reasons.isNotEmpty) {
    final top = reasons.entries.reduce((a, b) => a.value >= b.value ? a : b);
    if (top.value >= 2) insights.add('เหตุผลที่ตอบบ่อยสุด: ${top.key} (${top.value} ครั้ง)');
  }

  return Lookback(
    logs: logs,
    onTime: logs.fold(0, (s, l) => s + l.onTime),
    late: logs.fold(0, (s, l) => s + l.late),
    missed: logs.fold(0, (s, l) => s + l.missed),
    sleep: sleep,
    energy: energy,
    missedByCat: byCat,
    missedByWeekday: byWd,
    reasons: reasons,
    insights: insights,
  );
}

const _wdLong = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

/// CSV สำหรับเอาไปวิเคราะห์ต่อ (Excel / AI ในเครื่อง) · 1 แถว = 1 วัน
String lookbackCsv(Lookback lb) {
  String q(String s) => s.contains(',') || s.contains('"') ? '"${s.replaceAll('"', '""')}"' : s;
  final b = StringBuffer('day,weekday,important,on_time,late,missed,sleep_hours,energy,miss_reason,moods\n');
  for (final l in lb.logs) {
    b.writeln([
      dayKey(l.day),
      l.day.weekday,
      l.important,
      l.onTime,
      l.late,
      l.missed,
      l.sleepHours?.toStringAsFixed(2) ?? '',
      l.energy ?? '',
      q(l.reason ?? ''),
      q(l.moods.join(' ')),
    ].join(','));
  }
  return b.toString();
}
