/// มุมมอง "เดือน" แบบสมุด: ปฏิทินกระดาษ แปะสติกเกอร์ชัด ๆ · แตะวัน = เลือกวัน (รายการงานอยู่ใต้ตาราง)
/// เดือนที่ผ่านมา = ดูสติกเกอร์ + วันที่ทำครบ · เดือนหน้า = ดูแผน สอบ ส่งงาน ติว
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'achievements.dart';
import 'calendar_models.dart';
import 'calendar_ui.dart';
import 'sticker_ui.dart' show StickerGlyph;
import 'stickers.dart' show Sticker;

/// สรุปของ 1 วันในสมุด
class NotebookDay {
  const NotebookDay(
      {this.classes = 0, this.tutors = 0, this.exams = 0, this.homework = 0, this.others = 0, this.complete = false});
  final int classes;

  /// งานทั่วไป (ไม่ใช่คาบ / ติว / สอบ / ส่งงาน) เช่น ทำงาน · สตรีม
  final int others;
  final int tutors;
  final int exams;
  final int homework;
  final bool complete;

  factory NotebookDay.of(List<Occurrence> items, {required bool pastOrToday}) {
    var cl = 0, tu = 0, ex = 0, hw = 0, ot = 0;
    for (final o in items) {
      if (!o.active) continue;
      switch (markOf(o)) {
        case DayMark.exam:
          ex++;
        case DayMark.homework:
          hw++;
        case null:
          if (o.kind == ActivityKind.classSession) {
            cl++;
          } else if (o.kind == ActivityKind.tutor) {
            tu++;
          } else {
            ot++;
          }
      }
    }
    return NotebookDay(
        classes: cl, tutors: tu, exams: ex, homework: hw, others: ot, complete: pastOrToday && dayComplete(items));
  }
}

/// เลขสัปดาห์ ISO 8601 (สัปดาห์เริ่มจันทร์ · สัปดาห์ที่ 1 มีวันพฤหัสแรกของปี)
int isoWeek(DateTime d) {
  final day = DateTime.utc(d.year, d.month, d.day);
  final thursday = day.add(Duration(days: 4 - day.weekday));
  final jan1 = DateTime.utc(thursday.year, 1, 1);
  return thursday.difference(jan1).inDays ~/ 7 + 1;
}

const _weekdayLong = ['จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์'];

class NotebookMonth extends StatelessWidget {
  const NotebookMonth({
    super.key,
    required this.month,
    required this.days,
    required this.byDay,
    required this.stickers,
    required this.holidays,
    required this.onTapDay,
    this.onOpenDay,
    this.onOpenWeek,
    this.selected,
  });

  /// ดับเบิลคลิกวัน = เปิดมุมมองวัน
  final ValueChanged<DateTime>? onOpenDay;

  /// คลิกช่องสัปดาห์ (W46) ทางซ้าย = เปิดมุมมองสัปดาห์นั้น (ส่งวันจันทร์)
  final ValueChanged<DateTime>? onOpenWeek;

  /// วันที่เลือกอยู่ (กรอบสีเน้น)
  final DateTime? selected;
  final DateTime month;
  final List<DateTime> days; // 42 วันของตาราง (เริ่มจันทร์)
  final Map<DateTime, List<Occurrence>> byDay;
  final Map<DateTime, List<Sticker>> stickers;
  final Map<String, String> holidays;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final today = dayOnly(DateTime.now());
    final info = {
      for (final d in days) d: NotebookDay.of(byDay[d] ?? const [], pastOrToday: !d.isAfter(today)),
    };
    final inMonth = days.where((d) => d.month == month.month);
    int sum(int Function(NotebookDay) f) => inMonth.fold(0, (s, d) => s + f(info[d]!));
    final holidayCount = inMonth.where((d) => holidays[dayKey(d)] != null).length;
    final paper = Color.alphaBlend(c.surface.withValues(alpha: 0.6), c.bg);

    return LayoutBuilder(builder: (context, box) {
      final cellH = (box.maxWidth / 7 * 1.05).clamp(54.0, 120.0);
      final big = cellH * 0.48;
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // คำอธิบาย: ใช้สัญลักษณ์เดียวกับในช่องวันจริง
        Wrap(spacing: 14, runSpacing: 6, children: [
          _key(c, '⭐', 'ส่งงาน'),
          _key(c, '📝', 'สอบ'),
          _key(c, '🎓', 'คาบเรียน (ตัวเลข = กี่คาบ)'),
          _key(c, '✎', 'ติว (กี่รอบ)'),
          _key(c, '💼', 'งานอื่น (กี่งาน)'),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(border: Border.all(color: c.good, width: 2), borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 4),
            Text('ทำครบทั้งวัน', style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        ]),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.fromLTRB(8, 18, 8, 8),
          decoration: BoxDecoration(color: paper, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Stack(clipBehavior: Clip.none, children: [
            Column(children: [
              Row(children: [
                if (onOpenWeek != null) SizedBox(width: _weekColW, child: Center(child: Text(box.maxWidth < 520 ? 'ส.' : 'สัปดาห์', style: TextStyle(fontSize: 11, color: c.muted)))),
                // ชื่อวันเต็ม (จอแคบ = ย่อ) · เสาร์–อาทิตย์สีส้ม
                for (final (i, w) in (box.maxWidth < 520 ? thaiWeekdayShort : _weekdayLong).indexed)
                  Expanded(
                    child: Center(
                      child: Text(w, style: TextStyle(fontSize: 12, color: i >= 5 ? c.warn : c.muted)),
                    ),
                  ),
              ]),
              const SizedBox(height: 4),
              for (var r = 0; r < days.length ~/ 7; r++)
                Row(children: [
                  if (onOpenWeek != null) _weekCell(context, days[r * 7], cellH),
                  for (final d in days.sublist(r * 7, r * 7 + 7))
                    Expanded(child: _cell(context, d, info[d]!, cellH, big, today)),
                ]),
            ]),
            // เทปชื่อเดือน (เหมือนแปะบนสมุด)
            Positioned(
              top: -32,
              left: 0,
              right: 0,
              child: Center(
                child: Transform.rotate(
                  angle: -0.03,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 5),
                    color: c.good.withValues(alpha: 0.35),
                    child: Text(thaiMonthsLong[month.month - 1],
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  ),
                ),
              ),
            ),
          ]),
        ),
        const SizedBox(height: 12),
        // สรุปเดือน: ป้ายละเรื่อง ไม่รวมเป็นประโยคเดียว
        Text('ในเดือนนี้', style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 6),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _stat(c, '📝', 'สอบ', sum((i) => i.exams)),
          _stat(c, '⭐', 'ส่งงาน', sum((i) => i.homework)),
          _stat(c, '🎓', 'คาบเรียน', sum((i) => i.classes)),
          _stat(c, '✎', 'ติว', sum((i) => i.tutors)),
          _stat(c, '✓', 'วันที่ทำครบ', inMonth.where((d) => info[d]!.complete).length),
          if (holidayCount > 0) _stat(c, '🏖', 'วันหยุด', holidayCount),
        ]),
        const SizedBox(height: 6),
        Text(
            onOpenDay == null
                ? 'แตะวัน = ดูงานของวันนั้นด้านล่าง · เพิ่ม / กรอกผล / แก้ไข ได้ตามปกติ'
                : 'แตะวัน = ดูงานของวันนั้น · ดับเบิลคลิก = เปิดมุมมองวัน · แตะ W = เปิดสัปดาห์นั้น',
            style: TextStyle(fontSize: 12, color: c.muted)),
      ]);
    });
  }

  static const _weekColW = 44.0;

  /// ช่อง W (เลขสัปดาห์แบบ ISO) ทางซ้ายของแต่ละแถว · สัปดาห์ที่มีวันที่เลือก = สีเน้น
  Widget _weekCell(BuildContext context, DateTime monday, double h) {
    final c = context.noir;
    final current = selected != null && !selected!.isBefore(monday) && selected!.isBefore(monday.add(const Duration(days: 7)));
    return SizedBox(
      width: _weekColW,
      height: h + 2,
      child: Padding(
        padding: const EdgeInsets.all(1),
        child: Material(
          color: current ? c.accent : c.surface2,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            key: ValueKey('nb-week-${monday.month}-${monday.day}'),
            borderRadius: BorderRadius.circular(6),
            onTap: () => onOpenWeek!(monday),
            child: Center(
              child: Text('W${isoWeek(monday)}',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: current ? c.onAccent : c.accent)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _key(NoirColors c, String mark, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
        Text(mark, style: const TextStyle(fontSize: 13)),
        const SizedBox(width: 4),
        Text(text, style: TextStyle(fontSize: 12, color: c.muted)),
      ]);

  Widget _stat(NoirColors c, String mark, String label, int n) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
        child: Text('$mark $label $n', style: TextStyle(fontSize: 13, color: c.text)),
      );

  Widget _cell(BuildContext context, DateTime d, NotebookDay i, double h, double big, DateTime today) {
    final c = context.noir;
    final out = d.month != month.month;
    final st = stickers[d] ?? const <Sticker>[];
    final holiday = holidays[dayKey(d)];
    final marks = '${'⭐' * math.min(i.homework, 2)}${'📝' * math.min(i.exams, 2)}';
    final counts = [
      if (i.classes > 0) '🎓${i.classes}',
      if (i.tutors > 0) '✎${i.tutors}',
      if (i.others > 0) '💼${i.others}',
    ].join(' ');
    return InkWell(
      key: ValueKey('nb-${d.month}-${d.day}'),
      onTap: () => onTapDay(d),
      onDoubleTap: onOpenDay == null ? null : () => onOpenDay!(d),
      child: Container(
        height: h,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: d == today ? c.accent.withValues(alpha: 0.08) : null,
          border: d == selected
              ? Border.all(color: c.accent, width: 2.5)
              : i.complete
                  ? Border.all(color: c.good, width: 2)
                  : Border.all(color: c.line.withValues(alpha: 0.6)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Opacity(
          opacity: out ? 0.35 : 1,
          child: Stack(children: [
            Positioned(
              left: 4,
              top: 2,
              child: Text('${d.day}',
                  style: TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600, color: d == today ? c.accent : c.text)),
            ),
            if (marks.isNotEmpty) Positioned(right: 3, top: 2, child: Text(marks, style: const TextStyle(fontSize: 10))),
            // สติกเกอร์ชิ้นแรกใหญ่กลางช่อง เอียงนิดหน่อยเหมือนแปะจริง · ชิ้นที่ 2 เล็กมุมขวาล่าง
            if (st.isNotEmpty)
              Center(
                child: Transform.rotate(
                  angle: ((d.day * 37) % 14 - 7) * math.pi / 180,
                  child: StickerGlyph(st.first, size: big),
                ),
              ),
            if (st.length > 1) Positioned(right: 2, bottom: 2, child: StickerGlyph(st[1], size: big * 0.42)),
            if (holiday != null && st.isEmpty)
              Positioned(left: 4, top: 18, right: 2, child: Text('หยุด', style: TextStyle(fontSize: 10, color: c.warn))),
            if (counts.isNotEmpty && st.length < 2)
              Positioned(left: 4, bottom: 2, child: Text(counts, style: TextStyle(fontSize: 10, color: c.muted))),
          ]),
        ),
      ),
    );
  }
}

/// แตะวันในสมุด → สรุปวันนั้น (ดูอย่างเดียว)
Future<void> showNotebookDay(BuildContext context, DateTime day, List<Occurrence> items, List<Sticker> stickers) {
  final c = context.noir;
  final (done, total) = dayProgress(items);
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: ListView(shrinkWrap: true, children: [
        Row(children: [
          Expanded(
            child: Text(thaiShortDate(day), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
          ),
          for (final s in stickers) Padding(padding: const EdgeInsets.only(left: 4), child: StickerGlyph(s, size: 30)),
        ]),
        Text(total == 0 ? 'ไม่มีงาน' : 'ทำแล้ว $done / $total', style: TextStyle(color: c.muted)),
        const SizedBox(height: 8),
        for (final o in items.where((o) => o.status != OccurrenceStatus.moved))
          ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Icon(
              switch (o.status) {
                OccurrenceStatus.done => Icons.check_circle,
                OccurrenceStatus.cancelled => Icons.block,
                _ => o.kind == ActivityKind.tutor ? Icons.edit_outlined : Icons.circle_outlined,
              },
              color: o.status == OccurrenceStatus.done ? c.good : c.muted,
            ),
            title: Text(markedTitle(o)),
            subtitle: o.timed ? Text('${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)}') : null,
          ),
      ]),
    ),
  );
}
