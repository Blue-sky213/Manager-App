import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';

/// จำนวนคาบเรียนทั้งหมดของวิชา (นับจากตารางเรียนในปฏิทิน) — ใช้คิด % ขาดเรียน
/// null = ยังบอกไม่ได้ (ไม่มีคาบ หรือคาบซ้ำไม่มีวันสุดท้าย) → ให้นัวร์ใส่เอง
Future<int?> plannedClassTotal(CalendarRepository cal, int subjectId) async {
  var total = 0;
  for (final a in await cal.activitiesForSubject(subjectId)) {
    if (a.kind != ActivityKind.classSession) continue;
    final n = countPlanned(a.repeat == RepeatKind.dates && a.dates.isEmpty ? await cal.activity(a.id) : a);
    if (n == null) return null;
    total += n;
  }
  return total == 0 ? null : total;
}

/// งาน 1 ตัวเกิดกี่ครั้งตามกฎการทำซ้ำ (null = ไม่มีวันสุดท้าย นับไม่จบ)
int? countPlanned(Activity a) {
  switch (a.repeat) {
    case RepeatKind.none:
      return 1;
    case RepeatKind.dates:
      return a.dates.length;
    default:
      if (a.endDate == null) return null;
      var n = 0;
      final last = dayOnly(a.endDate!);
      for (var d = dayOnly(a.startDate); !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
        if (occursOn(a, d)) n++;
      }
      return n;
  }
}

/// คาบถัดไปของวิชาหลังวัน [after] (วัน + เวลาเริ่มคาบ) · ใช้ตั้งกำหนดส่ง "คาบหน้า"
Future<DateTime?> nextClassAfter(CalendarRepository cal, int subjectId, DateTime after) async {
  DateTime? best;
  final from = dayOnly(after);
  for (final a in await cal.activitiesForSubject(subjectId)) {
    if (a.kind != ActivityKind.classSession) continue;
    final full = a.repeat == RepeatKind.dates && a.dates.isEmpty ? await cal.activity(a.id) : a;
    for (var i = 1; i <= 60; i++) {
      final d = DateTime(from.year, from.month, from.day + i);
      if (best != null && !d.isBefore(dayOnly(best))) break;
      if (full.endDate != null && d.isAfter(dayOnly(full.endDate!))) break;
      if (occursOn(full, d)) {
        final at = DateTime(d.year, d.month, d.day).add(Duration(minutes: full.startMinute ?? 8 * 60));
        if (best == null || at.isBefore(best)) best = at;
        break;
      }
    }
  }
  return best;
}
