/// ความสำเร็จ: ครบทั้งวัน · สตรีค · เหรียญ (คำนวณจากข้อมูลที่มีอยู่ ไม่ต้องเก็บตารางใหม่)
library;

import 'calendar_models.dart';
import 'calendar_repository.dart';

/// ความคืบหน้าของวัน: (เสร็จ, ทั้งหมด)
/// เสร็จ = ทำแล้ว หรือ ยกเลิก (มีเหตุผลแล้ว) · ไม่นับครั้งที่ถูกเลื่อนออก / รอเลือกวัน
(int, int) dayProgress(Iterable<Occurrence> items) {
  var done = 0, total = 0;
  for (final o in items) {
    if (o.status == OccurrenceStatus.moved ||
        o.status == OccurrenceStatus.inbox ||
        o.status == OccurrenceStatus.shifted) {
      continue;
    }
    total++;
    if (o.status == OccurrenceStatus.done || o.status == OccurrenceStatus.cancelled) done++;
  }
  return (done, total);
}

/// ครบทั้งวัน: มีงานอย่างน้อย 1 และเสร็จทุกงาน
bool dayComplete(Iterable<Occurrence> items) {
  final (done, total) = dayProgress(items);
  return total > 0 && done == total;
}

/// สตรีค: นับวันที่ครบติดกันย้อนจาก [today] · วันที่ไม่มีงานไม่ตัดสตรีค
/// วันนี้ยังไม่ครบ = ยังไม่ตัด (เริ่มนับจากเมื่อวาน)
class StreakInfo {
  const StreakInfo({required this.current, required this.best, required this.completeDays});
  final int current;
  final int best;

  /// วันที่ครบทั้งวัน (ใหม่ → เก่า)
  final List<DateTime> completeDays;
}

/// [lookback] วันย้อนหลังที่ดู (รวมวันนี้)
Future<StreakInfo> loadStreak(CalendarRepository repo, DateTime today, {int lookback = 60}) async {
  final days = <DateTime, List<Occurrence>>{};
  for (var i = 0; i < lookback; i++) {
    final d = DateTime(today.year, today.month, today.day - i);
    days[d] = await repo.occurrencesOn(d);
  }
  return streakOf(days, dayOnly(today));
}

/// คำนวณจากงานรายวัน (แยกให้เทสได้)
StreakInfo streakOf(Map<DateTime, List<Occurrence>> byDay, DateTime today) {
  final ordered = byDay.keys.toList()..sort((a, b) => b.compareTo(a)); // ใหม่ → เก่า
  final complete = [for (final d in ordered) if (dayComplete(byDay[d]!)) d];
  var current = 0, run = 0, best = 0;
  var counting = true;
  for (final d in ordered) {
    final items = byDay[d]!;
    if (dayProgress(items).$2 == 0) continue; // ไม่มีงาน = ข้าม ไม่ตัด
    if (dayComplete(items)) {
      run++;
      if (counting) current = run;
    } else {
      if (d == today) continue; // วันนี้ยังไม่จบ ไม่ตัด
      counting = false;
      run = 0;
    }
    if (run > best) best = run;
  }
  return StreakInfo(current: current, best: best, completeDays: complete);
}
