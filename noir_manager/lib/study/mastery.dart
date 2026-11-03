import '../data/study_models.dart';

/// ระดับความเข้าใจของหัวข้อย่อย (กฎ: ดี >80% · พอได้ 60–80% · ยังไม่ได้ <60%)
enum MasteryLevel { none, bad, warn, good }

MasteryLevel masteryOf(int? score) {
  if (score == null) return MasteryLevel.none;
  if (score > 80) return MasteryLevel.good;
  if (score >= 60) return MasteryLevel.warn;
  return MasteryLevel.bad;
}

/// โหมดการให้คะแนน (เหมือนหน้า BIOS: EZ = ง่าย, Advanced = ละเอียด)
enum GradingMode { ez, advanced }

/// ลำดับทวนก่อนสอบ เรียงจากเร่งสุดลงไป (หัวข้อที่ยังไม่เคยประเมิน ไม่นับ)
/// 1. คะแนนล่าสุด <60 (ต่ำสุดก่อน)
/// 2. ติดธง + ยังไม่ถึง "ดี" (60–80)
/// 3. [Advanced เท่านั้น] เคยต่ำกว่า 60 + ตอนนี้ยังไม่ถึง "ดี" (60–80) — ทวนจนได้ >80
List<Subtopic> reviewOrder(
  Iterable<Subtopic> topics, {
  GradingMode mode = GradingMode.ez,
}) {
  final weak = topics
      .where((t) => masteryOf(t.latestScore) == MasteryLevel.bad)
      .toList()
    ..sort((a, b) => a.latestScore!.compareTo(b.latestScore!));
  final flagged = topics
      .where((t) =>
          t.examFlag && masteryOf(t.latestScore) == MasteryLevel.warn)
      .toList()
    ..sort((a, b) => a.latestScore!.compareTo(b.latestScore!));
  final recovered = mode == GradingMode.advanced
      ? (topics
          .where((t) =>
              !t.examFlag && // ติดธงอยู่ในกลุ่ม 2 แล้ว ไม่ต้องซ้ำ
              t.everBelow60 &&
              masteryOf(t.latestScore) == MasteryLevel.warn)
          .toList()
        ..sort((a, b) => a.latestScore!.compareTo(b.latestScore!)))
      : <Subtopic>[];
  return [...weak, ...flagged, ...recovered];
}
