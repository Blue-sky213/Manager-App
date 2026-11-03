import 'study_models.dart';

/// "สัญญา" ว่าที่เก็บข้อมูลวิชาต้องทำอะไรได้บ้าง
///
/// หน้าจอคุยกับสัญญานี้เท่านั้น ไม่รู้ว่าข้างหลังเป็น SQLite หรืออย่างอื่น
/// → ตอนเทสใช้ MemoryStudyRepository (เก็บใน RAM) แทนได้ ไม่ต้องเปิดฐานข้อมูลจริง
abstract class StudyRepository {
  Future<List<Subject>> subjects();
  Future<int> addSubject(String name, {int importance = 2});
  Future<void> renameSubject(int subjectId, String name);
  Future<void> setSubjectImportance(int subjectId, int importance);
  Future<void> deleteSubject(int subjectId);

  Future<List<ChapterWithTopics>> chapters(int subjectId);
  Future<int> addChapter(int subjectId, String name);
  Future<void> renameChapter(int chapterId, String name);
  Future<void> deleteChapter(int chapterId);

  Future<int> addSubtopic(int chapterId, String name);
  Future<void> renameSubtopic(int subtopicId, String name);
  Future<void> deleteSubtopic(int subtopicId);
  Future<void> setExamFlag(int subtopicId, bool flag);

  /// บันทึกคะแนนประเมินตัวเอง 0–100
  Future<void> addAssessment(int subtopicId, int score, {DateTime? at});
}

/// แปลงความสำคัญ → จำนวนรอบต่อสัปดาห์ (กฎ: สูง/กลาง/น้อย = 3/2/1)
int sessionsForImportance(int importance) => importance.clamp(1, 3);
