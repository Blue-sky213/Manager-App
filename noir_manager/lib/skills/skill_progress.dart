/// คิดความคืบหน้าของเป้า (ไม่มี UI · เทสได้ตรง ๆ)
library;

import 'skill_models.dart';

class GoalProgress {
  const GoalProgress({
    required this.current,
    this.best,
    required this.run,
    required this.met,
    this.series = const [],
    this.ratio,
  });

  /// ค่าล่าสุด (ข้อความพร้อมหน่วย)
  final String current;
  final String? best;

  /// ทำได้ตามเป้าติดกันตอนนี้กี่ครั้ง (รอบ / วัน / สัปดาห์)
  final int run;

  /// ถึงเป้าแล้ว (ติดกันครบ) → แอปถาม จบ / พัก / ยกระดับเป้า
  final bool met;

  /// จุดในกราฟ (วัน, ค่า)
  final List<(DateTime, double)> series;

  /// สัดส่วนสำเร็จของช่วงนี้ (0–1) · volume = สัปดาห์นี้ · milestone = ด่านที่ผ่าน
  final double? ratio;
}

DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);
DateTime mondayOfWeek(DateTime d) => _day(d).subtract(Duration(days: d.weekday - 1));

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

/// แสดงค่าพร้อมหน่วย · หน่วย "นาที" ตั้งแต่ 60 ขึ้นไป = ชั่วโมง:นาที
String fmtGoalValue(double v, String unit) {
  if (unit == 'นาที' && v >= 60) {
    final m = v.round();
    return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')} ชม.';
  }
  return unit.isEmpty ? _num(v) : '${_num(v)} $unit';
}

/// [practiceMinutes] = นาทีที่ทำแล้วจากปฏิทิน (งานที่ผูกสกิลนี้) ต่อวัน
GoalProgress goalProgress(
  SkillGoal g,
  List<SkillLog> logs, {
  Map<DateTime, int> practiceMinutes = const {},
  required DateTime today,
}) {
  final t = _day(today);
  switch (g.kind) {
    case GoalKind.faster:
      final pts = [
        for (final l in logs)
          if (l.goalId == g.id && l.value != null && !l.skipped) l
      ]..sort((a, b) => a.day != b.day ? a.day.compareTo(b.day) : a.id - b.id);
      var run = 0;
      for (final l in pts.reversed) {
        if (l.value! > g.target) break;
        run++;
      }
      final best = pts.isEmpty ? null : pts.map((l) => l.value!).reduce((a, b) => a < b ? a : b);
      return GoalProgress(
        current: pts.isEmpty ? '—' : fmtGoalValue(pts.last.value!, g.unit),
        best: best == null ? null : fmtGoalValue(best, g.unit),
        run: run,
        met: run >= g.streak,
        series: [for (final l in pts) (l.day, l.value!)],
      );

    case GoalKind.count:
      final perDay = <DateTime, double>{};
      for (final l in logs) {
        if (l.goalId == g.id && l.value != null && !l.skipped) {
          perDay[_day(l.day)] = (perDay[_day(l.day)] ?? 0) + l.value!;
        }
      }
      // วันนี้ยังไม่จบ: ถ้ายังไม่ครบ เริ่มนับจากเมื่อวาน
      var d = (perDay[t] ?? 0) >= g.target ? t : t.subtract(const Duration(days: 1));
      var run = 0;
      while ((perDay[d] ?? 0) >= g.target && g.target > 0) {
        run++;
        d = d.subtract(const Duration(days: 1));
      }
      final days = perDay.keys.toList()..sort();
      return GoalProgress(
        current: '${fmtGoalValue(perDay[t] ?? 0, g.unit)} วันนี้',
        run: run,
        met: run >= g.streak,
        series: [for (final k in days) (k, perDay[k]!)],
        ratio: g.target <= 0 ? null : ((perDay[t] ?? 0) / g.target).clamp(0, 1).toDouble(),
      );

    case GoalKind.volume:
      // นาทีต่อสัปดาห์ = งานในปฏิทินที่ทำแล้ว + บันทึกที่ไม่ได้มาจากงานในปฏิทิน (กันนับซ้ำ)
      final perWeek = <DateTime, int>{};
      practiceMinutes.forEach((day, m) => perWeek[mondayOfWeek(day)] = (perWeek[mondayOfWeek(day)] ?? 0) + m);
      for (final l in logs) {
        if (l.occurrenceId == null && l.minutes != null && !l.skipped) {
          perWeek[mondayOfWeek(l.day)] = (perWeek[mondayOfWeek(l.day)] ?? 0) + l.minutes!;
        }
      }
      final need = g.target * 60;
      final thisWeek = mondayOfWeek(t);
      var w = (perWeek[thisWeek] ?? 0) >= need ? thisWeek : thisWeek.subtract(const Duration(days: 7));
      var run = 0;
      while (need > 0 && (perWeek[w] ?? 0) >= need) {
        run++;
        w = w.subtract(const Duration(days: 7));
      }
      final weeks = perWeek.keys.toList()..sort();
      final now = (perWeek[thisWeek] ?? 0) / 60;
      return GoalProgress(
        current: '${_num(now)} / ${_num(g.target)} ชม. สัปดาห์นี้',
        run: run,
        met: run >= g.streak,
        series: [for (final k in weeks) (k, perWeek[k]! / 60)],
        ratio: g.target <= 0 ? null : (now / g.target).clamp(0, 1).toDouble(),
      );

    case GoalKind.milestone:
      final done = g.steps.where((s) => s.done).length;
      return GoalProgress(
        current: '$done / ${g.steps.length} ด่าน',
        run: done,
        met: g.steps.isNotEmpty && done == g.steps.length,
        ratio: g.steps.isEmpty ? null : done / g.steps.length,
      );
  }
}

/// คำอธิบายเงื่อนไขถึงเป้า (โชว์ใต้เป้า)
String goalRuleText(SkillGoal g) => switch (g.kind) {
      GoalKind.faster => '≤ ${fmtGoalValue(g.target, g.unit)} · ${g.streak} รอบติด',
      GoalKind.count => '≥ ${fmtGoalValue(g.target, g.unit)}/วัน · ${g.streak} วันติด',
      GoalKind.volume => '${_num(g.target)} ชม./สัปดาห์ · ${g.streak} สัปดาห์ติด',
      GoalKind.milestone => 'ผ่านครบทุกด่าน',
    };
