/// กล่องหาช่วงว่าง (ไทม์ไลน์ + ลิสต์แนะนำ) สำหรับ "งานครั้งเดียว" เช่น รอบติว
/// แถว = วันที่ (เช่น 7 วันข้างหน้า) · ใช้ free_slots.dart คำนวณ
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';
import 'free_slots.dart';

/// ผลที่เลือก: วัน · นาทีเริ่ม · ความยาว
typedef PickedSlot = ({DateTime day, int start, int minutes});

Future<PickedSlot?> pickFreeSlot(
  BuildContext context,
  CalendarRepository repo, {
  required String title,
  required int minutes,
  required List<DateTime> days,
  int preferStart = 18 * 60,
  int bufferAfter = 10,
  Set<DateTime> avoidDays = const {},
  String? note,
}) async {
  final lifeBase = await repo.lifeBase();
  final now = DateTime.now();
  final busy = <int, List<Busy>>{};
  final gaps = <int, List<Gap>>{};
  for (var i = 0; i < days.length; i++) {
    final day = dayOnly(days[i]);
    final list = <Busy>[];
    for (final x in await repo.occurrencesOn(day)) {
      if (!x.timed || !x.active) continue;
      final s = minuteOf(x.startAt!);
      final e = (s + x.endAt!.difference(x.startAt!).inMinutes).clamp(s, 24 * 60);
      // รอบติวมีพักเงียบหลังจบ → กันเวลาต่อท้ายงานติวไว้ด้วย
      final pad = x.kind == ActivityKind.tutor ? bufferAfter : 0;
      list.add(Busy(s, (e + pad).clamp(s, 24 * 60), x.title));
    }
    final lb = lifeBase[day.weekday - 1];
    var from = lb.wakeMinute;
    final to = lb.bedMinute < 12 * 60 ? 24 * 60 : lb.bedMinute;
    if (day == dayOnly(now)) {
      final nowMin = ((now.hour * 60 + now.minute + 14) ~/ 15) * 15;
      if (nowMin > from) from = nowMin;
    }
    busy[i] = list;
    // ต้องมีที่ให้ทั้งรอบติว + พักเงียบ
    gaps[i] = from < to ? freeGaps(list, from, to) : const [];
  }
  if (!context.mounted) return null;

  final axisFrom = (lifeBase.map((l) => l.wakeMinute).reduce((a, b) => a < b ? a : b) ~/ 60) * 60;
  const axisTo = 24 * 60;
  String rowName(int i) => thaiShortDate(days[i]);

  var len = minutes;
  int? row;
  var start = preferStart;
  var initialized = false;

  return showDialog<PickedSlot>(
    context: context,
    builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      final wide = MediaQuery.sizeOf(ctx).width >= 720;
      // วันที่มีคาบเรียนวิชานี้อยู่แล้ว → เลื่อนลงท้ายรายการ (เว้นระยะให้สมองได้พัก)
      final raw = suggestSlots(gaps, len + bufferAfter, preferStart, limit: 12);
      final suggestions = [
        ...raw.where((s) => !avoidDays.contains(dayOnly(days[s.row]))),
        ...raw.where((s) => avoidDays.contains(dayOnly(days[s.row]))),
      ].take(6).toList();
      // เปิดกล่องครั้งแรก: เลือกช่องแนะนำอันแรกไว้ให้เลย
      if (!initialized) {
        initialized = true;
        if (suggestions.isNotEmpty) {
          row = suggestions.first.row;
          start = suggestions.first.start;
        }
      }
      final hits = row == null ? const <Busy>[] : clashesAt(busy[row]!, start, len);

      Widget timelineRow(int i) => Row(children: [
            SizedBox(
              width: 96,
              child: Text(rowName(i),
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == row ? FontWeight.w600 : FontWeight.w400,
                      color: i == row ? c.accent : c.muted)),
            ),
            Expanded(
              child: LayoutBuilder(builder: (ctx, box) {
                final ppm = box.maxWidth / (axisTo - axisFrom);
                double x(int m) => (m - axisFrom) * ppm;
                return SizedBox(
                  height: 30,
                  child: Stack(children: [
                    for (final g in gaps[i]!)
                      Positioned(
                        left: x(g.start),
                        width: (g.length * ppm - 2).clamp(0.0, double.infinity),
                        top: 3,
                        bottom: 3,
                        child: GestureDetector(
                          onTapDown: g.length < len
                              ? null
                              : (t) {
                                  final at = g.start + (t.localPosition.dx / ppm).round();
                                  final s = (((at - len ~/ 2) ~/ 15) * 15).clamp(g.start, g.end - len);
                                  setLocal(() {
                                    row = i;
                                    start = s;
                                  });
                                },
                          child: Container(
                            decoration: BoxDecoration(
                              color: g.length >= len ? c.greenBg : c.surface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: g.length >= len ? c.good.withValues(alpha: 0.5) : c.line),
                            ),
                          ),
                        ),
                      ),
                    for (final b in busy[i]!)
                      Positioned(
                        left: x(b.start),
                        width: ((b.end - b.start) * ppm - 2).clamp(0.0, double.infinity),
                        top: 3,
                        bottom: 3,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.centerLeft,
                          decoration: BoxDecoration(
                              color: c.line2, borderRadius: BorderRadius.circular(5)),
                          child: Text(b.title.replaceFirst('เรียน · ', ''),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(fontSize: 10, color: c.muted)),
                        ),
                      ),
                    if (i == row)
                      Positioned(
                        left: x(start),
                        width: len * ppm,
                        top: 1,
                        bottom: 1,
                        child: IgnorePointer(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hits.isEmpty ? c.accent : c.bad,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(rangeText(start, len),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w600, color: c.onAccent)),
                          ),
                        ),
                      ),
                  ]),
                );
              }),
            ),
          ]);

      return AlertDialog(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: wide ? 900 : 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (note != null) Text(note, style: TextStyle(fontSize: 13, color: c.muted)),
                if (wide) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration:
                        BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
                    child: Column(children: [for (var i = 0; i < days.length; i++) timelineRow(i)]),
                  ),
                  const SizedBox(height: 4),
                  Text('🟩 ว่างพอ (แตะเพื่อวาง) · ⬛ มีงานแล้ว · เผื่อพักเงียบ $bufferAfter นาทีหลังติว',
                      style: TextStyle(fontSize: 12, color: c.muted)),
                ],
                const SizedBox(height: 12),
                Text('ช่วงว่างแนะนำ', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 6),
                if (suggestions.isEmpty)
                  Text('ไม่มีช่วงว่างพอใน ${days.length} วันนี้ ลองลดเวลาติว',
                      style: TextStyle(color: c.bad)),
                for (final sg in suggestions)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Material(
                      color: sg.row == row && sg.start == start ? c.navBg : c.surface,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => setLocal(() {
                          row = sg.row;
                          start = sg.start;
                        }),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          child: Row(children: [
                            SizedBox(
                                width: 120,
                                child: Text(rowName(sg.row),
                                    style: const TextStyle(fontWeight: FontWeight.w600))),
                            Expanded(
                              child: Text.rich(TextSpan(children: [
                                TextSpan(
                                    text: rangeText(sg.start, len),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                TextSpan(
                                  text: ' · ว่าง ${fmtMinute(sg.gap.start)}–${fmtMinute(sg.gap.end)}'
                                      '${avoidDays.contains(dayOnly(days[sg.row])) ? ' · วันเดียวกับคาบเรียน' : ''}',
                                  style: TextStyle(fontSize: 12, color: c.muted),
                                ),
                              ])),
                            ),
                            if (sg == suggestions.first)
                              Text('แนะนำ', style: TextStyle(fontSize: 12, color: c.good)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final m in const [30, 60, 90, 120])
                    ChoiceChip(
                      label: Text(durationText(m)),
                      selected: len == m,
                      onSelected: (_) => setLocal(() => len = m),
                    ),
                  ActionChip(
                      label: const Text('−30 นาที'),
                      onPressed: () => setLocal(() => start = (start - 30).clamp(0, 24 * 60 - len))),
                  ActionChip(
                      label: const Text('+30 นาที'),
                      onPressed: () => setLocal(() => start = (start + 30).clamp(0, 24 * 60 - len))),
                ]),
                const SizedBox(height: 8),
                if (row != null)
                  Text(
                    hits.isEmpty
                        ? '${rowName(row!)} ${rangeText(start, len)} · ไม่ชนกับงานไหน'
                        : '⚠ ${rowName(row!)} ${rangeText(start, len)} ชนกับ ${hits.map((b) => b.title).join(', ')}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: hits.isEmpty ? c.good : c.bad),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: row == null
                ? null
                : () => Navigator.pop(ctx, (day: dayOnly(days[row!]), start: start, minutes: len)),
            child: Text(row == null ? 'เลือกช่วงเวลา' : 'จอง ${rowName(row!)} ${rangeText(start, len)}'),
          ),
        ],
      );
    }),
  );
}
