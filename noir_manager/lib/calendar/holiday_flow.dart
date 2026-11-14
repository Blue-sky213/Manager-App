/// วันหยุด → กล่องเลื่อน 4 ทาง (แผนรวม v0.2 · must-have #6)
///
/// เพิ่มวันหยุด → ระบบหางานที่ตรงวันนั้น → จัดกลุ่มตาม Preset (ไม่มี Preset = ตามหมวด)
/// → เลือกทางเลื่อนทีเดียวทั้งกลุ่ม หรือเปลี่ยนรายตัว → "จำตัวเลือกนี้" ได้รายกลุ่ม
library;

import 'package:flutter/material.dart';

import '../utils/thai_date.dart';
import '../widgets/mini_form.dart';
import 'calendar_flows.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import '../widgets/toast.dart';

/// 4 ทางของกล่องเลื่อน (ลำดับตามสเปก)
enum HolidayChoice { shift, reschedule, inbox, cancel }

String holidayChoiceLabel(HolidayChoice c) => switch (c) {
      HolidayChoice.shift => 'เลื่อนไปรอบถัดไป',
      HolidayChoice.reschedule => 'นัดวันเวลาอื่น',
      HolidayChoice.inbox => 'รอนัด',
      HolidayChoice.cancel => 'ยกเลิก',
    };

/// งาน 1 ครั้งที่ตรงวันหยุด + ข้อมูลที่ใช้จัดกลุ่ม
class HolidayItem {
  const HolidayItem({
    required this.o,
    required this.a,
    required this.groupKey,
    required this.groupName,
    required this.isStudy,
  });

  final Occurrence o;
  final Activity a;

  /// 'preset_3' / 'cat_1' / 'none' — ใช้เป็น key ของ "จำตัวเลือกนี้" ด้วย
  final String groupKey;
  final String groupName;

  /// หมวดเรียน / คาบ / สอบ / ติว → ค่าเริ่มต้น "รอนัด" และติ๊กว่าโดนวันหยุดไว้ก่อน
  final bool isStudy;

  bool get canShift => canShiftToNextRound(a);
}

/// key ใน setting ของตัวเลือกที่จำไว้
String holidayChoiceKey(String groupKey) => 'holiday_choice_$groupKey';

/// ค่าเริ่มต้นตามสเปก: เรียน → รอนัด · อื่น ๆ → ยกเลิก · มีที่จำไว้ใช้ที่จำไว้
HolidayChoice defaultHolidayChoice(bool isStudy, {String? remembered}) {
  final saved = HolidayChoice.values.where((c) => c.name == remembered).firstOrNull;
  return saved ?? (isStudy ? HolidayChoice.inbox : HolidayChoice.cancel);
}

/// เลือก "เลื่อนไปรอบถัดไป" กับงานที่ไม่มีรอบถัดไป → ใช้ "รอนัด" แทน (ไม่บล็อก แค่บอก)
HolidayChoice effectiveChoice(HolidayChoice c, HolidayItem item) =>
    c == HolidayChoice.shift && !item.canShift ? HolidayChoice.inbox : c;

/// งานที่ยังเป็นแผนในช่วงวันหยุด [from]–[to] จัดกลุ่มแล้ว (เรียงชื่อกลุ่ม)
Future<Map<String, List<HolidayItem>>> collectHolidayItems(
    CalendarRepository repo, DateTime from, DateTime to) async {
  final cats = {for (final c in await repo.categories()) c.id: c};
  final presets = {for (final p in await repo.presets()) p.id: p};
  final studyId = studyCategoryId(cats.values.toList());
  final groups = <String, List<HolidayItem>>{};
  for (var d = dayOnly(from); !d.isAfter(dayOnly(to)); d = DateTime(d.year, d.month, d.day + 1)) {
    for (final o in await repo.occurrencesOn(d)) {
      if (o.status != OccurrenceStatus.planned) continue;
      final a = await repo.activity(o.activityId);
      final preset = a.presetId == null ? null : presets[a.presetId];
      final cat = cats[o.categoryId];
      final (key, name) = preset != null
          ? ('preset_${preset.id}', 'Preset: ${preset.name}')
          : cat != null
              ? ('cat_${cat.id}', cat.name)
              : ('none', 'ไม่มีหมวด');
      final study = (studyId != null && o.categoryId == studyId) ||
          o.kind != ActivityKind.todo;
      (groups[key] ??= []).add(HolidayItem(
          o: o, a: a, groupKey: key, groupName: name, isStudy: study));
    }
  }
  return Map.fromEntries(
      groups.entries.toList()..sort((x, y) => x.value.first.groupName.compareTo(y.value.first.groupName)));
}

/// เลื่อนไปรอบถัดไป 1 ครั้ง (ใช้จากแผ่นตัวเลือกตอนแตะงาน) → แจ้งผลแถบล่าง
Future<void> shiftFlow(BuildContext context, CalendarRepository repo, Occurrence o,
    {String reason = 'กดเลื่อนเอง'}) async {
  final a = await repo.activity(o.activityId);
  if (!context.mounted) return;
  if (!canShiftToNextRound(a)) {
    _toast(context, 'งานนี้ไม่มีรอบถัดไป → ใช้ "เลื่อน" เลือกวันใหม่แทน');
    return;
  }
  final end = await repo.shiftToNextRound(o.id, reason);
  if (!context.mounted) return;
  _toast(
      context,
      end == null
          ? '"${o.title}" เลื่อนไปรอบถัดไปแล้ว'
          : '"${o.title}" เลื่อนไปรอบถัดไป · วันสุดท้ายขยายเป็น ${thaiShortDate(end)}');
}

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  showToast(context, text);
}

/// เพิ่มวันหยุดแล้ว → กล่องเลือกทางเลื่อนของงานที่โดน
Future<void> holidayFlow(BuildContext context, CalendarRepository repo,
    DateTime from, DateTime to, String name) async {
  final groups = await collectHolidayItems(repo, from, to);
  if (!context.mounted) return;
  if (groups.isEmpty) {
    _toast(context, 'บันทึกวันหยุด "$name" แล้ว · ไม่มีงานที่ตรงวันนี้');
    return;
  }

  // สถานะในกล่อง: กลุ่มไหนโดน · ตัวเลือกของกลุ่ม · ตัวเลือกรายตัว · จำไว้ไหม
  final included = <String, bool>{};
  final groupChoice = <String, HolidayChoice>{};
  final itemChoice = <int, HolidayChoice>{};
  final remember = <String, bool>{};
  for (final e in groups.entries) {
    final first = e.value.first;
    final saved = await repo.getSetting(holidayChoiceKey(e.key));
    included[e.key] = e.value.any((i) => i.isStudy);
    groupChoice[e.key] = defaultHolidayChoice(first.isStudy, remembered: saved);
    remember[e.key] = false;
    for (final i in e.value) {
      itemChoice[i.o.id] = groupChoice[e.key]!;
    }
  }
  if (!context.mounted) return;

  final when = dayOnly(from) == dayOnly(to)
      ? thaiShortDate(from)
      : '${thaiShortDate(from)} – ${thaiShortDate(to)}';
  final count = groups.values.fold<int>(0, (n, l) => n + l.length);

  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final muted = TextStyle(fontSize: 12, color: Theme.of(ctx).hintColor);
        return MiniForm(
          title: 'วันหยุด: $name',
          maxWidth: 560,
          secondaryLabel: 'ไว้ทีหลัง',
          primaryLabel: 'ยืนยัน',
          onPrimary: () => Navigator.pop(ctx, true),
          children: [
                  Text('$when · งานที่ตรงวันหยุด $count รายการ', style: muted),
                  Text('ติ๊กกลุ่มที่หยุด · กลุ่มที่ไม่ติ๊กยังเหมือนเดิม', style: muted),
                  const SizedBox(height: 8),
                  for (final e in groups.entries) ...[
                    const Divider(),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: included[e.key],
                      onChanged: (v) => setLocal(() => included[e.key] = v ?? false),
                      title: Text('${e.value.first.groupName} · ${e.value.length} รายการ',
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                    if (included[e.key]!) ...[
                      // เลือกทีเดียวทั้งกลุ่ม → ทุกตัวในกลุ่มเปลี่ยนตาม
                      Wrap(spacing: 6, runSpacing: 6, children: [
                        for (final c in HolidayChoice.values)
                          ChoiceChip(
                            showCheckmark: false,
                            label: Text(holidayChoiceLabel(c)),
                            selected: groupChoice[e.key] == c,
                            onSelected: (_) => setLocal(() {
                              groupChoice[e.key] = c;
                              for (final i in e.value) {
                                itemChoice[i.o.id] = c;
                              }
                            }),
                          ),
                      ]),
                      for (final i in e.value)
                        ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.only(left: 8),
                          title: Text(i.o.title),
                          subtitle: Text([
                            thaiShortDate(i.o.day),
                            if (i.o.session != null) i.o.session!.label,
                            if (itemChoice[i.o.id] == HolidayChoice.shift && !i.canShift)
                              'ไม่มีรอบถัดไป → ใช้ "รอนัด" แทน',
                          ].join(' · ')),
                          // เปลี่ยนรายตัว
                          trailing: PopupMenuButton<HolidayChoice>(
                            tooltip: 'เปลี่ยนเฉพาะงานนี้',
                            initialValue: itemChoice[i.o.id],
                            onSelected: (c) => setLocal(() => itemChoice[i.o.id] = c),
                            itemBuilder: (_) => [
                              for (final c in HolidayChoice.values)
                                PopupMenuItem(value: c, child: Text(holidayChoiceLabel(c))),
                            ],
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Text(holidayChoiceLabel(effectiveChoice(itemChoice[i.o.id]!, i)),
                                  style: TextStyle(color: Theme.of(ctx).colorScheme.primary)),
                            ),
                          ),
                        ),
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: remember[e.key],
                        onChanged: (v) => setLocal(() => remember[e.key] = v ?? false),
                        title: const Text('จำตัวเลือกนี้สำหรับกลุ่มนี้'),
                      ),
                    ],
                  ],
                ],
        );
      },
    ),
  );
  if (ok != true || !context.mounted) return;

  // ทำตามที่เลือก · นับผลไว้แจ้งแถบล่าง
  final reason = 'วันหยุด: $name';
  final toReschedule = <Occurrence>[];
  var shifted = 0, inbox = 0, cancelled = 0;
  DateTime? lastEnd;
  for (final e in groups.entries) {
    if (!included[e.key]!) continue;
    if (remember[e.key]!) {
      await repo.setSetting(holidayChoiceKey(e.key), groupChoice[e.key]!.name);
    }
    for (final i in e.value) {
      switch (effectiveChoice(itemChoice[i.o.id]!, i)) {
        case HolidayChoice.shift:
          lastEnd = await repo.shiftToNextRound(i.o.id, reason) ?? lastEnd;
          shifted++;
        case HolidayChoice.reschedule:
          toReschedule.add(i.o);
        case HolidayChoice.inbox:
          await repo.sendToInbox(i.o.id);
          inbox++;
        case HolidayChoice.cancel:
          await repo.cancel(i.o.id, reason);
          cancelled++;
      }
    }
  }
  if (!context.mounted) return;
  final parts = [
    if (shifted > 0) 'เลื่อนรอบถัดไป $shifted',
    if (inbox > 0) 'รอนัด $inbox',
    if (cancelled > 0) 'ยกเลิก $cancelled',
    if (toReschedule.isNotEmpty) 'นัดวันอื่น ${toReschedule.length}',
  ];
  _toast(context, [
    'วันหยุด "$name": ${parts.isEmpty ? 'ไม่มีงานที่เปลี่ยน' : parts.join(' · ')}',
    if (lastEnd != null) 'วันสุดท้ายขยายเป็น ${thaiShortDate(lastEnd)}',
  ].join(' · '));

  // "นัดวันเวลาอื่น" → เปิดกล่องเลื่อนเดิมทีละงาน
  for (final o in toReschedule) {
    if (!context.mounted) return;
    await rescheduleFlow(context, repo, o);
  }
}
