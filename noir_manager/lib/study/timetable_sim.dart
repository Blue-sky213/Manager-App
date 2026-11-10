import 'dart:math';

import '../calendar/calendar_models.dart';
import '../data/study_models.dart';
import 'credit_hours.dart';

/// กฎจำลองตารางเรียนแบบมหาลัย (ใช้ทดสอบระบบ):
/// - คาบละไม่เกิน [maxSession] ชม. · ทฤษฎี / ปฏิบัติ แยกคาบกัน
/// - วิชาละไม่เกิน [maxWeek] ชม./สัปดาห์ (เกินจากหน่วยกิต → ตัดส่วนที่มากกว่าก่อน)
/// - หน่วยกิตอ่านไม่ได้ → ไม่ระบุประเภท 3 ชม.
/// - จันทร์–ศุกร์ 08:00–18:00 · พักเที่ยง 12–13 · วิชาเดียวกันพยายามไม่เรียนวันเดียวกัน
/// - ไม่ชนกันเอง และไม่ชนกับคาบที่มีอยู่แล้ว ([busy])
const int maxSession = 2;
const int maxWeek = 4;

class SimSession {
  const SimSession(this.subject, this.weekday, this.startHour, this.hours, this.type);
  final Subject subject;
  final int weekday; // 1 = จันทร์
  final int startHour;
  final int hours;
  final ClassType? type;

  int get endHour => startHour + hours;
}

/// ช่วงเวลาที่ไม่ว่าง: (วัน, นาทีเริ่ม, นาทีจบ)
typedef Busy = ({int weekday, int start, int end});

/// ชั่วโมงต่อสัปดาห์ของวิชาตามกฎ: (ทฤษฎี, ปฏิบัติ, ไม่ระบุ)
({int theory, int lab, int unknown}) simHours(Subject s) {
  final h = parseCreditHours(s.credits);
  if (h == null || h.theory + h.lab == 0) return (theory: 0, lab: 0, unknown: 3);
  var t = h.theory, l = h.lab;
  while (t + l > maxWeek) {
    if (t >= l) {
      t--;
    } else {
      l--;
    }
  }
  return (theory: t, lab: l, unknown: 0);
}

/// แบ่งชั่วโมงเป็นคาบ ≤ maxSession: 3 → [2, 1] · 4 → [2, 2]
List<int> splitHours(int hours) => [
      for (var left = hours; left > 0; left -= maxSession) left < maxSession ? left : maxSession,
    ];

// เวลาเริ่มที่เป็นไปได้ (เช้าก่อน) · ห้ามคร่อมพักเที่ยง และจบไม่เกิน 18:00
const _starts = [9, 10, 8, 13, 14, 15, 16, 11];

bool _fits(int start, int hours) =>
    start + hours <= 18 && !(start < 13 && start + hours > 12);

/// วางคาบของทุกวิชา · [seed] เดิม = ได้ตารางเดิมทุกครั้ง · คืน (คาบที่วางได้, วิชาที่วางไม่ลง)
({List<SimSession> sessions, List<Subject> skipped}) planSimTimetable(
  List<Subject> subjects, {
  List<Busy> busy = const [],
  int seed = 2567,
}) {
  final rnd = Random(seed);
  final taken = [...busy];
  final out = <SimSession>[];
  final skipped = <Subject>[];

  bool free(int wd, int start, int hours) => !taken.any(
      (b) => b.weekday == wd && b.start < (start + hours) * 60 && start * 60 < b.end);

  for (final (i, s) in subjects.indexed) {
    final h = simHours(s);
    final parts = [
      for (final n in splitHours(h.theory)) (n, ClassType.theory),
      for (final n in splitHours(h.lab)) (n, ClassType.lab),
      for (final n in splitHours(h.unknown)) (n, null),
    ];
    final usedDays = <int>{};
    final placed = <SimSession>[];
    for (final (hours, type) in parts) {
      // เริ่มคนละวันในแต่ละวิชา → คาบกระจายทั้งสัปดาห์
      final offset = (i * 2 + rnd.nextInt(5)) % 5;
      final days = [for (var k = 0; k < 5; k++) (offset + k) % 5 + 1];
      SimSession? got;
      // รอบแรก: วันที่วิชานี้ยังไม่มีคาบ · รอบสอง: วันไหนก็ได้ · รอบสุดท้าย: เสาร์
      for (final pass in [0, 1, 2]) {
        final tryDays = pass == 2 ? [6] : [for (final d in days) if (pass == 1 || !usedDays.contains(d)) d];
        for (final d in tryDays) {
          for (final st in _starts) {
            if (_fits(st, hours) && free(d, st, hours)) {
              got = SimSession(s, d, st, hours, type);
              break;
            }
          }
          if (got != null) break;
        }
        if (got != null) break;
      }
      if (got == null) continue;
      placed.add(got);
      usedDays.add(got.weekday);
      taken.add((weekday: got.weekday, start: got.startHour * 60, end: got.endHour * 60));
    }
    if (placed.isEmpty && parts.isNotEmpty) skipped.add(s);
    out.addAll(placed);
  }
  return (sessions: out, skipped: skipped);
}

/// ตรวจตารางตามกฎ · ว่าง = ผ่านทุกข้อ (ใช้ในเทส และไว้เช็กตารางที่ใส่เอง)
List<String> checkSimRules(List<SimSession> sessions) {
  final errors = <String>[];
  final perSubject = <int, int>{};
  for (final s in sessions) {
    if (s.hours > maxSession) errors.add('${s.subject.name}: คาบยาว ${s.hours} ชม.');
    if (!_fits(s.startHour, s.hours)) errors.add('${s.subject.name}: เวลาไม่อยู่ในช่วงเรียน');
    perSubject[s.subject.id] = (perSubject[s.subject.id] ?? 0) + s.hours;
  }
  for (final s in sessions) {
    if ((perSubject[s.subject.id] ?? 0) > maxWeek) {
      errors.add('${s.subject.name}: ${perSubject[s.subject.id]} ชม./สัปดาห์');
      perSubject.remove(s.subject.id);
    }
  }
  for (var i = 0; i < sessions.length; i++) {
    for (var j = i + 1; j < sessions.length; j++) {
      final a = sessions[i], b = sessions[j];
      if (a.weekday == b.weekday && a.startHour < b.endHour && b.startHour < a.endHour) {
        errors.add('ชน: ${a.subject.name} กับ ${b.subject.name}');
      }
    }
  }
  return errors;
}

/// คาบจำลอง → งานในปฏิทิน (ซ้ำทุกสัปดาห์ ตลอด [from]–[to])
NewActivity simToActivity(SimSession s, {required int categoryId, required DateTime from, required DateTime to}) =>
    NewActivity(
      name: 'เรียน · ${s.subject.name}',
      categoryId: categoryId,
      importance: 3,
      timed: true,
      day: from,
      startMinute: s.startHour * 60,
      durationMin: s.hours * 60,
      repeat: RepeatKind.weekly,
      weekdays: {s.weekday},
      endDate: to,
      subjectId: s.subject.id,
      kind: ActivityKind.classSession,
      classInfo: ClassInfo(
        type: s.type,
        section: switch (s.type) { ClassType.theory => 'S.1', ClassType.lab => 'L.1', null => null },
      ),
    );

/// setting ที่จำ id ของคาบจำลอง → ลบทิ้งได้ทั้งชุด โดยไม่แตะคาบที่นัวร์ใส่เอง
const simIdsKey = 'sim_timetable_ids';
