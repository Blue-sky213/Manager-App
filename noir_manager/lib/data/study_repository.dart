import '../study/mastery.dart';
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

  /// เลือกจำนวนรอบติวเอง (ถูกบีบให้อยู่ในช่วงของความสำคัญ)
  Future<void> setSessionsPerWeek(int subjectId, int sessions);
  Future<void> deleteSubject(int subjectId);

  /// เส้นความสัมพันธ์ทั้งหมด (from ต้องเรียนก่อน to)
  Future<List<SubjectLink>> subjectLinks();

  /// เพิ่มเส้น · มีอยู่แล้ว / ชี้หาตัวเอง → ไม่ทำอะไร
  Future<void> addSubjectLink(int fromId, int toId);
  Future<void> removeSubjectLink(int fromId, int toId);

  /// ตำแหน่งในแผนการเรียน: รหัส · หน่วยกิต · ปี · เทอม
  Future<void> setSubjectPlan(int subjectId,
      {String? code, String? credits, int? year, int? term});

  /// สีประจำวิชา (ลำดับใน subjectPalette)
  Future<void> setSubjectColor(int subjectId, int colorIndex);

  /// ความยาวรอบติวของวิชา (นาที)
  Future<void> setTutorMinutes(int subjectId, int minutes);

  Future<List<ChapterWithTopics>> chapters(int subjectId);
  Future<int> addChapter(int subjectId, String name);
  Future<void> renameChapter(int chapterId, String name);
  Future<void> deleteChapter(int chapterId);
  Future<void> setChapterKind(int chapterId, ChapterKind kind);
  Future<void> setChapterStatus(int chapterId, ChapterStatus status);

  /// บันทึกว่ารอบติว [occurrenceId] ติวบท [chapterId] ไปถึงสถานะ [status]
  Future<void> logTutor(int occurrenceId, int? chapterId, ChapterStatus status);

  /// บทนี้ติวไปแล้วกี่รอบ (นับจาก tutor_log)
  Future<int> tutorCount(int chapterId);

  Future<int> addSubtopic(int chapterId, String name);
  Future<void> renameSubtopic(int subtopicId, String name);
  Future<void> deleteSubtopic(int subtopicId);
  Future<void> setExamFlag(int subtopicId, bool flag);

  /// โหมดการให้คะแนน EZ / Advanced (จำไว้ในฐานข้อมูล)
  Future<GradingMode> gradingMode();
  Future<void> setGradingMode(GradingMode mode);

  /// ค่าตั้งค่าทั่วไปแบบ key → value (null = ยังไม่เคยตั้ง)
  Future<String?> getSetting(String key);
  Future<void> setSetting(String key, String value);

  /// ทำให้คะแนนก่อน [from] เป็นโมฆะ: ไม่นำมาเฉลี่ย ไม่นับว่าเคยตก (ข้อมูลยังอยู่ในไฟล์)
  Future<void> resetHistoryFrom(int subtopicId, DateTime from);

  /// ประวัติคะแนนทุกรอบของหัวข้อ เรียงเก่า → ใหม่ (รวมรอบโมฆะ)
  Future<List<ScoreRecord>> scoreHistory(int subtopicId);
  Future<void> updateAssessment(int assessmentId, int score);
  Future<void> deleteAssessment(int assessmentId);

  /// ยกเลิกโมฆะ: นำคะแนนทุกรอบกลับมาคิดเหมือนเดิม
  Future<void> undoReset(int subtopicId);

  /// บันทึกคะแนนประเมินตัวเอง 0–100
  Future<void> addAssessment(int subtopicId, int score, {DateTime? at});
}

/// แปลงความสำคัญ → จำนวนรอบต่อสัปดาห์ (กฎ: สูง/กลาง/น้อย = 3/2/1)
/// ช่วงรอบติวต่อสัปดาห์ที่เลือกได้ (แผน v0.2): น้อย 1–2 · กลาง 2–3 · สูง 3–7
(int, int) sessionRange(int importance) => switch (importance) {
      >= 3 => (3, 7),
      2 => (2, 3),
      _ => (1, 2),
    };

/// ค่าเริ่มต้นตอนสร้าง/เปลี่ยนความสำคัญ: น้อย 2 · กลาง 2 · สูง 3
int sessionsForImportance(int importance) => importance >= 3 ? 3 : 2;

/// บีบจำนวนรอบให้อยู่ในช่วงของความสำคัญนั้น
int clampSessions(int importance, int sessions) {
  final (lo, hi) = sessionRange(importance);
  return sessions.clamp(lo, hi);
}
