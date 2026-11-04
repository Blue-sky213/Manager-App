/// ข้อมูลฝั่ง Study Tree (ตาม Data Model ในแผนรวม: Subject → Chapter → Subtopic → Assessment)
library;

/// วิชา 1 วิชา เช่น DaVinci Resolve
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.importance,
    required this.sessionsPerWeek,
    this.code,
    this.credits,
    this.planYear,
    this.planTerm,
  });

  final int id;
  final String name;

  /// รหัสวิชา เช่น 060233115 · หน่วยกิต เช่น 3(2-2-5)
  final String? code;
  final String? credits;

  /// อยู่ในแผนการเรียน ปีที่ / เทอมที่ (3 = ภาคฤดูร้อน) · null = ยังไม่จัด
  final int? planYear;
  final int? planTerm;

  /// เลขหน้าวงเล็บ = หน่วยกิตรวม เช่น "3(2-2-5)" → 3
  int get creditUnits => int.tryParse(RegExp(r'^\d+').stringMatch(credits ?? '') ?? '') ?? 0;

  Subject copyWith({
    String? name,
    int? importance,
    int? sessionsPerWeek,
    String? code,
    String? credits,
    int? planYear,
    int? planTerm,
  }) =>
      Subject(
        id: id,
        name: name ?? this.name,
        importance: importance ?? this.importance,
        sessionsPerWeek: sessionsPerWeek ?? this.sessionsPerWeek,
        code: code ?? this.code,
        credits: credits ?? this.credits,
        planYear: planYear ?? this.planYear,
        planTerm: planTerm ?? this.planTerm,
      );

  /// ความสำคัญ 3 = สูง, 2 = กลาง, 1 = น้อย (ตามกฎ hard/medium/easy = 3/2/1 รอบต่อสัปดาห์)
  final int importance;
  final int sessionsPerWeek;

  String get importanceLabel => switch (importance) {
        3 => 'สูง',
        2 => 'กลาง',
        _ => 'น้อย',
      };

  /// แปลง 1 แถวจากฐานข้อมูล (Map) เป็น Subject
  factory Subject.fromRow(Map<String, Object?> row) => Subject(
        id: row['id'] as int,
        name: row['name'] as String,
        importance: row['importance'] as int,
        sessionsPerWeek: row['sessions_per_week'] as int,
        code: row['code'] as String?,
        credits: row['credits'] as String?,
        planYear: row['plan_year'] as int?,
        planTerm: row['plan_term'] as int?,
      );
}

/// บทของวิชา เช่น "บท 1 · Interface & Media"
class Chapter {
  const Chapter({
    required this.id,
    required this.subjectId,
    required this.name,
    required this.sortOrder,
  });

  final int id;
  final int subjectId;
  final String name;
  final int sortOrder;

  factory Chapter.fromRow(Map<String, Object?> row) => Chapter(
        id: row['id'] as int,
        subjectId: row['subject_id'] as int,
        name: row['name'] as String,
        sortOrder: row['sort_order'] as int,
      );
}

/// คะแนน 1 รอบ: ได้กี่ % เมื่อไหร่ (id = แถวในตาราง assessment)
class ScorePoint {
  const ScorePoint(this.id, this.score, this.at);

  final int id;
  final int score;
  final DateTime at;
}

/// แถวในตารางประวัติคะแนน (รวมรอบที่เป็นโมฆะด้วย)
class ScoreRecord {
  const ScoreRecord({
    required this.id,
    required this.score,
    required this.at,
    required this.voided,
  });

  final int id;
  final int score;
  final DateTime at;

  /// true = โมฆะ (ไม่นำมาคิด แต่ยังเก็บไว้)
  final bool voided;
}

/// หัวข้อย่อย 1 ข้อ + ประวัติคะแนน (นับตั้งแต่ "เริ่มนับใหม่" ครั้งล่าสุด)
class Subtopic {
  const Subtopic({
    required this.id,
    required this.chapterId,
    required this.name,
    required this.sortOrder,
    required this.examFlag,
    required this.scores,
  });

  final int id;
  final int chapterId;
  final String name;
  final int sortOrder;

  /// ธง "อาจออกสอบ"
  final bool examFlag;

  /// คะแนนทุกรอบ เรียงจากเก่า → ใหม่
  /// (คะแนนก่อนวันที่ถูกทำเป็นโมฆะจะไม่อยู่ในนี้)
  final List<ScorePoint> scores;

  /// คะแนนล่าสุด 0–100 · null = ยังไม่เคยประเมิน (ใช้ในโหมด EZ)
  int? get latestScore => scores.isEmpty ? null : scores.last.score;

  /// ค่าเฉลี่ยทุกรอบ ปัดเป็นจำนวนเต็ม (ใช้ในโหมด Advanced)
  int? get averageScore => scores.isEmpty
      ? null
      : (scores.map((s) => s.score).reduce((a, b) => a + b) / scores.length)
          .round();

  /// เคยได้ต่ำกว่า 60% อย่างน้อย 1 ครั้ง
  bool get everBelow60 => scores.any((s) => s.score < 60);

  /// 2 รอบล่าสุดได้ "ดี" (>80) ทั้งคู่
  bool get greenTwice =>
      scores.length >= 2 &&
      scores[scores.length - 1].score > 80 &&
      scores[scores.length - 2].score > 80;
}

/// บท 1 บท พร้อมหัวข้อย่อยข้างใน (ใช้แสดงผลทั้งก้อน)
class ChapterWithTopics {
  const ChapterWithTopics(this.chapter, this.subtopics);

  final Chapter chapter;
  final List<Subtopic> subtopics;
}
