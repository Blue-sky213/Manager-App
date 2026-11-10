/// มุมมองสัปดาห์ 3 แบบ (นัวร์เลือกได้ในหน้าปฏิทิน)
/// A = ตารางเวลา 7 คอลัมน์ · B = ลิสต์รายวัน · C = 7 คอลัมน์การ์ด
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import 'calendar_flows.dart';
import 'calendar_models.dart';
import 'calendar_ui.dart';

/// นาทีเริ่ม/จบของงานในวันนั้น (ข้ามเที่ยงคืน → ตัดที่ 24:00)
(int, int) _span(Occurrence o) {
  final s = minuteOf(o.startAt!);
  final mins = o.endAt!.difference(o.startAt!).inMinutes;
  return (s, (s + mins).clamp(s, 24 * 60));
}

/// ชั่วโมงรวมของงานล็อกเวลาที่ยังนับ (ไม่รวมยกเลิก/เลื่อน)
String _totalHours(List<Occurrence> items) {
  final mins = items
      .where((o) => o.timed && o.active)
      .fold<int>(0, (sum, o) => sum + o.endAt!.difference(o.startAt!).inMinutes);
  if (mins == 0) return 'ว่าง';
  return durationText(mins);
}

/// หัววัน 1 ช่อง (แตะ = เปิดดูแบบวัน)
class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday, required this.onTap});

  final DateTime day;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          children: [
            Text(thaiWeekdayShort[day.weekday - 1],
                style: TextStyle(fontSize: 12, color: isToday ? c.accent : c.muted)),
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isToday ? c.accent : null,
              ),
              child: Text('${day.day}',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isToday ? c.onAccent : c.text,
                  )),
            ),
          ],
        ),
      ),
    );
  }
}

/// ชิปงาน 1 อัน (ใช้ใน B และแถวงานลิสต์ของ A)
class _Chip extends StatelessWidget {
  const _Chip({required this.o, required this.category, required this.onTap, this.dense = false});

  final Occurrence o;
  final ActivityCategory? category;
  final VoidCallback onTap;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final (bg, fg) = occurrenceColors(c, o, category?.colorKey);
    final label = o.timed
        ? '${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)} · ${o.title}'
        : '○ ${o.title}';
    return OccurrenceMenuArea(o: o, child: Opacity(
      opacity: o.active ? 1 : 0.45,
      child: Material(
        color: o.timed ? bg : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onTap,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 8, vertical: dense ? 2 : 4),
            decoration: o.timed
                ? null
                : BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: c.line2),
                  ),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: dense ? 12 : 13,
                color: o.timed ? fg : c.muted,
                decoration: o.active ? null : TextDecoration.lineThrough,
              ),
            ),
          ),
        ),
      ),
    ));
  }
}

// ---------- A · ตารางเวลา 7 คอลัมน์ ----------

class WeekTimeline extends StatelessWidget {
  const WeekTimeline({
    super.key,
    required this.days,
    required this.byDay,
    required this.categories,
    required this.lifeBase,
    required this.today,
    required this.onTapOccurrence,
    required this.onTapDay,
  });

  final List<DateTime> days;
  final Map<DateTime, List<Occurrence>> byDay;
  final Map<int, ActivityCategory> categories;
  final List<LifeBaseDay> lifeBase;
  final DateTime today;
  final ValueChanged<Occurrence> onTapOccurrence;
  final ValueChanged<DateTime> onTapDay;

  static const double _hourPx = 26;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    // เริ่มที่ชั่วโมงตื่นเร็วสุด หรืองานแรกสุดของสัปดาห์ (ไม่เกิน 06:00)
    var fromHour = 6;
    for (final l in lifeBase) {
      if (l.wakeMinute ~/ 60 < fromHour) fromHour = l.wakeMinute ~/ 60;
    }
    for (final d in days) {
      for (final o in byDay[d] ?? const <Occurrence>[]) {
        if (o.timed && o.startAt!.hour < fromHour) fromHour = o.startAt!.hour;
      }
    }
    final hours = 24 - fromHour;
    final height = hours * _hourPx;
    final hasList = days.any((d) => (byDay[d] ?? const []).any((o) => !o.timed));
    final now = DateTime.now();

    Widget column(DateTime d) {
      final items = byDay[d] ?? const <Occurrence>[];
      final clashes = clashingIds(items);
      return SizedBox(
        height: height,
        child: Stack(
          children: [
            for (var h = 0; h < hours; h++)
              Positioned(
                top: h * _hourPx,
                left: 0,
                right: 0,
                child: Container(height: 1, color: c.line),
              ),
            for (final o in items.where((o) => o.timed))
              Builder(builder: (context) {
                final (s, e) = _span(o);
                final top = ((s - fromHour * 60) / 60 * _hourPx).clamp(0, height).toDouble();
                final h = ((e - s) / 60 * _hourPx).clamp(14, height - top).toDouble();
                final (bg, fg) = occurrenceColors(c, o, categories[o.categoryId]?.colorKey);
                return Positioned(
                  top: top,
                  height: h,
                  left: 2,
                  right: 2,
                  child: Opacity(
                    opacity: o.active ? 1 : 0.45,
                    child: Material(
                      // รอบติว = พื้นจาง + กรอบ (แยกจากคาบเรียน)
                      color: o.kind == ActivityKind.tutor ? bg.withValues(alpha: 0.35) : bg,
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                        side: clashes.contains(o.id)
                            ? BorderSide(color: c.bad, width: 2)
                            : (o.kind == ActivityKind.tutor
                                ? BorderSide(color: fg.withValues(alpha: 0.6), width: 1.5)
                                : BorderSide.none),
                      ),
                      child: OccurrenceMenuArea(o: o, child: InkWell(
                        onTap: () => onTapOccurrence(o),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          // Text เดียว: กล่องเตี้ยก็แค่ถูกตัด ไม่เกิด overflow error
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: o.title,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  decoration: o.active ? null : TextDecoration.lineThrough,
                                ),
                              ),
                              if (h >= 36)
                                TextSpan(
                                  text: '\n${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)}',
                                  style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8)),
                                ),
                            ]),
                            maxLines: h >= 36 ? 2 : 1,
                            overflow: TextOverflow.clip,
                            style: TextStyle(fontSize: 12, color: fg, height: 1.25),
                          ),
                        ),
                      )),
                    ),
                  ),
                );
              }),
            // เส้นแดง = ตอนนี้
            if (d == today && now.hour >= fromHour)
              Positioned(
                top: (now.hour * 60 + now.minute - fromHour * 60) / 60 * _hourPx,
                left: 0,
                right: 0,
                child: Container(height: 2, color: c.bad),
              ),
          ],
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                const SizedBox(width: 44),
                for (final d in days)
                  Expanded(
                    child: _DayHeader(day: d, isToday: d == today, onTap: () => onTapDay(d)),
                  ),
              ],
            ),
            if (hasList) ...[
              const SizedBox(height: 4),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 44,
                    child: Text('ลิสต์', style: TextStyle(fontSize: 11, color: c.muted)),
                  ),
                  for (final d in days)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (final o in (byDay[d] ?? const <Occurrence>[]).where((o) => !o.timed))
                              Padding(
                                padding: const EdgeInsets.only(bottom: 2),
                                child: _Chip(
                                  o: o,
                                  category: categories[o.categoryId],
                                  onTap: () => onTapOccurrence(o),
                                  dense: true,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 44,
                  height: height,
                  child: Stack(
                    children: [
                      for (var h = 0; h < hours; h += 2)
                        Positioned(
                          top: h * _hourPx - 7,
                          child: Text(fmtMinute((fromHour + h) * 60),
                              style: TextStyle(fontSize: 11, color: c.muted)),
                        ),
                    ],
                  ),
                ),
                for (final d in days) Expanded(child: column(d)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ---------- B · ลิสต์รายวัน ----------

class WeekList extends StatelessWidget {
  const WeekList({
    super.key,
    required this.days,
    required this.byDay,
    required this.categories,
    required this.today,
    required this.onTapOccurrence,
    required this.onTapDay,
  });

  final List<DateTime> days;
  final Map<DateTime, List<Occurrence>> byDay;
  final Map<int, ActivityCategory> categories;
  final DateTime today;
  final ValueChanged<Occurrence> onTapOccurrence;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Column(
      children: [
        for (final d in days)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Material(
              color: c.surface,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onTapDay(d),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: d == today ? c.accent : c.line),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 48,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(thaiWeekdayShort[d.weekday - 1],
                                style: TextStyle(
                                    fontSize: 12, color: d == today ? c.accent : c.muted)),
                            Text('${d.day}',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: (byDay[d] ?? const []).isEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text('—', style: TextStyle(color: c.muted)),
                              )
                            : Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final o in byDay[d]!)
                                    _Chip(
                                      o: o,
                                      category: categories[o.categoryId],
                                      onTap: () => onTapOccurrence(o),
                                    ),
                                ],
                              ),
                      ),
                      const SizedBox(width: 8),
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(_totalHours(byDay[d] ?? const []),
                            style: TextStyle(fontSize: 12, color: c.muted)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------- C · 7 คอลัมน์การ์ด ----------

class WeekCards extends StatelessWidget {
  const WeekCards({
    super.key,
    required this.days,
    required this.byDay,
    required this.categories,
    required this.today,
    required this.onTapOccurrence,
    required this.onTapDay,
  });

  final List<DateTime> days;
  final Map<DateTime, List<Occurrence>> byDay;
  final Map<int, ActivityCategory> categories;
  final DateTime today;
  final ValueChanged<Occurrence> onTapOccurrence;
  final ValueChanged<DateTime> onTapDay;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final d in days)
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.all(6),
              constraints: const BoxConstraints(minHeight: 280),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: d == today ? c.accent : c.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DayHeader(day: d, isToday: d == today, onTap: () => onTapDay(d)),
                  const SizedBox(height: 4),
                  for (final o in byDay[d] ?? const <Occurrence>[])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _Card(
                        o: o,
                        category: categories[o.categoryId],
                        onTap: () => onTapOccurrence(o),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// การ์ดงาน: ชื่อ แล้วเวลาเริ่ม │ เวลาจบ (แบบเดียวกับมุมมองรายวัน)
class _Card extends StatelessWidget {
  const _Card({required this.o, required this.category, required this.onTap});

  final Occurrence o;
  final ActivityCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (!o.timed) {
      return _Chip(o: o, category: category, onTap: onTap, dense: true);
    }
    final (bg, fg) = occurrenceColors(c, o, category?.colorKey);
    return OccurrenceMenuArea(o: o, child: Opacity(
      opacity: o.active ? 1 : 0.45,
      child: Material(
        color: bg,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(o.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: fg,
                      decoration: o.active ? null : TextDecoration.lineThrough,
                    )),
                Text(fmtTime(o.startAt!), style: TextStyle(fontSize: 12, color: fg)),
                Container(
                  width: 2,
                  height: 12,
                  margin: const EdgeInsets.only(left: 14, top: 2, bottom: 2),
                  color: fg.withValues(alpha: 0.5),
                ),
                Text(fmtTime(o.endAt!), style: TextStyle(fontSize: 12, color: fg)),
              ],
            ),
          ),
        ),
      ),
    ));
  }
}
