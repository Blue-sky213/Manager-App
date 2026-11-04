/// หาช่วงว่างที่ไม่ชน (ใช้ในกล่อง "ย้ายวัน/เวลา")
/// ทุกค่าเป็น "นาทีนับจากเที่ยงคืน" (0–1440)
library;

/// ช่วงเวลาที่มีงานแล้ว
class Busy {
  const Busy(this.start, this.end, this.title);
  final int start;
  final int end;
  final String title;
}

/// ช่วงว่าง 1 ช่วงในวันนั้น
class Gap {
  const Gap(this.start, this.end);
  final int start;
  final int end;
  int get length => end - start;
}

/// ช่วงว่างระหว่าง [from]–[to] หลังตัดงานที่มีอยู่ออก
List<Gap> freeGaps(List<Busy> busy, int from, int to) {
  final sorted = [...busy]..sort((a, b) => a.start.compareTo(b.start));
  final gaps = <Gap>[];
  var cursor = from;
  for (final b in sorted) {
    if (b.end <= cursor) continue;
    if (b.start >= to) break;
    if (b.start > cursor) gaps.add(Gap(cursor, b.start));
    if (b.end > cursor) cursor = b.end;
  }
  if (cursor < to) gaps.add(Gap(cursor, to));
  return gaps;
}

/// ช่วง [start, start+duration] ชนกับงานไหนบ้าง
List<Busy> clashesAt(List<Busy> busy, int start, int duration) => [
      for (final b in busy)
        if (start < b.end && b.start < start + duration) b,
    ];

/// ข้อเสนอ 1 ช่อง: แถวที่ [row] (วันในสัปดาห์ 1–7 หรือ index ของวัน) เริ่ม [start]
class SlotSuggestion {
  const SlotSuggestion(this.row, this.start, this.gap);
  final int row;
  final int start;
  final Gap gap;
}

/// เสนอช่องที่ใส่ได้ เรียงจาก "ใกล้เวลาเดิมที่สุด" (เวลาเดิมเป๊ะมาก่อน)
/// [gapsByRow] = ช่วงว่างของแต่ละแถว · ช่องที่สั้นกว่า [duration] ไม่นับ
List<SlotSuggestion> suggestSlots(
  Map<int, List<Gap>> gapsByRow,
  int duration,
  int originalStart, {
  int? originalRow,
  int limit = 6,
}) {
  final out = <(int, SlotSuggestion)>[];
  for (final e in gapsByRow.entries) {
    for (final g in e.value) {
      if (g.length < duration) continue;
      // วางให้ใกล้เวลาเดิมที่สุดภายในช่องนี้ ปัดเป็น 15 นาที
      var s = originalStart.clamp(g.start, g.end - duration);
      s = ((s + 14) ~/ 15) * 15;
      if (s + duration > g.end) s = g.end - duration;
      final sameRow = e.key == originalRow ? 0 : 1;
      out.add(((s - originalStart).abs() * 2 + sameRow, SlotSuggestion(e.key, s, g)));
    }
  }
  out.sort((a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.row.compareTo(b.$2.row));
  return [for (final x in out.take(limit)) x.$2];
}
