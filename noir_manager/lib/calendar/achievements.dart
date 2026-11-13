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
        o.status == OccurrenceStatus.shifted ||
        o.freeAll) {
      continue; // ว่างจากงานทั้งช่วง (งานยืดหยุ่น) = ไม่นับว่าต้องทำ
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

/// % ทำตามแผนของชุดงาน · null = ไม่มีงาน
double? percentDone(Iterable<Occurrence> items) {
  final (done, total) = dayProgress(items);
  return total == 0 ? null : done * 100 / total;
}

/// กลุ่มของงานสำหรับแถบ "แยกตามกิจกรรม": เรียน · ติว · ชื่อหมวด · อื่น ๆ
String activityGroup(Occurrence o, Map<int, String> categoryNames) => switch (o.kind) {
      ActivityKind.classSession => 'เรียน',
      ActivityKind.tutor => 'ติว',
      _ => categoryNames[o.categoryId] ?? 'อื่น ๆ',
    };

/// % ต่อกลุ่ม: (กลุ่ม, % ช่วงนี้, % ช่วงก่อน) เรียงตามจำนวนงานมากก่อน
List<(String, double, double?)> groupPercents(
  List<Occurrence> now,
  List<Occurrence> before,
  String Function(Occurrence) groupOf,
) {
  final g = <String, List<Occurrence>>{};
  for (final o in now) {
    (g[groupOf(o)] ??= []).add(o);
  }
  final b = <String, List<Occurrence>>{};
  for (final o in before) {
    (b[groupOf(o)] ??= []).add(o);
  }
  final keys = g.keys.where((k) => percentDone(g[k]!) != null).toList()
    ..sort((x, y) => g[y]!.length.compareTo(g[x]!.length));
  return [for (final k in keys) (k, percentDone(g[k]!)!, b[k] == null ? null : percentDone(b[k]!))];
}

/// ข้อความตามระดับ (ตกลงไว้: ≥ 80 ชม · 50–79 กลาง · < 50 ปลอบ)
String levelMessage(double p) => p >= 80
    ? 'ทำได้ดีมาก รักษาจังหวะนี้ไว้'
    : p >= 50
        ? 'ไปได้ดี ค่อย ๆ เพิ่มทีละนิด'
        : 'ช่วงนี้หนักหน่อย พักให้พอแล้วค่อยเริ่มใหม่';

// ---------- เหรียญ 3 ขั้น (ทองแดง → เงิน → ทอง) · เกณฑ์สูง กันเหรียญเฟ้อ ----------

/// เหรียญ 1 สาย · [values] = ค่าที่ใช้เทียบเกณฑ์แต่ละขั้น (บางสายใช้ค่าต่างกันต่อขั้น)
class MedalTrack {
  const MedalTrack(this.name, this.desc, this.goals, this.values, {this.unit = ''});
  final String name;
  final String desc;
  final List<int> goals; // [ทองแดง, เงิน, ทอง]
  final List<int> values; // ค่าที่ทำได้ เทียบกับ goals ทีละขั้น
  final String unit;

  /// ได้ถึงขั้นไหน: 0 = ยังไม่ได้ · 1 ทองแดง · 2 เงิน · 3 ทอง
  int get level {
    var l = 0;
    for (var i = 0; i < 3; i++) {
      if (values[i] >= goals[i]) l = i + 1;
    }
    return l;
  }

  /// ขั้นถัดไป: (ค่าปัจจุบัน, เป้า) · ทองแล้ว = null
  (int, int)? get next => level >= 3 ? null : (values[level], goals[level]);
}

/// ช่วงติดกันยาวสุดที่ [ok] เป็นจริง
int _bestRun(Iterable<bool> xs) {
  var run = 0, best = 0;
  for (final x in xs) {
    run = x ? run + 1 : 0;
    if (run > best) best = run;
  }
  return best;
}

/// คำนวณเหรียญจากงานย้อนหลัง (ปกติ 1 ปี) · [understoodSubjects] = วิชาที่ทุกหัวข้อ ≥ 80%
List<MedalTrack> medalTracks(Map<DateTime, List<Occurrence>> byDay, DateTime today, {int understoodSubjects = 0}) {
  final streak = streakOf(byDay, today);
  final days = byDay.keys.where((d) => !d.isAfter(today)).toList()..sort();

  // เดือนเต็ม: % ทั้งเดือน (เฉพาะเดือนที่จบแล้ว)
  final months = <DateTime, List<Occurrence>>{};
  for (final d in days) {
    if (d.year == today.year && d.month == today.month) continue;
    (months[DateTime(d.year, d.month)] ??= []).addAll(byDay[d]!);
  }
  final monthPct = [for (final m in (months.keys.toList()..sort())) percentDone(months[m]!) ?? 0];

  // นักติว: สัปดาห์ที่จบแล้วซึ่งทุกวิชาที่มีคาบ มีติว "ทำแล้ว" อย่างน้อย 1 รอบ
  final weeks = <DateTime, List<Occurrence>>{};
  for (final d in days) {
    final mon = DateTime(d.year, d.month, d.day - (d.weekday - 1));
    if (!mon.add(const Duration(days: 6)).isBefore(today)) continue;
    (weeks[mon] ??= []).addAll(byDay[d]!);
  }
  final tutorOk = <bool>[];
  for (final w in (weeks.keys.toList()..sort())) {
    final items = weeks[w]!;
    final subjects = {for (final o in items) if (o.kind == ActivityKind.classSession && o.active) o.subjectId};
    if (subjects.isEmpty) continue; // ไม่มีเรียน (ปิดเทอม) = ข้าม ไม่ตัด
    tutorOk.add(subjects.every((s) =>
        items.any((o) => o.kind == ActivityKind.tutor && o.subjectId == s && o.status == OccurrenceStatus.done)));
  }

  // ส่งงานตรงเวลา: ⭐ ที่ทำแล้วติดกัน (เรียงตามวัน)
  final hw = [
    for (final d in days)
      for (final o in byDay[d]!)
        if (o.title.startsWith('ส่ง:') && o.status != OccurrenceStatus.moved && d.isBefore(today))
          o.status == OccurrenceStatus.done,
  ];

  int runAtLeast(int pct) => _bestRun(monthPct.map((p) => p >= pct));
  final tutorBest = _bestRun(tutorOk);
  final hwBest = _bestRun(hw);
  return [
    MedalTrack('Streak', 'ทำครบทุกงานติดกัน', const [14, 45, 120],
        [streak.best, streak.best, streak.best], unit: 'วัน'),
    MedalTrack('ครบทั้งวัน', 'สะสมวันที่ทำครบ', const [30, 100, 250],
        List.filled(3, streak.completeDays.length), unit: 'วัน'),
    MedalTrack('เดือนเต็ม', '≥ 80% 1 เดือน · ≥ 85% 3 เดือนติด · ≥ 90% 6 เดือนติด', const [1, 3, 6],
        [runAtLeast(80), runAtLeast(85), runAtLeast(90)], unit: 'เดือน'),
    MedalTrack('นักติว', 'ติวครบทุกวิชาที่มีคาบ ทุกสัปดาห์', const [4, 18, 52],
        List.filled(3, tutorBest), unit: 'สัปดาห์'),
    MedalTrack('เข้าใจจริง', 'วิชาที่ทุกหัวข้อ ≥ 80%', const [1, 5, 10],
        List.filled(3, understoodSubjects), unit: 'วิชา'),
    MedalTrack('ส่งงานตรงเวลา', '⭐ ทำทันกำหนดติดกัน', const [10, 30, 60],
        List.filled(3, hwBest), unit: 'ชิ้น'),
  ];
}
