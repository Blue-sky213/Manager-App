/// สกิล (รอบ 8C): ทักษะที่ฝึกเอง ไม่มีตารางจากอาจารย์ ไม่มีเกรด
/// ตั้งเป้าเอง (4 แบบ) · บันทึกทุกรอบที่ฝึก · เก็บผลงานเป็น Portfolio · ประเมินตัวเองรายเดือน
library;

import 'dart:convert';

enum SkillStatus { active, paused, done }

String skillStatusText(SkillStatus s) => switch (s) {
      SkillStatus.active => 'กำลังฝึก',
      SkillStatus.paused => 'พักไว้',
      SkillStatus.done => 'จบแล้ว',
    };

class Skill {
  const Skill({
    this.id = 0,
    required this.name,
    this.icon = '🎯',
    this.colorKey = 'purple',
    this.why,
    this.status = SkillStatus.active,
    required this.startedAt,
    this.doneAt,
  });

  final int id;
  final String name;
  final String icon;
  final String colorKey;

  /// ฝึกไปทำไม (ช่วยตอนท้อ)
  final String? why;
  final SkillStatus status;
  final DateTime startedAt;
  final DateTime? doneAt;

  Skill copyWith({String? name, String? icon, String? colorKey, String? why, SkillStatus? status, DateTime? doneAt, bool clearDone = false}) =>
      Skill(
        id: id,
        name: name ?? this.name,
        icon: icon ?? this.icon,
        colorKey: colorKey ?? this.colorKey,
        why: why ?? this.why,
        status: status ?? this.status,
        startedAt: startedAt,
        doneAt: clearDone ? null : (doneAt ?? this.doneAt),
      );
}

/// เป้า 4 แบบ
/// - volume: ปริมาณ (ชั่วโมงต่อสัปดาห์) · นับจากงานในปฏิทินที่ผูกสกิลนี้ + บันทึก
/// - faster: เร็วขึ้น (ค่าต่อรอบ ยิ่งน้อยยิ่งดี เช่น นาทีที่ใช้ตัดคลิป)
/// - count: จำนวน (ค่าต่อวัน ยิ่งมากยิ่งดี เช่น คำศัพท์)
/// - milestone: ด่าน (เช็กลิสต์)
enum GoalKind { volume, faster, count, milestone }

String goalKindText(GoalKind k) => switch (k) {
      GoalKind.volume => 'ปริมาณ',
      GoalKind.faster => 'เร็วขึ้น',
      GoalKind.count => 'จำนวน',
      GoalKind.milestone => 'ด่าน',
    };

enum GoalStatus { active, met, closed }

class GoalStep {
  const GoalStep(this.title, {this.done = false});
  final String title;
  final bool done;
}

class SkillGoal {
  const SkillGoal({
    this.id = 0,
    required this.skillId,
    required this.kind,
    required this.title,
    this.unit = '',
    this.target = 0,
    this.streak = 3,
    this.status = GoalStatus.active,
    this.steps = const [],
  });

  final int id;
  final int skillId;
  final GoalKind kind;
  final String title;

  /// หน่วยที่ผู้ใช้ตั้ง เช่น นาที · คำ · ชม./สัปดาห์
  final String unit;

  /// ค่าเป้า: volume = ชั่วโมง/สัปดาห์ · faster = ไม่เกินเท่านี้ · count = อย่างน้อยเท่านี้/วัน
  final double target;

  /// ทำได้ติดกันกี่ครั้ง (รอบ / วัน / สัปดาห์) ถึงนับว่าถึงเป้า
  final int streak;
  final GoalStatus status;
  final List<GoalStep> steps;

  SkillGoal copyWith({String? title, String? unit, double? target, int? streak, GoalStatus? status, List<GoalStep>? steps}) => SkillGoal(
        id: id,
        skillId: skillId,
        kind: kind,
        title: title ?? this.title,
        unit: unit ?? this.unit,
        target: target ?? this.target,
        streak: streak ?? this.streak,
        status: status ?? this.status,
        steps: steps ?? this.steps,
      );

  String stepsJson() => jsonEncode([for (final s in steps) {'t': s.title, 'd': s.done}]);

  static List<GoalStep> stepsFrom(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      return [for (final m in jsonDecode(json) as List) GoalStep(m['t'] as String, done: m['d'] == true)];
    } catch (_) {
      return const [];
    }
  }
}

/// 1 รอบที่ฝึก
class SkillLog {
  const SkillLog({
    this.id = 0,
    required this.skillId,
    this.goalId,
    required this.day,
    this.minutes,
    this.value,
    this.rating,
    this.better,
    this.stuck,
    this.next,
    this.skipped = false,
    this.occurrenceId,
  });

  final int id;
  final int skillId;

  /// เป้าที่วัด (faster / count) · null = บันทึกเฉย ๆ
  final int? goalId;
  final DateTime day;

  /// เวลาที่ฝึกจริง
  final int? minutes;

  /// ค่าที่วัดได้รอบนี้ (นาทีที่ใช้ · จำนวน)
  final double? value;

  /// พอใจ 1–5
  final int? rating;
  final String? better;
  final String? stuck;
  final String? next;

  /// ไม่ได้ฝึก (เหตุผลอยู่ใน [stuck])
  final bool skipped;
  final int? occurrenceId;
}

enum SkillFileKind { image, file, link }

/// ผลงาน 1 ชิ้น (รูป · ไฟล์ · ลิงก์) · ⭐ = ผลงานเด่น
class SkillFile {
  const SkillFile({
    this.id = 0,
    required this.skillId,
    this.logId,
    required this.kind,
    required this.path,
    required this.title,
    this.featured = false,
    required this.addedAt,
  });

  final int id;
  final int skillId;
  final int? logId;
  final SkillFileKind kind;

  /// ที่อยู่ไฟล์ในโฟลเดอร์แอป หรือ URL
  final String path;
  final String title;
  final bool featured;
  final DateTime addedAt;

  SkillFile copyWith({bool? featured, String? title}) => SkillFile(
        id: id,
        skillId: skillId,
        logId: logId,
        kind: kind,
        path: path,
        title: title ?? this.title,
        featured: featured ?? this.featured,
        addedAt: addedAt,
      );
}

/// ประเมินตัวเองรายเดือน: ทำได้แล้ว · ยังอ่อน · เป้าถัดไป
class SkillReview {
  const SkillReview({required this.skillId, required this.month, this.can, this.weak, this.nextGoal});
  final int skillId;

  /// YYYY-MM
  final String month;
  final String? can;
  final String? weak;
  final String? nextGoal;
}

String monthKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}';

/// ไอคอนที่เลือกได้ของสกิล
const skillIcons = ['🎬', '✂️', '🇬🇧', '🎨', '🎵', '💻', '📷', '🎮', '✍️', '📚', '🏃', '🎯'];
