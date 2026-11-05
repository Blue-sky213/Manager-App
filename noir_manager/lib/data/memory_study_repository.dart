import '../study/mastery.dart';
import 'seed_data.dart';
import 'study_models.dart';
import 'study_repository.dart';

/// StudyRepository แบบเก็บใน RAM (ปิดแอปแล้วหาย) — ใช้ในการเทส
/// กฎทุกข้อต้องเหมือน SqliteStudyRepository
class MemoryStudyRepository implements StudyRepository {
  MemoryStudyRepository();

  /// สร้างพร้อมข้อมูล DaVinci เหมือนตอนเปิดแอปครั้งแรก
  factory MemoryStudyRepository.seeded() {
    final repo = MemoryStudyRepository();
    final subjectId = repo._insertSubject(seedSubjectName, seedSubjectImportance);
    for (final seed in seedChapters) {
      final chapterId = repo._insertChapter(subjectId, seed.name);
      for (final name in seed.subtopics) {
        repo._insertSubtopic(chapterId, name);
      }
    }
    return repo;
  }

  int _nextId = 1;
  GradingMode _mode = GradingMode.ez;
  final List<Subject> _subjects = [];
  final List<Chapter> _chapters = [];
  final List<_TopicRow> _topics = [];
  final List<_ScoreRow> _scores = [];

  int _insertSubject(String name, int importance) {
    final id = _nextId++;
    _subjects.add(Subject(
      id: id,
      name: name,
      importance: importance,
      sessionsPerWeek: sessionsForImportance(importance),
    ));
    return id;
  }

  int _insertChapter(int subjectId, String name) {
    final id = _nextId++;
    final order = _chapters.where((c) => c.subjectId == subjectId).length + 1;
    _chapters.add(Chapter(id: id, subjectId: subjectId, name: name, sortOrder: order));
    return id;
  }

  int _insertSubtopic(int chapterId, String name) {
    final id = _nextId++;
    final order = _topics.where((t) => t.chapterId == chapterId).length + 1;
    _topics.add(_TopicRow(id, chapterId, name, order));
    return id;
  }

  Subtopic _toSubtopic(_TopicRow t) {
    final cleared = t.clearedAt;
    final mine = _scores
        .where((s) => s.subtopicId == t.id)
        .where((s) => cleared == null || !s.at.isBefore(cleared))
        .toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return Subtopic(
      id: t.id,
      chapterId: t.chapterId,
      name: t.name,
      sortOrder: t.sortOrder,
      examFlag: t.examFlag,
      scores: [for (final s in mine) ScorePoint(s.id, s.score, s.at)],
    );
  }

  @override
  Future<List<Subject>> subjects() async => List.of(_subjects);

  @override
  Future<int> addSubject(String name, {int importance = 2}) async =>
      _insertSubject(name, importance);

  @override
  Future<void> renameSubject(int subjectId, String name) async {
    final i = _subjects.indexWhere((s) => s.id == subjectId);
    final old = _subjects[i];
    _subjects[i] = old.copyWith(name: name);
  }

  @override
  Future<void> setSessionsPerWeek(int subjectId, int sessions) async {
    final i = _subjects.indexWhere((s) => s.id == subjectId);
    final old = _subjects[i];
    _subjects[i] = old.copyWith(sessionsPerWeek: clampSessions(old.importance, sessions));
  }

  @override
  Future<void> setSubjectImportance(int subjectId, int importance) async {
    final i = _subjects.indexWhere((s) => s.id == subjectId);
    final old = _subjects[i];
    _subjects[i] = old.copyWith(
        importance: importance, sessionsPerWeek: sessionsForImportance(importance));
  }

  @override
  Future<void> setSubjectPlan(int subjectId,
      {String? code, String? credits, int? year, int? term}) async {
    final i = _subjects.indexWhere((s) => s.id == subjectId);
    _subjects[i] = _subjects[i]
        .copyWith(code: code, credits: credits, planYear: year, planTerm: term);
  }

  @override
  Future<void> deleteSubject(int subjectId) async {
    final chapterIds = _chapters
        .where((c) => c.subjectId == subjectId)
        .map((c) => c.id)
        .toList();
    for (final id in chapterIds) {
      await deleteChapter(id);
    }
    _subjects.removeWhere((s) => s.id == subjectId);
  }

  @override
  Future<void> renameChapter(int chapterId, String name) async {
    final i = _chapters.indexWhere((c) => c.id == chapterId);
    final old = _chapters[i];
    _chapters[i] = old.copyWith(name: name);
  }

  @override
  Future<void> setChapterKind(int chapterId, ChapterKind kind) async {
    final i = _chapters.indexWhere((c) => c.id == chapterId);
    _chapters[i] = _chapters[i].copyWith(kind: kind);
  }

  @override
  Future<void> setSubjectColor(int subjectId, int colorIndex) async {
    final i = _subjects.indexWhere((s) => s.id == subjectId);
    _subjects[i] = _subjects[i].copyWith(colorIndex: colorIndex);
  }

  @override
  Future<void> setTutorMinutes(int subjectId, int minutes) async {
    final i = _subjects.indexWhere((s) => s.id == subjectId);
    _subjects[i] = _subjects[i].copyWith(tutorMinutes: minutes);
  }

  /// (occurrenceId, chapterId) ของทุกรอบติวที่บันทึก
  final List<(int, int?)> _tutorLog = [];

  @override
  Future<void> logTutor(int occurrenceId, int? chapterId, ChapterStatus status) async =>
      _tutorLog.add((occurrenceId, chapterId));

  @override
  Future<int> tutorCount(int chapterId) async =>
      {for (final l in _tutorLog) if (l.$2 == chapterId) l.$1}.length;

  @override
  Future<void> setChapterStatus(int chapterId, ChapterStatus status) async {
    final i = _chapters.indexWhere((c) => c.id == chapterId);
    _chapters[i] = _chapters[i].copyWith(status: status);
  }

  @override
  Future<void> renameSubtopic(int subtopicId, String name) async {
    _topics.firstWhere((t) => t.id == subtopicId).name = name;
  }

  @override
  Future<List<ChapterWithTopics>> chapters(int subjectId) async {
    final mine = _chapters.where((c) => c.subjectId == subjectId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return [
      for (final c in mine)
        ChapterWithTopics(
          c,
          (_topics.where((t) => t.chapterId == c.id).toList()
                ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder)))
              .map(_toSubtopic)
              .toList(),
        ),
    ];
  }

  @override
  Future<int> addChapter(int subjectId, String name) async =>
      _insertChapter(subjectId, name);

  @override
  Future<void> deleteChapter(int chapterId) async {
    final topicIds =
        _topics.where((t) => t.chapterId == chapterId).map((t) => t.id).toSet();
    _scores.removeWhere((s) => topicIds.contains(s.subtopicId));
    _topics.removeWhere((t) => t.chapterId == chapterId);
    _chapters.removeWhere((c) => c.id == chapterId);
  }

  @override
  Future<int> addSubtopic(int chapterId, String name) async =>
      _insertSubtopic(chapterId, name);

  @override
  Future<void> deleteSubtopic(int subtopicId) async {
    _scores.removeWhere((s) => s.subtopicId == subtopicId);
    _topics.removeWhere((t) => t.id == subtopicId);
  }

  @override
  Future<void> setExamFlag(int subtopicId, bool flag) async {
    _topics.firstWhere((t) => t.id == subtopicId).examFlag = flag;
  }

  final Map<String, String> _settings = {};

  @override
  Future<String?> getSetting(String key) async => _settings[key];

  @override
  Future<void> setSetting(String key, String value) async =>
      _settings[key] = value;

  @override
  Future<void> resetHistoryFrom(int subtopicId, DateTime from) async {
    _topics.firstWhere((t) => t.id == subtopicId).clearedAt = from;
  }

  @override
  Future<List<ScoreRecord>> scoreHistory(int subtopicId) async {
    final cleared = _topics.firstWhere((t) => t.id == subtopicId).clearedAt;
    final mine = _scores.where((s) => s.subtopicId == subtopicId).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    return [
      for (final s in mine)
        ScoreRecord(
          id: s.id,
          score: s.score,
          at: s.at,
          voided: cleared != null && s.at.isBefore(cleared),
        ),
    ];
  }

  @override
  Future<void> updateAssessment(int assessmentId, int score) async {
    _scores.firstWhere((s) => s.id == assessmentId).score = score;
  }

  @override
  Future<void> deleteAssessment(int assessmentId) async {
    _scores.removeWhere((s) => s.id == assessmentId);
  }

  @override
  Future<void> undoReset(int subtopicId) async {
    _topics.firstWhere((t) => t.id == subtopicId).clearedAt = null;
  }

  @override
  Future<GradingMode> gradingMode() async => _mode;

  @override
  Future<void> setGradingMode(GradingMode mode) async => _mode = mode;

  @override
  Future<void> addAssessment(int subtopicId, int score, {DateTime? at}) async {
    _scores.add(_ScoreRow(_nextId++, subtopicId, score, at ?? DateTime.now()));
  }
}

class _TopicRow {
  _TopicRow(this.id, this.chapterId, this.name, this.sortOrder);
  final int id;
  final int chapterId;
  String name;
  final int sortOrder;
  bool examFlag = false;
  DateTime? clearedAt;
}

class _ScoreRow {
  _ScoreRow(this.id, this.subtopicId, this.score, this.at);
  final int id;
  final int subtopicId;
  int score;
  final DateTime at;
}
