/// สถิติเวลาเลิกเรียนจริงเทียบกับตาราง (เลิกเร็ว / ตรงเวลา / เลิกช้า)
library;

import 'calendar_models.dart';

/// ต่างกันไม่เกินกี่นาทีถึงนับว่า "ตรงเวลา"
const int onTimeTolerance = 5;

class ClassTimeStats {
  const ClassTimeStats({
    required this.count,
    required this.early,
    required this.onTime,
    required this.late,
    required this.averageDiff,
    required this.maxLate,
    required this.maxEarly,
  });

  /// จำนวนคาบที่บันทึกเวลาเลิกจริงแล้ว
  final int count;
  final int early;
  final int onTime;
  final int late;

  /// เฉลี่ยกี่นาที (+ = เลิกช้า · − = เลิกก่อน)
  final double averageDiff;

  /// เลิกช้าสุด / เลิกเร็วสุด (นาที, เป็นบวกทั้งคู่)
  final int maxLate;
  final int maxEarly;

  static const empty = ClassTimeStats(
      count: 0, early: 0, onTime: 0, late: 0, averageDiff: 0, maxLate: 0, maxEarly: 0);
}

/// คิดจากคาบที่ทำแล้วและมีเวลาเลิกจริง
ClassTimeStats classTimeStats(Iterable<Occurrence> items) {
  final diffs = [
    for (final o in items)
      if (o.status == OccurrenceStatus.done && o.endDiffMinutes != null) o.endDiffMinutes!,
  ];
  if (diffs.isEmpty) return ClassTimeStats.empty;
  return ClassTimeStats(
    count: diffs.length,
    early: diffs.where((d) => d < -onTimeTolerance).length,
    onTime: diffs.where((d) => d.abs() <= onTimeTolerance).length,
    late: diffs.where((d) => d > onTimeTolerance).length,
    averageDiff: diffs.reduce((a, b) => a + b) / diffs.length,
    maxLate: diffs.fold(0, (m, d) => d > m ? d : m),
    maxEarly: diffs.fold(0, (m, d) => -d > m ? -d : m),
  );
}

/// "+12 นาที" / "−8 นาที" / "ตรงเวลา"
String diffText(num minutes) {
  final m = minutes.round();
  if (m.abs() <= onTimeTolerance) return 'ตรงเวลา';
  return m > 0 ? 'ช้า $m นาที' : 'ก่อน ${-m} นาที';
}
