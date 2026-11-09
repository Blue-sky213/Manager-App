/// ตรวจชั่วโมงคาบเรียนกับหน่วยกิตแบบไทย เช่น "3(2-2-5)"
/// = 3 หน่วยกิต · ทฤษฎี 2 ชม. · ปฏิบัติ 2 ชม. · ศึกษาเอง 5 ชม. ต่อสัปดาห์
library;

import '../calendar/calendar_models.dart';

class CreditHours {
  const CreditHours({required this.credits, required this.theory, required this.lab, required this.self});

  final int credits;
  final int theory;
  final int lab;

  /// ชั่วโมงศึกษาเอง/สัปดาห์ → ใช้วางเวลาติวต่อ
  final int self;
}

/// "3(2-2-5)" → CreditHours · รูปแบบอื่น เช่น "1(240 ชม.)" → null (ตรวจไม่ได้ ไม่ใช่ผิด)
CreditHours? parseCreditHours(String? text) {
  final m = RegExp(r'^\s*(\d+)\s*\(\s*(\d+)\s*-\s*(\d+)\s*-\s*(\d+)\s*\)').firstMatch(text ?? '');
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  return CreditHours(credits: g(1), theory: g(2), lab: g(3), self: g(4));
}

/// นาทีเรียนต่อสัปดาห์ที่ใส่ไว้ แยกตามประเภท
class WeeklyClassMinutes {
  const WeeklyClassMinutes({this.theory = 0, this.lab = 0, this.unknown = 0});

  final int theory;
  final int lab;

  /// คาบที่ยังไม่ระบุประเภท (คาบก่อน v11)
  final int unknown;

  int get total => theory + lab + unknown;
}

/// รวมนาทีเรียนต่อสัปดาห์จากคาบประจำ (ซ้ำทุกสัปดาห์) ของวิชาหนึ่ง
///
/// คาบเดียวกันที่แยกเป็นหลายช่วงวันที่ (เช่น ก่อน/หลังสอบกลางภาค) นับครั้งเดียว
/// เพราะเป็นคาบเดิมในสัปดาห์ ไม่ใช่คาบเพิ่ม
WeeklyClassMinutes weeklyClassMinutes(Iterable<Activity> activities) {
  final seen = <String>{};
  var theory = 0, lab = 0, unknown = 0;
  for (final a in activities) {
    if (a.kind != ActivityKind.classSession || a.repeat != RepeatKind.weekly || !a.timed) continue;
    final key = '${weekdaysToText(a.weekdays)}|${a.startMinute}|${a.durationMin}|${a.classInfo.type}';
    if (!seen.add(key)) continue;
    final minutes = a.weekdays.length * (a.durationMin ?? 0);
    switch (a.classInfo.type) {
      case ClassType.theory:
        theory += minutes;
      case ClassType.lab:
        lab += minutes;
      case null:
        unknown += minutes;
    }
  }
  return WeeklyClassMinutes(theory: theory, lab: lab, unknown: unknown);
}

enum HourStatus { ok, short, over }

/// ผลตรวจ 1 ประเภท: ใส่ไว้ [have] นาที เทียบกับที่หน่วยกิตกำหนด [need] นาที
class HourCheck {
  const HourCheck(this.have, this.need);
  final int have;
  final int need;

  HourStatus get status => have == need ? HourStatus.ok : (have < need ? HourStatus.short : HourStatus.over);
}

class CreditCheck {
  const CreditCheck({required this.hours, required this.theory, required this.lab, required this.unknown});

  final CreditHours hours;
  final HourCheck theory;
  final HourCheck lab;

  /// นาทีของคาบที่ยังไม่ระบุประเภท
  final int unknown;

  /// ยังไม่ระบุประเภทเลย แต่ชั่วโมงรวมตรงกับ ทฤษฎี + ปฏิบัติ → น่าจะครบ แค่ต้องตั้งประเภท
  bool get totalMatchesOnly =>
      unknown > 0 && theory.have + lab.have + unknown == (hours.theory + hours.lab) * 60;

  bool get allOk => unknown == 0 && theory.status == HourStatus.ok && lab.status == HourStatus.ok;
}

/// ตรวจวิชาที่มีหน่วยกิต [credits] กับคาบ [activities] · หน่วยกิตอ่านไม่ได้ → null
CreditCheck? checkCredits(String? credits, Iterable<Activity> activities) {
  final h = parseCreditHours(credits);
  if (h == null) return null;
  final w = weeklyClassMinutes(activities);
  return CreditCheck(
    hours: h,
    theory: HourCheck(w.theory, h.theory * 60),
    lab: HourCheck(w.lab, h.lab * 60),
    unknown: w.unknown,
  );
}

/// 90 → "1.5" · 120 → "2"
String hoursText(int minutes) {
  final h = minutes / 60;
  return h == h.roundToDouble() ? '${h.round()}' : h.toStringAsFixed(1);
}
