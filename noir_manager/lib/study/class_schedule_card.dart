import 'package:flutter/material.dart';

import '../calendar/calendar_flows.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart';
import '../calendar/class_stats.dart';
import '../data/study_models.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import 'credit_hours.dart';

/// การ์ด "ตารางเรียน + วันสอบ + สถิติเวลาเลิก" ของวิชาที่เลือก (ในหน้าวิชา)
///
/// คาบเรียน = งานในปฏิทินที่ผูก subject_id ไว้ → แก้ที่นี่หรือในปฏิทินก็ได้ ข้อมูลเดียวกัน
class ClassScheduleCard extends StatefulWidget {
  const ClassScheduleCard({super.key, required this.subject});

  final Subject subject;

  @override
  State<ClassScheduleCard> createState() => _ClassScheduleCardState();
}

class _ClassScheduleCardState extends State<ClassScheduleCard>
    with CalendarListener<ClassScheduleCard> {
  List<Activity> _activities = [];
  List<Occurrence> _occurrences = [];

  @override
  void didUpdateWidget(ClassScheduleCard old) {
    super.didUpdateWidget(old);
    if (old.subject.id != widget.subject.id) reload();
  }

  @override
  Future<void> reload() async {
    final id = widget.subject.id;
    final acts = await calendar!.activitiesForSubject(id);
    final occs = await calendar!.occurrencesForSubject(id);
    if (!mounted || id != widget.subject.id) return;
    setState(() {
      _activities = acts;
      _occurrences = occs;
    });
  }

  /// คาบประจำ (ซ้ำทุกสัปดาห์) รวมช่วงที่ตารางเดียวกันแต่แยกช่วงเวลา (เช่น ก่อน/หลังกลางภาค)
  List<(String, List<Activity>)> get _slots {
    final groups = <String, List<Activity>>{};
    for (final a in _activities.where((a) => a.repeat == RepeatKind.weekly && a.timed)) {
      // ประเภท/ห้อง/กลุ่มต่างกัน = คนละคาบ แม้เวลาเดียวกัน
      final i = a.classInfo;
      final key = '${weekdaysToText(a.weekdays)}|${a.startMinute}|${a.durationMin}|${i.type}|${i.room}|${i.section}';
      (groups[key] ??= []).add(a);
    }
    return groups.entries.map((e) => (e.key, e.value)).toList()
      ..sort((x, y) => x.$1.compareTo(y.$1));
  }

  List<Activity> get _exams =>
      _activities.where((a) => a.repeat == RepeatKind.none).toList()
        ..sort((a, b) => a.startDate.compareTo(b.startDate));

  Future<void> _addSlot() async {
    final repo = calendar!;
    final draft = await _askSlot(context);
    if (draft == null) return;
    final learn = studyCategoryId(await repo.categories());

    // เช็กเวลาทับ (คาบแรกของแต่ละวันที่เลือก) · ทับได้ แค่เตือนสั้น ๆ ด้านล่าง
    final clashes = <String>{};
    for (final wd in draft.weekdays) {
      var d = draft.from;
      while (d.weekday != wd) {
        d = DateTime(d.year, d.month, d.day + 1);
      }
      if (d.isAfter(draft.to)) continue;
      final start = atMinute(d, draft.start);
      for (final o in findOverlaps(
          await repo.occurrencesOn(d), start, start.add(Duration(minutes: draft.minutes)))) {
        clashes.add('${o.title.replaceFirst('เรียน · ', '')} '
            '(${thaiWeekdayShort[wd - 1]} ${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)})');
      }
    }

    await repo.addActivity(NewActivity(
      name: 'เรียน · ${widget.subject.name}',
      categoryId: learn,
      importance: 3,
      timed: true,
      day: draft.from,
      startMinute: draft.start,
      durationMin: draft.minutes,
      repeat: RepeatKind.weekly,
      weekdays: draft.weekdays,
      endDate: draft.to,
      subjectId: widget.subject.id,
      kind: ActivityKind.classSession,
      classInfo: draft.info,
    ));
    if (clashes.isNotEmpty && mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
          behavior: SnackBarBehavior.floating,
          width: 420,
          content: Text('⚠ ทับกับ ${clashes.join(', ')}',
              maxLines: 2, overflow: TextOverflow.ellipsis),
        ));
    }
  }

  Future<void> _slotMenu(List<Activity> group) async {
    final repo = calendar!;
    final a = group.first;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final g in group)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text('แก้ไขช่วง ${thaiShortDate(g.startDate)} – '
                    '${g.endDate == null ? 'ไม่กำหนด' : thaiShortDate(g.endDate!)}'),
                onTap: () => Navigator.pop(ctx, 'edit:${g.id}'),
              ),
            ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('ตั้งประเภท / ห้อง / กลุ่มเรียน'),
              onTap: () => Navigator.pop(ctx, 'info'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('ลบคาบนี้ (ทุกช่วง)'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    if (action == 'info') {
      final info = await _askClassInfo(context, a.classInfo);
      if (info == null) return;
      for (final g in group) {
        await repo.updateActivity(g.id, g.toDraft().withClassInfo(info));
      }
    } else if (action == 'delete') {
      if (!await confirmDelete(context, a.name)) return;
      for (final g in group) {
        await repo.deleteActivity(g.id);
      }
    } else {
      await editActivityFlow(context, repo, int.parse(action.split(':').last));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final stats = classTimeStats(_occurrences);
    final title = TextStyle(fontWeight: FontWeight.w600, color: c.text);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ----- ตารางเรียน -----
            Row(
              children: [
                Expanded(child: Text('ตารางเรียน', style: title)),
                TextButton.icon(
                  onPressed: _addSlot,
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มคาบ'),
                ),
              ],
            ),
            if (_slots.isEmpty)
              Text('ยังไม่มีคาบเรียน · กด "เพิ่มคาบ" ใส่วันและเวลาเรียนประจำ',
                  style: TextStyle(color: c.muted))
            else
              _CreditCheckRow(credits: widget.subject.credits, activities: _activities),
            for (final (_, group) in _slots)
              _SlotTile(
                group: group,
                stats: classTimeStats(_occurrences.where(
                    (o) => group.any((g) => g.id == o.activityId))),
                onTap: () => _slotMenu(group),
              ),

            // ----- วันสอบ -----
            if (_exams.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('วันสอบ', style: title),
              const SizedBox(height: 4),
              for (final e in _exams)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    '${e.name.split(' · ').first} · ${thaiShortDate(e.startDate)} '
                    '${rangeText(e.startMinute ?? 0, e.durationMin ?? 0)}',
                    style: TextStyle(color: c.text),
                  ),
                ),
            ],

            // ----- สถิติเวลาเลิก -----
            const SizedBox(height: 12),
            Text('เวลาเลิกจริง', style: title),
            const SizedBox(height: 4),
            if (stats.count == 0)
              Text(
                'ยังไม่มีข้อมูล · หลังเรียน แตะคาบในปฏิทิน → ทำแล้ว → เลือกเวลาเลิกจริง',
                style: TextStyle(color: c.muted),
              )
            else ...[
              Text(
                'เฉลี่ย ${diffText(stats.averageDiff)} · จาก ${stats.count} คาบ',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: stats.averageDiff > onTimeTolerance
                      ? c.warn
                      : (stats.averageDiff < -onTimeTolerance ? c.good : c.text),
                ),
              ),
              Text(
                'เลิกก่อน ${stats.early} · ตรงเวลา ${stats.onTime} · เลิกช้า ${stats.late}'
                '${stats.maxLate > 0 ? ' · ช้าสุด ${stats.maxLate} นาที' : ''}'
                '${stats.maxEarly > 0 ? ' · เร็วสุด ${stats.maxEarly} นาที' : ''}',
                style: TextStyle(color: c.muted, fontSize: 13),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.group, required this.stats, required this.onTap});

  final List<Activity> group;
  final ClassTimeStats stats;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final a = group.first;
    final days = (a.weekdays.toList()..sort()).map((d) => thaiWeekdayShort[d - 1]).join(' ');
    final from = group.map((g) => g.startDate).reduce((x, y) => x.isBefore(y) ? x : y);
    final ends = group.map((g) => g.endDate);
    final to = ends.any((e) => e == null)
        ? null
        : ends.whereType<DateTime>().reduce((x, y) => x.isAfter(y) ? x : y);
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: c.navBg,
        child: Text(days, style: TextStyle(fontSize: 12, color: c.navText)),
      ),
      title: Text('${classTypeLabel(a.classInfo.type)} · '
          '${rangeText(a.startMinute!, a.durationMin!)} · ${durationText(a.durationMin!)}',
          style: TextStyle(color: a.classInfo.type == null ? c.muted : null)),
      subtitle: Text([
        if (a.classInfo.section != null) 'กลุ่ม ${a.classInfo.section}',
        if (a.classInfo.room != null) 'ห้อง ${a.classInfo.room}',
        '${thaiShortDate(from)} – ${to == null ? 'ไม่กำหนด' : thaiShortDate(to)}',
        if (group.length > 1) 'เว้นช่วงสอบ',
        if (stats.count > 0) 'เลิกจริงเฉลี่ย ${diffText(stats.averageDiff)}',
      ].join(' · ')),
      trailing: const Icon(Icons.chevron_right),
    );
  }
}

typedef _SlotDraft = ({Set<int> weekdays, int start, int minutes, DateTime from, DateTime to, ClassInfo info});

/// กล่องเพิ่มคาบเรียนประจำ: วันในสัปดาห์ · เวลาเริ่ม–เลิก · ช่วงวันที่ของเทอม
Future<_SlotDraft?> _askSlot(BuildContext context) async {
  final room = TextEditingController(), section = TextEditingController();
  ClassType? type = ClassType.theory;
  var weekdays = <int>{DateTime.now().weekday};
  var start = 9 * 60;
  var minutes = 120;
  var from = dayOnly(DateTime.now());
  var to = from.add(const Duration(days: 7 * 13 - 3)); // ~3 เดือน (13 สัปดาห์)

  final result = await showDialog<_SlotDraft>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('เพิ่มคาบเรียน'),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ClassInfoFields(
                  type: type,
                  onType: (t) => setLocal(() => type = t),
                  room: room,
                  section: section,
                ),
                const SizedBox(height: 12),
                const Text('เรียนวันไหน (เลือกได้หลายวัน)'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (var d = 1; d <= 7; d++)
                      FilterChip(
                        label: Text(thaiWeekdayShort[d - 1]),
                        selected: weekdays.contains(d),
                        onSelected: (on) => setLocal(() {
                          weekdays = on ? {...weekdays, d} : ({...weekdays}..remove(d));
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                PickerTile(
                  icon: Icons.schedule,
                  label: 'เวลาเริ่มเรียน',
                  value: fmtMinute(start),
                  onTap: () async {
                    final m = await pickMinute(ctx, start, title: 'เวลาเริ่มเรียน');
                    if (m != null) setLocal(() => start = m);
                  },
                ),
                PickerTile(
                  icon: Icons.flag_outlined,
                  label: 'เวลาเลิกเรียน (ตามตาราง)',
                  value: fmtMinute(start + minutes),
                  onTap: () async {
                    final m = await pickMinute(ctx, (start + minutes) % (24 * 60),
                        title: 'เวลาเลิกเรียนตามตาราง (เริ่ม ${fmtMinute(start)})');
                    if (m != null) setLocal(() => minutes = durationBetween(start, m));
                  },
                ),
                Text('คาบละ ${durationText(minutes)}',
                    style: TextStyle(color: ctx.noir.muted, fontSize: 13)),
                const SizedBox(height: 8),
                PickerTile(
                  icon: Icons.event,
                  label: 'เริ่มเทอม',
                  value: thaiShortDate(from),
                  onTap: () async {
                    final d = await pickDay(ctx, from);
                    if (d != null) setLocal(() => from = dayOnly(d));
                  },
                ),
                PickerTile(
                  icon: Icons.event_busy,
                  label: 'คาบสุดท้าย',
                  value: thaiShortDate(to),
                  onTap: () async {
                    final d = await pickDay(ctx, to);
                    if (d != null) setLocal(() => to = dayOnly(d));
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: weekdays.isEmpty || to.isBefore(from)
                ? null
                : () => Navigator.pop(ctx, (
                      weekdays: weekdays,
                      start: start,
                      minutes: minutes,
                      from: from,
                      to: to,
                      info: ClassInfo(type: type, room: room.text.trim(), section: section.text.trim())
                          .normalized,
                    )),
            child: const Text('เพิ่มคาบ'),
          ),
        ],
      ),
    ),
  );
  room.dispose();
  section.dispose();
  return result;
}

/// ประเภท (ทฤษฎี/ปฏิบัติ/ไม่ระบุ) + ห้อง + กลุ่มเรียน · ใช้ทั้งตอนเพิ่มคาบและตอนแก้คาบเดิม
class _ClassInfoFields extends StatelessWidget {
  const _ClassInfoFields({required this.type, required this.onType, required this.room, required this.section});

  final ClassType? type;
  final ValueChanged<ClassType?> onType;
  final TextEditingController room;
  final TextEditingController section;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('ประเภทคาบ'),
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in [ClassType.theory, ClassType.lab, null])
              ChoiceChip(
                label: Text(t == null ? 'ไม่ระบุ' : '${classTypeLabel(t)} (${t == ClassType.theory ? 'S' : 'L'})'),
                selected: type == t,
                onSelected: (_) => onType(t),
              ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                controller: section,
                decoration: const InputDecoration(labelText: 'กลุ่มเรียน', hintText: 'S.1 / L.1'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: room,
                decoration: const InputDecoration(labelText: 'ห้อง', hintText: '1-B4-08'),
              ),
            ),
          ]),
        ],
      );
}

/// แก้ประเภท/ห้อง/กลุ่มของคาบที่มีอยู่ (เช่นคาบเก่าก่อน v11)
Future<ClassInfo?> _askClassInfo(BuildContext context, ClassInfo initial) async {
  final room = TextEditingController(text: initial.room ?? '');
  final section = TextEditingController(text: initial.section ?? '');
  var type = initial.type;
  final result = await showDialog<ClassInfo>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: const Text('ประเภท / ห้อง / กลุ่มเรียน'),
        content: SizedBox(
          width: 420,
          child: _ClassInfoFields(
            type: type,
            onType: (t) => setLocal(() => type = t),
            room: room,
            section: section,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(
                ctx, ClassInfo(type: type, room: room.text.trim(), section: section.text.trim()).normalized),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
  room.dispose();
  section.dispose();
  return result;
}

/// แถวตรวจชั่วโมงเรียนกับหน่วยกิต เช่น "3(2-2-5) · ทฤษฎี 2/2 ✓ · ปฏิบัติ 0/2 ขาด 2"
class _CreditCheckRow extends StatelessWidget {
  const _CreditCheckRow({required this.credits, required this.activities});

  final String? credits;
  final List<Activity> activities;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final check = checkCredits(credits, activities);
    if (check == null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          (credits ?? '').isEmpty
              ? 'ใส่หน่วยกิต เช่น 3(2-2-5) ในแผนการเรียน เพื่อตรวจชั่วโมงเรียน'
              : 'หน่วยกิต $credits · ตรวจชั่วโมงอัตโนมัติไม่ได้',
          style: TextStyle(color: c.muted, fontSize: 13),
        ),
      );
    }
    Widget part(String label, HourCheck h) {
      final (text, color) = switch (h.status) {
        HourStatus.ok => ('${hoursText(h.have)}/${hoursText(h.need)} ✓', c.good),
        HourStatus.short => ('${hoursText(h.have)}/${hoursText(h.need)} ขาด ${hoursText(h.need - h.have)}', c.warn),
        HourStatus.over => ('${hoursText(h.have)}/${hoursText(h.need)} เกิน ${hoursText(h.have - h.need)}', c.bad),
      };
      return Text('$label $text', style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600));
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(spacing: 12, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('หน่วยกิต ${check.hours.credits}(${check.hours.theory}-${check.hours.lab}-${check.hours.self})',
            style: TextStyle(color: c.muted, fontSize: 13)),
        part('ทฤษฎี', check.theory),
        part('ปฏิบัติ', check.lab),
        if (check.unknown > 0)
          Text(
            check.totalMatchesOnly
                ? 'รวมครบแล้ว · แตะคาบเพื่อตั้งประเภท'
                : 'ไม่ระบุประเภท ${hoursText(check.unknown)} ชม. · แตะคาบเพื่อตั้งประเภท',
            style: TextStyle(color: c.muted, fontSize: 13),
          ),
        Text('ศึกษาเอง ${check.hours.self} ชม./สัปดาห์', style: TextStyle(color: c.muted, fontSize: 13)),
      ]),
    );
  }
}
