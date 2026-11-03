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

/// คะแนนที่โชว์ (และใช้ตัดสินสี)
/// EZ = คะแนนล่าสุด · Advanced = ค่าเฉลี่ยทุกรอบ
int? shownScore(Subtopic t, GradingMode mode) =>
    mode == GradingMode.ez ? t.latestScore : t.averageScore;

/// ป้าย "เช็กซ้ำ"
/// EZ = เคยต่ำกว่า 60 · Advanced = เคยต่ำกว่า 60 และยังไม่ "ผ่านจริง"
/// (ผ่านจริง = เขียว 2 รอบติด + ค่าเฉลี่ยเป็นเขียว)
bool showRecheck(Subtopic t, GradingMode mode) {
  if (!t.everBelow60) return false;
  if (mode == GradingMode.ez) return true;
  final passed =
      t.greenTwice && masteryOf(t.averageScore) == MasteryLevel.good;
  return !passed;
}

/// [Advanced] ต้องถามผู้ใช้ไหม: เคยตก → เขียว 2 รอบติดแล้ว แต่ค่าเฉลี่ยยังไม่ถึงเขียว
bool needsGreenDecision(Subtopic t) =>
    t.everBelow60 &&
    t.greenTwice &&
    masteryOf(t.averageScore) != MasteryLevel.good;

/// ลำดับทวนก่อนสอบ เรียงจากเร่งสุดลงไป (หัวข้อที่ยังไม่เคยประเมิน ไม่นับ)
/// 1. คะแนน (ตามโหมด) <60 — ต่ำสุดก่อน
/// 2. ติดธง + ยังไม่ถึง "ดี"
/// 3. [Advanced เท่านั้น] มีป้ายเช็กซ้ำ (เคยตก และยังไม่ผ่านจริง) แม้ตอนนี้จะเขียวแล้ว 1 รอบ
List<Subtopic> reviewOrder(
  Iterable<Subtopic> topics, {
  GradingMode mode = GradingMode.ez,
}) {
  int score(Subtopic t) => shownScore(t, mode)!;
  MasteryLevel level(Subtopic t) => masteryOf(shownScore(t, mode));
  void byScore(List<Subtopic> list) =>
      list.sort((a, b) => score(a).compareTo(score(b)));

  final scored = topics.where((t) => shownScore(t, mode) != null).toList();

  final weak = scored.where((t) => level(t) == MasteryLevel.bad).toList();
  byScore(weak);

  final flagged = scored
      .where((t) => t.examFlag && level(t) == MasteryLevel.warn)
      .toList();
  byScore(flagged);

  final recheck = mode == GradingMode.advanced
      ? scored
          .where((t) =>
              !weak.contains(t) && !flagged.contains(t) && showRecheck(t, mode))
          .toList()
      : <Subtopic>[];
  byScore(recheck);

  return [...weak, ...flagged, ...recheck];
}
