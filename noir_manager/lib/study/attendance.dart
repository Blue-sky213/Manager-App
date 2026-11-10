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
