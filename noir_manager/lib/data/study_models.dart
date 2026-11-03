/// ข้อมูลฝั่ง Study Tree (ตาม Data Model ในแผนรวม: Subject → Chapter → Subtopic → Assessment)
library;

/// วิชา 1 วิชา เช่น DaVinci Resolve
class Subject {
  const Subject({
    required this.id,
    required this.name,
    required this.importance,
    required this.sessionsPerWeek,
  });

  final int id;
  final String name;

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

/// หัวข้อย่อย 1 ข้อ + คะแนนล่าสุด (คำนวณจากตาราง assessment)
class Subtopic {
  const Subtopic({
    required this.id,
    required this.chapterId,
    required this.name,
    required this.sortOrder,
    required this.examFlag,
    required this.latestScore,
    required this.everBelow60,
  });

  final int id;
  final int chapterId;
  final String name;
  final int sortOrder;

  /// ธง "อาจออกสอบ"
  final bool examFlag;

  /// คะแนนล่าสุด 0–100 · null = ยังไม่เคยประเมิน
  final int? latestScore;

  /// เคยได้ต่ำกว่า 60% อย่างน้อย 1 ครั้ง → โชว์ป้าย "เช็กซ้ำ" (กฎ EZ mode)
  final bool everBelow60;

  factory Subtopic.fromRow(Map<String, Object?> row) => Subtopic(
        id: row['id'] as int,
        chapterId: row['chapter_id'] as int,
        name: row['name'] as String,
        sortOrder: row['sort_order'] as int,
        examFlag: (row['exam_flag'] as int) == 1,
        latestScore: row['latest_score'] as int?,
        everBelow60: (row['ever_below'] as int) == 1,
      );
}

/// บท 1 บท พร้อมหัวข้อย่อยข้างใน (ใช้แสดงผลทั้งก้อน)
class ChapterWithTopics {
  const ChapterWithTopics(this.chapter, this.subtopics);

  final Chapter chapter;
  final List<Subtopic> subtopics;
}
