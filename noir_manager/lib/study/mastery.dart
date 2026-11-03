import '../data/study_models.dart';

/// ระดับความเข้าใจของหัวข้อย่อย (กฎ: ดี >80% · พอได้ 60–80% · ยังไม่ได้ <60%)
enum MasteryLevel { none, bad, warn, good }

MasteryLevel masteryOf(int? score) {
  if (score == null) return MasteryLevel.none;
  if (score > 80) return MasteryLevel.good;
  if (score >= 60) return MasteryLevel.warn;
  return MasteryLevel.bad;
}

/// ลำดับทวนก่อนสอบ: คะแนนต่ำ (<60) ก่อน เรียงจากน้อยไปมาก
/// → ตามด้วยหัวข้อที่ติดธงแต่ยังไม่ถึง "ดี" → หัวข้อที่ยังไม่เคยประเมิน ไม่นับ
List<Subtopic> reviewOrder(Iterable<Subtopic> topics) {
  final weak = topics
      .where((t) => masteryOf(t.latestScore) == MasteryLevel.bad)
      .toList()
    ..sort((a, b) => a.latestScore!.compareTo(b.latestScore!));
  final flagged = topics
      .where((t) =>
          t.examFlag && masteryOf(t.latestScore) == MasteryLevel.warn)
      .toList()
    ..sort((a, b) => a.latestScore!.compareTo(b.latestScore!));
  return [...weak, ...flagged];
}
