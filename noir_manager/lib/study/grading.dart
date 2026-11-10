/// ระบบเกรด: คะแนนย่อย → คะแนนรวม → เกรด → GPA
///
/// แยกเป็นฟังก์ชันล้วน (ไม่แตะ DB / หน้าจอ) เพื่อเทสได้ตรง ๆ
library;

/// ช่วงเกรด 1 ขั้น: ได้ตั้งแต่ [min] คะแนน (จาก 100) ขึ้นไป
class GradeBand {
  const GradeBand(this.letter, this.min, this.points);
  final String letter;
  final double min;
  final double points;
}

/// ค่าเริ่มต้นตามตาราง มก. — อาจารย์ตัดต่างไปแก้ได้ทุกวิชา
const List<GradeBand> kuGradeScale = [
  GradeBand('A', 80, 4.0),
  GradeBand('B+', 75, 3.5),
  GradeBand('B', 70, 3.0),
  GradeBand('C+', 65, 2.5),
  GradeBand('C', 60, 2.0),
  GradeBand('D+', 55, 1.5),
  GradeBand('D', 50, 1.0),
];

/// แต้มของแต่ละเกรด (F = 0) · ใช้ตอนคิด GPA
double? gradePoints(String letter) => switch (letter) {
      'A' => 4.0,
      'B+' => 3.5,
      'B' => 3.0,
      'C+' => 2.5,
      'C' => 2.0,
      'D+' => 1.5,
      'D' => 1.0,
      'F' => 0.0,
      _ => null, // S/U หรือยังไม่มีเกรด → ไม่นับ
    };

/// เก็บช่วงเกรดลง DB เป็นข้อความสั้น เช่น "A:80,B+:75,..."
String encodeScale(List<GradeBand> scale) =>
    scale.map((b) => '${b.letter}:${_num(b.min)}').join(',');

/// อ่านกลับ · ข้อความเสีย/ว่าง → ใช้ตาราง มก.
List<GradeBand> parseScale(String? text) {
  if (text == null || text.trim().isEmpty) return kuGradeScale;
  final out = <GradeBand>[];
  for (final part in text.split(',')) {
    final kv = part.split(':');
    if (kv.length != 2) return kuGradeScale;
    final min = double.tryParse(kv[1].trim());
    final pts = gradePoints(kv[0].trim());
    if (min == null || pts == null) return kuGradeScale;
    out.add(GradeBand(kv[0].trim(), min, pts));
  }
  out.sort((a, b) => b.min.compareTo(a.min));
  return out.isEmpty ? kuGradeScale : out;
}

/// คะแนนต่ำสุดของ D (= เกณฑ์ตัด F + 1) เช่น อาจารย์ตัด F ที่ 49 → D เริ่ม 50
List<GradeBand> withFCut(List<GradeBand> scale, double fCut) => [
      for (final b in scale)
        if (b.letter == 'D') GradeBand('D', fCut + 1, b.points) else b,
    ];

/// เกณฑ์ตัด F ปัจจุบัน = ขั้นต่ำสุดของช่วง − 1
double fCutOf(List<GradeBand> scale) => scale.isEmpty ? 49 : scale.last.min - 1;

String letterFor(double percent, List<GradeBand> scale) {
  for (final b in scale) {
    if (percent >= b.min - 1e-9) return b.letter;
  }
  return 'F';
}

/// คะแนนย่อย 1 ชิ้น เช่น "งาน 1" เต็ม 5 ได้ 4 · got = null = ยังไม่ได้คะแนน
class GradeItem {
  const GradeItem({required this.id, required this.name, required this.full, this.got});
  final int id;
  final String name;
  final double full;
  final double? got;
}

/// ส่วนของคะแนน เช่น "งาน" เก็บ 20 คะแนน · รวมคะแนนดิบของทุกชิ้นแล้วย่อ/ขยายเป็น [weight]
/// (อาจารย์บอก "สอบย่อยเต็ม 60 เก็บ 15" → ชิ้นละเต็มรวม 60 · weight 15)
class GradePart {
  const GradePart({required this.id, required this.name, required this.weight, this.items = const []});
  final int id;
  final String name;
  final double weight;
  final List<GradeItem> items;

  double get rawFull => items.fold(0, (s, i) => s + i.full);
  bool get anyGraded => items.any((i) => i.got != null);
  bool get allGraded => items.isNotEmpty && items.every((i) => i.got != null);

  /// คะแนนที่เก็บได้แล้ว (หน่วยเดียวกับ weight)
  double get earned {
    final full = rawFull;
    if (full <= 0) return 0;
    final got = items.fold<double>(0, (s, i) => s + (i.got ?? 0));
    return got / full * weight;
  }

  /// คะแนนเต็มของชิ้นที่ให้คะแนนแล้ว (ส่วนที่ "ผ่านไปแล้ว")
  double get decided {
    final full = rawFull;
    if (full <= 0) return 0;
    final f = items.where((i) => i.got != null).fold<double>(0, (s, i) => s + i.full);
    return f / full * weight;
  }
}

/// เงื่อนไขได้ F ทันที
class GradeFlags {
  const GradeFlags({this.absentOver = false, this.missedExam = false});
  final bool absentOver;
  final bool missedExam;
}

class GradeResult {
  const GradeResult({
    required this.earned,
    required this.decided,
    required this.totalWeight,
    required this.letter,
    required this.complete,
    this.reason,
  });

  /// คะแนนที่ได้แล้ว / คะแนนที่ตัดสินไปแล้ว / คะแนนเต็มของวิชา
  final double earned;
  final double decided;
  final double totalWeight;

  /// เกรด · ยังไม่ครบทุกชิ้น = เกรดถ้าที่เหลือได้ 0 ([complete] = false)
  final String letter;
  final bool complete;

  /// ทำไมได้ F ทันที (null = คิดตามคะแนน)
  final String? reason;

  double get remaining => (totalWeight - decided).clamp(0, double.infinity);

  /// คะแนนเทียบ 100 (เผื่ออาจารย์ให้คะแนนรวมไม่เท่ากับ 100)
  double get percent => totalWeight <= 0 ? 0 : earned / totalWeight * 100;
}

GradeResult computeGrade(List<GradePart> parts, List<GradeBand> scale,
    [GradeFlags flags = const GradeFlags()]) {
  final total = parts.fold<double>(0, (s, p) => s + p.weight);
  final earned = parts.fold<double>(0, (s, p) => s + p.earned);
  final decided = parts.fold<double>(0, (s, p) => s + p.decided);
  final complete = parts.isNotEmpty && parts.every((p) => p.allGraded);
  final reason = flags.absentOver
      ? 'ขาดเรียนเกิน 20% → F'
      : flags.missedExam
          ? 'ขาดสอบ → F'
          : null;
  final pct = total <= 0 ? 0.0 : earned / total * 100;
  return GradeResult(
    earned: earned,
    decided: decided,
    totalWeight: total,
    letter: reason != null ? 'F' : letterFor(pct, scale),
    complete: complete || reason != null,
    reason: reason,
  );
}

/// "ต้องได้อีกเท่าไหร่ถึงจะได้เกรดนี้" จากคะแนนที่เหลือ
/// null = ได้แน่นอนแล้ว · double.infinity = ไม่ทันแล้ว
double? neededFor(GradeResult r, GradeBand band) {
  if (r.reason != null) return double.infinity;
  final needPct = band.min;
  final needPoints = needPct / 100 * r.totalWeight - r.earned;
  if (needPoints <= 1e-9) return null;
  if (needPoints > r.remaining + 1e-9) return double.infinity;
  return needPoints;
}

/// GPA = ผลรวม (แต้ม × หน่วยกิต) ÷ หน่วยกิตที่นับเกรด · วิชาไม่มีแต้ม (S/U, ยังไม่มีเกรด) ไม่นับ
double? gpa(Iterable<(int credits, String letter)> rows) {
  var sum = 0.0;
  var credits = 0;
  for (final (cr, letter) in rows) {
    final pts = gradePoints(letter);
    if (pts == null || cr <= 0) continue;
    sum += pts * cr;
    credits += cr;
  }
  return credits == 0 ? null : sum / credits;
}

String _num(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// แสดงคะแนนสั้น ๆ: 17.0 → "17" · 12.5 → "12.5"
String fmtScore(double v) {
  final r = (v * 10).round() / 10;
  return _num(r);
}

/// ตั้งค่าเกรดของวิชา 1 วิชา
class GradeSetup {
  const GradeSetup({this.scale = kuGradeScale, this.flags = const GradeFlags(), this.official});
  final List<GradeBand> scale;
  final GradeFlags flags;

  /// เกรดจริงที่ประกาศแล้ว (หรือ S / U) · มีค่า = ใช้อันนี้แทนเกรดที่คำนวณ
  final String? official;
}

/// เกรดที่ใช้คิด GPA: เกรดจริงก่อน · ไม่มี → เกรดที่คำนวณ (เมื่อมีคะแนนแล้ว)
String effectiveLetter(GradeSetup setup, List<GradePart> parts) {
  if (setup.official case final o? when o.isNotEmpty) return o;
  if (!parts.any((p) => p.anyGraded) && !setup.flags.absentOver && !setup.flags.missedExam) return '—';
  return computeGrade(parts, setup.scale, setup.flags).letter;
}
