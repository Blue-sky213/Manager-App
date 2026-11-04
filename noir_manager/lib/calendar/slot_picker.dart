/// กล่องหาช่วงว่าง (ไทม์ไลน์ + ลิสต์แนะนำ) สำหรับ "งานครั้งเดียว" เช่น รอบติว
/// แถว = วันที่ (เช่น 7 วันข้างหน้า) · ใช้ free_slots.dart คำนวณ
library;

import 'package:flutter/material.dart';

import '../study/subject_colors.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';
import 'free_slots.dart';

/// ผลที่เลือก: วัน · นาทีเริ่ม · ความยาว
typedef PickedSlot = ({DateTime day, int start, int minutes});

/// ระบายสีงานในไทม์ไลน์ตามอะไร
enum SlotColorMode { subject, importance }

const double _rowH = 30;
const double _labelW = 96;

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
  Map<int, Color> subjectColors = const {},
  Map<int, String> subjectNames = const {},
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
      list.add(Busy(s, (e + pad).clamp(s, 24 * 60), x.title,
          subjectId: x.subjectId,
          importance: x.importance,
          tutor: x.kind == ActivityKind.tutor));
    }
    final lb = lifeBase[day.weekday - 1];
    var from = lb.wakeMinute;
    final to = lb.bedMinute < 12 * 60 ? 24 * 60 : lb.bedMinute;
    if (day == dayOnly(now)) {
      final nowMin = ((now.hour * 60 + now.minute + 14) ~/ 15) * 15;
      if (nowMin > from) from = nowMin;
    }
    busy[i] = list;
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
  var mode = SlotColorMode.subject;

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

      Color colorOf(Busy b) => switch (mode) {
            SlotColorMode.subject =>
              b.subjectId == null ? c.line2 : (subjectColors[b.subjectId] ?? c.line2),
            SlotColorMode.importance => importancePalette[b.importance] ?? c.line2,
          };

      // ลากเมาส์ค้าง (หรือนิ้ว) ได้ต่อเนื่อง: แปลงตำแหน่ง → (แถว, นาที) ปัดทีละ 5 นาที
      void dragTo(Offset local, double trackW) {
        final ppm = trackW / (axisTo - axisFrom);
        final i = (local.dy ~/ _rowH).clamp(0, days.length - 1);
        final at = axisFrom + ((local.dx - _labelW) / ppm).round();
        final s = (((at - len ~/ 2) / 5).round() * 5).clamp(axisFrom, axisTo - len);
        if (i != row || s != start) {
          setLocal(() {
            row = i;
            start = s;
          });
        }
      }

      Widget timeline() => LayoutBuilder(builder: (ctx, box) {
            final trackW = box.maxWidth - _labelW;
            final ppm = trackW / (axisTo - axisFrom);
            double x(int m) => _labelW + (m - axisFrom) * ppm;
            return MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanDown: (d) => dragTo(d.localPosition, trackW),
                onPanUpdate: (d) => dragTo(d.localPosition, trackW),
                child: SizedBox(
                  height: _rowH * days.length,
                  child: Stack(children: [
                    for (var i = 0; i < days.length; i++) ...[
                      Positioned(
                        left: 0,
                        top: i * _rowH,
                        width: _labelW,
                        height: _rowH,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(rowName(i),
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: i == row ? FontWeight.w600 : FontWeight.w400,
                                  color: i == row ? c.accent : c.muted)),
                        ),
                      ),
                      for (final g in gaps[i]!)
                        Positioned(
                          left: x(g.start),
                          width: (g.length * ppm - 2).clamp(0.0, double.infinity),
                          top: i * _rowH + 3,
                          height: _rowH - 6,
                          child: Container(
                            decoration: BoxDecoration(
                              color: g.length >= len ? c.greenBg : c.surface,
                              borderRadius: BorderRadius.circular(5),
                              border: Border.all(
                                  color: g.length >= len ? c.good.withValues(alpha: 0.5) : c.line),
                            ),
                          ),
                        ),
                      for (final b in busy[i]!)
                        Positioned(
                          left: x(b.start),
                          width: ((b.end - b.start) * ppm - 2).clamp(0.0, double.infinity),
                          top: i * _rowH + 3,
                          height: _rowH - 6,
                          // ชี้เมาส์ค้าง = เห็นชื่อเต็ม + เวลา (กล่องเล็กตัวหนังสือถูกตัด)
                          child: Tooltip(
                            message: '${b.title}\n${rangeText(b.start, b.end - b.start)}',
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              alignment: Alignment.centerLeft,
                              decoration: BoxDecoration(
                                color: b.tutor ? colorOf(b).withValues(alpha: 0.45) : colorOf(b),
                                borderRadius: BorderRadius.circular(5),
                                border: b.tutor ? Border.all(color: colorOf(b), width: 1.5) : null,
                              ),
                              child: Text(
                                b.title.replaceFirst('เรียน · ', '').replaceFirst('ติว · ', 'ติว '),
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: TextStyle(fontSize: 10, color: onColor(colorOf(b))),
                              ),
                            ),
                          ),
                        ),
                    ],
                    if (row != null)
                      Positioned(
                        left: x(start),
                        width: len * ppm,
                        top: row! * _rowH + 1,
                        height: _rowH - 2,
                        child: IgnorePointer(
                          child: Container(
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: hits.isEmpty ? c.accent : c.bad,
                              borderRadius: BorderRadius.circular(5),
                              boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
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
                ),
              ),
            );
          });

      // คำอธิบายสี มุมขวาบนของไทม์ไลน์
      Widget legend() {
        final entries = <(Color, String)>[];
        if (mode == SlotColorMode.subject) {
          final ids = {
            for (final l in busy.values)
              for (final b in l)
                if (b.subjectId != null) b.subjectId!,
          };
          for (final id in ids) {
            entries.add((subjectColors[id] ?? c.line2, subjectNames[id] ?? 'วิชา $id'));
          }
          entries.add((c.line2, 'งานอื่น'));
        } else {
          for (final i in [3, 2, 1]) {
            entries.add((importancePalette[i]!, importanceNames[i]!));
          }
        }
        Widget dot(Color color, String name, {Color? border}) => Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(3),
                    border: border == null ? null : Border.all(color: border),
                  ),
                ),
                const SizedBox(width: 5),
                Text(name, style: TextStyle(fontSize: 11, color: c.text)),
              ],
            );
        // แถวคำอธิบายสี วางเหนือไทม์ไลน์ (ไม่ลอยทับช่อง)
        return Wrap(
          spacing: 12,
          runSpacing: 4,
          children: [
            for (final (color, name) in entries) dot(color, name),
            dot(c.greenBg, 'ว่างพอ', border: c.good),
            dot(c.accent, 'ที่เลือก'),
          ],
        );
      }

      return AlertDialog(
        title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
        content: SizedBox(
          width: wide ? 960 : 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (note != null) Text(note, style: TextStyle(fontSize: 13, color: c.muted)),
                if (wide) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text('สีตาม', style: TextStyle(fontSize: 13, color: c.muted)),
                      SegmentedButton<SlotColorMode>(
                        style: const ButtonStyle(visualDensity: VisualDensity.compact),
                        segments: const [
                          ButtonSegment(value: SlotColorMode.subject, label: Text('วิชา')),
                          ButtonSegment(value: SlotColorMode.importance, label: Text('ความสำคัญ')),
                        ],
                        selected: {mode},
                        showSelectedIcon: false,
                        onSelectionChanged: (v) => setLocal(() => mode = v.first),
                      ),
                      Text('· ลากเมาส์ค้างเพื่อเลื่อน · ชี้ที่กล่องเพื่อดูชื่อเต็ม',
                          style: TextStyle(fontSize: 12, color: c.muted)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration:
                        BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        legend(),
                        const SizedBox(height: 8),
                        timeline(),
                      ],
                    ),
                  ),
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
                      label: const Text('−15 นาที'),
                      onPressed: () => setLocal(() => start = (start - 15).clamp(0, 24 * 60 - len))),
                  ActionChip(
                      label: const Text('+15 นาที'),
                      onPressed: () => setLocal(() => start = (start + 15).clamp(0, 24 * 60 - len))),
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
