import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import 'calendar_flows.dart';
import 'calendar_models.dart';
import 'calendar_ui.dart';
import 'class_stats.dart';

/// ตารางของ 1 วัน: ตื่นนอน → งานล็อกเวลา (เรียงตามเวลา) → นอน · แล้วตามด้วยงานแบบลิสต์
class DayAgenda extends StatelessWidget {
  const DayAgenda({
    super.key,
    required this.items,
    required this.categories,
    required this.onTap,
    this.lifeBase,
  });

  final List<Occurrence> items;
  final Map<int, ActivityCategory> categories;
  final ValueChanged<Occurrence> onTap;

  /// เวลาตื่น/นอนของวันนี้ (null = ไม่แสดง)
  final LifeBaseDay? lifeBase;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final timed = items.where((o) => o.timed).toList();
    final clashes = clashingIds(items);
    final list = items.where((o) => !o.timed).toList();

    // รวมงานล็อกเวลา + ตื่น/นอน แล้วเรียงตามนาที
    final rows = <(int, Widget)>[
      if (lifeBase != null)
        (lifeBase!.wakeMinute, _MarkerRow(minute: lifeBase!.wakeMinute, text: 'ตื่นนอน')),
      for (final o in timed)
        (
          minuteOf(o.startAt!),
          _OccurrenceRow(
            o: o,
            category: categories[o.categoryId],
            clash: clashes.contains(o.id),
            onTap: () => onTap(o),
          ),
        ),
      if (lifeBase != null)
        (
          // นอนหลังเที่ยงคืน (เช่น 00:30) ให้อยู่ท้ายสุด
          lifeBase!.bedMinute < 12 * 60 ? lifeBase!.bedMinute + 24 * 60 : lifeBase!.bedMinute,
          _MarkerRow(minute: lifeBase!.bedMinute, text: 'นอน'),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                for (final r in rows) r.$2,
                if (timed.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text('ยังไม่มีงานล็อกเวลาในวันนี้',
                        style: TextStyle(color: c.muted)),
                  ),
              ],
            ),
          ),
        ),
        if (list.isNotEmpty) ...[
          const SizedBox(height: 12),
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: Text('งานแบบลิสต์ (ไม่ล็อกเวลา)',
                      style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                ),
                for (final o in list)
                  _ListRow(o: o, category: categories[o.categoryId], onTap: () => onTap(o)),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

/// ตื่นนอน / นอน (แถวสีเทา กดไม่ได้)
class _MarkerRow extends StatelessWidget {
  const _MarkerRow({required this.minute, required this.text});

  final int minute;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(fmtMinute(minute), style: TextStyle(color: c.muted, fontSize: 14)),
          ),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: c.line2),
              ),
              child: Text(text, style: TextStyle(color: c.muted)),
            ),
          ),
        ],
      ),
    );
  }
}

/// ข้อความสถานะใต้ชื่องาน
String? _statusText(Occurrence o) => switch (o.status) {
      OccurrenceStatus.planned => null,
      OccurrenceStatus.done => o.actualEnd == null
          ? 'ทำแล้ว'
          : 'เลิกจริง ${fmtTime(o.actualEnd!)} (${diffText(o.endDiffMinutes!)})',
      OccurrenceStatus.cancelled => 'ยกเลิก: ${o.reason ?? ''}',
      OccurrenceStatus.moved => 'เลื่อนไปวันอื่นแล้ว',
      OccurrenceStatus.inbox => 'อยู่ใน Updates',
      OccurrenceStatus.shifted => 'เลื่อนไปรอบถัดไป${o.reason == null ? '' : ' · ${o.reason}'}',
    };

IconData? _statusIcon(OccurrenceStatus s) => switch (s) {
      OccurrenceStatus.planned => null,
      OccurrenceStatus.done => Icons.check_circle,
      OccurrenceStatus.cancelled => Icons.block,
      OccurrenceStatus.moved => Icons.redo,
      OccurrenceStatus.inbox => Icons.inbox,
      OccurrenceStatus.shifted => Icons.fast_forward,
    };

/// งานล็อกเวลา 1 ครั้ง
class _OccurrenceRow extends StatelessWidget {
  const _OccurrenceRow({
    required this.o,
    required this.category,
    required this.onTap,
    this.clash = false,
  });

  /// เวลาทับกับงานอื่นในวันเดียวกัน → กรอบแดง + ป้าย "ทับเวลา"
  final bool clash;
  final Occurrence o;
  final ActivityCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final (rawBg, fg) = occurrenceColors(c, o, category?.colorKey);
    // รอบติว = พื้นจาง + กรอบ · คาบเรียน/สอบ = พื้นทึบ
    final tutor = o.kind == ActivityKind.tutor;
    final bg = tutor ? rawBg.withValues(alpha: 0.35) : rawBg;
    final faded = !o.active;
    final status = _statusText(o);
    final icon = _statusIcon(o.status);

    // ยิ่งนานกล่องยิ่งสูง (ให้เห็นช่วงเวลา) แต่ไม่เตี้ย/สูงเกินไป
    final minutes = o.endAt!.difference(o.startAt!).inMinutes;
    final height = (52 + minutes / 60 * 14).clamp(64, 200).toDouble();

    return OccurrenceMenuArea(o: o, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      // IntrinsicHeight + minHeight: สูงตามระยะเวลา แต่ถ้าชื่อยาวจนตัดบรรทัด กล่องก็สูงตาม ไม่ล้น
      child: IntrinsicHeight(
       child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: height),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // เวลาเริ่ม │ เวลาจบ: เส้นเชื่อมสีเดียวกับหมวดงาน
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(fmtTime(o.startAt!),
                    style: TextStyle(color: c.text, fontSize: 14, fontWeight: FontWeight.w600)),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 18, top: 2, bottom: 2),
                    child: Container(width: 2, color: fg.withValues(alpha: faded ? 0.3 : 0.7)),
                  ),
                ),
                Text(fmtTime(o.endAt!), style: TextStyle(color: c.muted, fontSize: 14)),
              ],
            ),
          ),
          Expanded(
            child: Opacity(
              opacity: faded ? 0.5 : 1,
              child: Material(
                color: bg,
                // Material ห้ามใส่ทั้ง borderRadius และ shape → ใช้ shape อย่างเดียว
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: clash
                      ? BorderSide(color: c.bad, width: 2)
                      : (tutor ? BorderSide(color: fg.withValues(alpha: 0.6), width: 1.5) : BorderSide.none),
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                markedTitle(o),
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: o.importance == 3 ? FontWeight.w600 : FontWeight.w400,
                                  color: fg,
                                  decoration: faded ? TextDecoration.lineThrough : null,
                                ),
                              ),
                              Text(
                                [
                                  if (clash) '⚠ ทับเวลา',
                                  if (o.kind == ActivityKind.exam) 'สอบ',
                                  if (tutor) 'ติว',
                                  if (o.session?.total != null) o.session!.label,
                                  durationText(minutes),
                                  if (category != null) category!.name,
                                  if (o.importance == 3) 'สำคัญ',
                                  if (status != null) status,
                                ].join(' · '),
                                style: TextStyle(fontSize: 12, color: fg.withValues(alpha: 0.8)),
                              ),
                            ],
                          ),
                        ),
                        if (icon != null) Icon(icon, size: 20, color: o.status == OccurrenceStatus.done ? c.good : fg),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          ],
          ),
        ),
      ),
    ));
  }
}

/// งานแบบลิสต์ 1 ครั้ง (ไม่มีเวลา)
class _ListRow extends StatelessWidget {
  const _ListRow({required this.o, required this.category, required this.onTap});

  final Occurrence o;
  final ActivityCategory? category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final status = _statusText(o);
    final faded = !o.active;
    return OccurrenceMenuArea(o: o, child: ListTile(
      onTap: onTap,
      leading: Icon(
        _statusIcon(o.status) ?? Icons.radio_button_unchecked,
        color: o.status == OccurrenceStatus.done ? c.good : c.muted,
      ),
      title: Text(
        o.title,
        style: TextStyle(decoration: faded ? TextDecoration.lineThrough : null),
      ),
      subtitle: Text([
        if (o.session?.total != null) o.session!.label,
        if (category != null) category!.name,
        'ความสำคัญ: ${importanceText(o.importance)}',
        if (status != null) status,
      ].join(' · ')),
    ));
  }
}
