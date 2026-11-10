import 'package:flutter/material.dart';

import '../study/subject_colors.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'calendar_models.dart';

// ---------- ตัวช่วยเล็ก ๆ ----------

const List<String> thaiWeekdayShort = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
const List<String> thaiWeekdayLong = [
  'จันทร์', 'อังคาร', 'พุธ', 'พฤหัสบดี', 'ศุกร์', 'เสาร์', 'อาทิตย์',
];

String importanceText(int importance) => switch (importance) {
      3 => 'สำคัญ',
      2 => 'กลาง',
      _ => 'น้อย',
    };

/// สีพื้น + ตัวหนังสือของแต่ละหมวด (ตามธีมมืด/สว่าง)
(Color, Color) categoryColors(NoirColors c, String? colorKey) =>
    switch (colorKey) {
      'blue' => (c.navBg, c.navText),
      'green' => (c.greenBg, c.greenText),
      'purple' => (c.purpleBg, c.purpleText),
      'amber' => (c.amberBg, c.amberText),
      _ => (c.surface2, c.text),
    };

/// สีกล่องงาน: งานที่ผูกวิชา (คาบ / สอบ / ติว) → สีประจำวิชา ชุดเดียวกับตารางเรียนและแผนผัง
/// งานอื่น → สีหมวด · ตัวหนังสือใช้สีหลักของธีม อ่านออกทั้งมืด/สว่าง
(Color, Color) occurrenceColors(NoirColors c, Occurrence o, String? colorKey) {
  final sc = o.subjectId == null ? null : subjectColors.value[o.subjectId];
  if (sc == null) return categoryColors(c, colorKey);
  return (Color.alphaBlend(sc.withValues(alpha: 0.28), c.surface), c.text);
}

String durationText(int min) => min < 60
    ? '$min นาที'
    : (min % 60 == 0 ? '${min ~/ 60} ชม.' : '${min ~/ 60} ชม. ${min % 60} นาที');

/// เลือกวัน (ปฏิทิน Material)
Future<DateTime?> pickDay(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 2),
    );

/// เลือกเวลาแบบ 24 ชม. → คืนเป็นนาทีนับจากเที่ยงคืน
/// [title] = หัวข้อบนกล่อง เช่น "เวลาเริ่มกิจกรรม" (จะได้รู้ว่ากำลังเลือกอะไร)
Future<int?> pickMinute(BuildContext context, int initial, {String title = 'เลือกเวลา'}) async {
  final t = await showTimePicker(
    context: context,
    helpText: title,
    initialTime: TimeOfDay(hour: initial ~/ 60 % 24, minute: initial % 60),
    builder: (ctx, child) => MediaQuery(
      data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
      child: child!,
    ),
  );
  return t == null ? null : t.hour * 60 + t.minute;
}

/// แถวกดได้: ไอคอน + หัวข้อ + ค่า (ใช้ในฟอร์ม)
class PickerTile extends StatelessWidget {
  const PickerTile({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon),
        title: Text(label),
        trailing: Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
        onTap: onTap,
      );
}

// ---------- ฟอร์มเพิ่มงาน / แก้ไขงาน ----------

/// ระยะเวลาจากเวลาเริ่ม → เวลาจบ (จบก่อนหรือเท่ากับเริ่ม = ข้ามเที่ยงคืน)
int durationBetween(int startMinute, int endMinute) {
  final d = (endMinute - startMinute) % (24 * 60);
  return d == 0 ? 24 * 60 : d;
}

String durationLabel(int start, int duration) =>
    '${durationText(duration)}${start + duration > 24 * 60 ? ' · ข้ามเที่ยงคืน' : ''}';

/// เลือกเวลาเริ่ม แล้วต่อด้วยเวลาจบ → (เริ่ม, ระยะเวลา) · null = ยกเลิก
Future<(int, int)?> pickRange(BuildContext context, int start, int duration) async {
  final s = await pickMinute(context, start, title: 'เวลาเริ่มกิจกรรม');
  if (s == null || !context.mounted) return null;
  final e = await pickMinute(context, (s + duration) % (24 * 60), title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(s)})');
  if (e == null) return null;
  return (s, durationBetween(s, e));
}

Future<NewActivity?> showActivityDialog(
  BuildContext context, {
  required DateTime day,
  required List<ActivityCategory> categories,
  required List<Preset> presets,
  NewActivity? initial,
  bool editing = false,
  Future<int> Function(String name, NewActivity values)? onSavePreset,
  Future<void> Function(int presetId)? onDeletePreset,
}) =>
    showDialog<NewActivity>(
      context: context,
      builder: (_) => _ActivityDialog(
        day: day,
        categories: categories,
        presets: presets,
        initial: initial,
        editing: editing,
        onSavePreset: onSavePreset,
        onDeletePreset: onDeletePreset,
      ),
    );

class _ActivityDialog extends StatefulWidget {
  const _ActivityDialog({
    required this.day,
    required this.categories,
    required this.presets,
    required this.initial,
    required this.editing,
    required this.onSavePreset,
    required this.onDeletePreset,
  });

  final DateTime day;
  final List<ActivityCategory> categories;
  final List<Preset> presets;
  final NewActivity? initial;
  final bool editing;
  final Future<int> Function(String name, NewActivity values)? onSavePreset;
  final Future<void> Function(int presetId)? onDeletePreset;

  @override
  State<_ActivityDialog> createState() => _ActivityDialogState();
}

class _ActivityDialogState extends State<_ActivityDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late final List<Preset> _presets = List.of(widget.presets);
  late int? _presetId = widget.presets.any((p) => p.id == widget.initial?.presetId)
      ? widget.initial?.presetId
      : null;
  late int? _categoryId = widget.initial?.categoryId ??
      (widget.categories.isEmpty ? null : widget.categories.first.id);
  late int _importance = widget.initial?.importance ?? 2;
  late bool _timed = widget.initial?.timed ?? true;
  late DateTime _day = dayOnly(widget.initial?.day ?? widget.day);
  late int _start = widget.initial?.startMinute ?? 18 * 60;
  late int _duration = widget.initial?.durationMin ?? 60;
  late RepeatKind _repeat = widget.initial?.repeat ?? RepeatKind.none;
  late Set<int> _weekdays = {...?widget.initial?.weekdays};
  late DateTime? _endDate = widget.initial?.endDate;
  late List<ScheduledDate> _dates = [...?widget.initial?.dates];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  NewActivity get _draft => NewActivity(
        name: _name.text.trim(),
        categoryId: _categoryId,
        importance: _importance,
        timed: _timed,
        day: _day,
        startMinute: _timed ? _start : null,
        durationMin: _timed ? _duration : null,
        repeat: _repeat,
        weekdays: _repeat == RepeatKind.weekly ? _weekdays : const {},
        endDate: _repeat == RepeatKind.daily || _repeat == RepeatKind.weekly
            ? _endDate
            : null,
        presetId: _presetId,
        dates: _repeat == RepeatKind.dates ? _dates : const [],
        subjectId: widget.initial?.subjectId, // แก้ไขคาบเรียนแล้วยังผูกวิชาเดิม
        kind: widget.initial?.kind ?? ActivityKind.todo,
        classInfo: widget.initial?.classInfo ?? ClassInfo.none, // แก้เวลาในปฏิทินแล้วประเภท/ห้องไม่หาย
      );

  String? get _problem {
    if (_name.text.trim().isEmpty) return 'ใส่ชื่องาน';
    if (_repeat == RepeatKind.weekly && _weekdays.isEmpty) return 'เลือกวันในสัปดาห์อย่างน้อย 1 วัน';
    if (_repeat == RepeatKind.dates && _dates.isEmpty) return 'เพิ่มวันอย่างน้อย 1 วัน';
    if (_endDate != null &&
        (_repeat == RepeatKind.daily || _repeat == RepeatKind.weekly) &&
        _endDate!.isBefore(_day)) {
      return 'วันสิ้นสุดต้องไม่ก่อนวันเริ่ม';
    }
    return null;
  }

  /// เลือก Preset → กรอกหมวด / ความสำคัญ / เวลาให้อัตโนมัติ
  void _applyPreset(int? id) {
    setState(() {
      _presetId = id;
      if (id == null) return;
      final p = _presets.firstWhere((x) => x.id == id);
      _categoryId = p.categoryId ?? _categoryId;
      _importance = p.importance;
      _timed = p.startMinute != null;
      if (p.startMinute != null) {
        _start = p.startMinute!;
        _duration = p.durationMin ?? _duration;
      }
    });
  }

  Future<void> _savePreset() async {
    final save = widget.onSavePreset;
    if (save == null) return;
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('บันทึกเป็น Preset'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('เก็บหมวด · ความสำคัญ · เวลาเริ่ม–จบ ตอนนี้ไว้ใช้ซ้ำ'),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(
                  labelText: 'ชื่อ Preset', hintText: 'เช่น Stream, ติวเข้ม'),
              onSubmitted: (v) => Navigator.pop(ctx, v),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('บันทึก')),
        ],
      ),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    final id = await save(trimmed, _draft);
    if (!mounted) return;
    setState(() {
      _presets.add(Preset(
        id: id,
        name: trimmed,
        categoryId: _categoryId,
        importance: _importance,
        startMinute: _timed ? _start : null,
        durationMin: _timed ? _duration : null,
      ));
      _presetId = id;
    });
  }

  Future<void> _deletePreset() async {
    final del = widget.onDeletePreset;
    final id = _presetId;
    if (del == null || id == null) return;
    await del(id);
    if (!mounted) return;
    setState(() {
      _presets.removeWhere((p) => p.id == id);
      _presetId = null;
    });
  }

  Future<void> _addDate() async {
    final d = await pickDay(context, _dates.isEmpty ? _day : _dates.last.day);
    if (d == null) return;
    final day = dayOnly(d);
    if (_dates.any((x) => x.day == day)) return;
    setState(() => _dates = [..._dates, ScheduledDate(day)]
      ..sort((a, b) => a.day.compareTo(b.day)));
  }

  Future<void> _editDateTime(int i) async {
    final d = _dates[i];
    final r = await pickRange(
        context, d.startMinute ?? _start, d.durationMin ?? _duration);
    if (r == null) return;
    setState(() {
      _dates = [..._dates]
        ..[i] = ScheduledDate(d.day, startMinute: r.$1, durationMin: r.$2);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final problem = _problem;

    return AlertDialog(
      title: Text(widget.editing ? 'แก้ไขงาน' : 'เพิ่มงาน'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ----- Preset -----
              Row(
                children: [
                  const Text('Preset'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButton<int?>(
                      isExpanded: true,
                      value: _presetId,
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('ไม่ใช้')),
                        for (final p in _presets)
                          DropdownMenuItem<int?>(value: p.id, child: Text(p.name)),
                      ],
                      onChanged: _applyPreset,
                    ),
                  ),
                  if (_presetId != null && widget.onDeletePreset != null)
                    IconButton(
                      tooltip: 'ลบ Preset นี้ (งานเดิมไม่หาย)',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _deletePreset,
                    ),
                  if (widget.onSavePreset != null)
                    IconButton(
                      tooltip: 'บันทึกค่าตอนนี้เป็น Preset ใหม่',
                      icon: const Icon(Icons.bookmark_add_outlined),
                      onPressed: _savePreset,
                    ),
                ],
              ),
              TextField(
                key: const Key('activity-name'),
                controller: _name,
                autofocus: !widget.editing,
                decoration: InputDecoration(
                  labelText: 'ชื่องาน',
                  hintText: _presetId == null ? 'เช่น ออกกำลังกาย' : 'เช่น RE4, Minecraft',
                ),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('หมวด'),
                  const SizedBox(width: 16),
                  Expanded(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: _categoryId,
                      items: [
                        for (final cat in widget.categories)
                          DropdownMenuItem(value: cat.id, child: Text(cat.name)),
                      ],
                      onChanged: (v) => setState(() => _categoryId = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('ความสำคัญ'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 3, label: Text('สำคัญ')),
                  ButtonSegment(value: 2, label: Text('กลาง')),
                  ButtonSegment(value: 1, label: Text('น้อย')),
                ],
                selected: {_importance},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _importance = s.first),
              ),
              const SizedBox(height: 8),

              // ----- เวลา -----
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ล็อกเวลา'),
                subtitle: Text(_timed
                    ? 'มีเวลาเริ่ม–จบ แสดงในตารางเวลา'
                    : 'แบบลิสต์: แค่ต้องทำวันนั้น ไม่กำหนดเวลา'),
                value: _timed,
                onChanged: (v) => setState(() => _timed = v),
              ),
              if (_timed) ...[
                PickerTile(
                  icon: Icons.schedule,
                  label: 'เวลาเริ่ม',
                  value: fmtMinute(_start),
                  onTap: () async {
                    final m = await pickMinute(context, _start, title: 'เวลาเริ่มกิจกรรม');
                    if (m == null) return;
                    // ขยับเวลาเริ่ม → เวลาจบเลื่อนตาม (ระยะเวลาเท่าเดิม)
                    setState(() => _start = m);
                  },
                ),
                PickerTile(
                  icon: Icons.flag_outlined,
                  label: 'เวลาจบ',
                  value: fmtMinute(_start + _duration),
                  onTap: () async {
                    final m = await pickMinute(context, (_start + _duration) % (24 * 60), title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(_start)})');
                    if (m == null) return;
                    setState(() => _duration = durationBetween(_start, m));
                  },
                ),
                Text('รวม ${durationLabel(_start, _duration)}',
                    style: TextStyle(color: c.muted, fontSize: 13)),
              ],
              const SizedBox(height: 12),

              // ----- ทำซ้ำ -----
              const Text('ทำซ้ำ'),
              const SizedBox(height: 6),
              // ChoiceChip ห่อบรรทัดเองได้ → ไม่ล้นจอแคบ 420 px
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final (kind, label) in const [
                    (RepeatKind.none, 'ครั้งเดียว'),
                    (RepeatKind.daily, 'ทุกวัน'),
                    (RepeatKind.weekly, 'ทุกสัปดาห์'),
                    (RepeatKind.dates, 'เลือกวันเอง'),
                  ])
                    ChoiceChip(
                      label: Text(label),
                      selected: _repeat == kind,
                      onSelected: (_) => setState(() {
                        _repeat = kind;
                        if (_repeat == RepeatKind.weekly && _weekdays.isEmpty) {
                          _weekdays = {_day.weekday};
                        }
                        if (_repeat == RepeatKind.dates && _dates.isEmpty) {
                          _dates = [ScheduledDate(_day)];
                        }
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 4),

              if (_repeat != RepeatKind.dates)
                PickerTile(
                  icon: Icons.event,
                  label: _repeat == RepeatKind.none ? 'วันที่' : 'เริ่มวันที่',
                  value: thaiShortDate(_day),
                  onTap: () async {
                    final d = await pickDay(context, _day);
                    if (d != null) setState(() => _day = dayOnly(d));
                  },
                ),

              if (_repeat == RepeatKind.weekly)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (var d = 1; d <= 7; d++)
                        FilterChip(
                          label: Text(thaiWeekdayShort[d - 1]),
                          selected: _weekdays.contains(d),
                          onSelected: (on) => setState(() {
                            _weekdays = on ? {..._weekdays, d} : ({..._weekdays}..remove(d));
                          }),
                        ),
                    ],
                  ),
                ),

              if (_repeat == RepeatKind.daily || _repeat == RepeatKind.weekly)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_busy),
                  title: const Text('ถึงวันที่'),
                  onTap: () async {
                    final d = await pickDay(context, _endDate ?? _day.add(const Duration(days: 7)));
                    if (d != null) setState(() => _endDate = dayOnly(d));
                  },
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_endDate == null ? 'ไม่กำหนด' : thaiShortDate(_endDate!),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      if (_endDate != null)
                        IconButton(
                          tooltip: 'ไม่กำหนดวันสิ้นสุด',
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () => setState(() => _endDate = null),
                        ),
                    ],
                  ),
                ),

              if (_repeat == RepeatKind.dates) ...[
                const SizedBox(height: 4),
                Text(
                  _timed
                      ? 'แตะ 🕑 เพื่อตั้งเวลาเฉพาะวันนั้น (ไม่ตั้ง = ใช้เวลาหลักด้านบน)'
                      : 'เลือกได้หลายวัน',
                  style: TextStyle(color: c.muted, fontSize: 12),
                ),
                for (var i = 0; i < _dates.length; i++)
                  Row(
                    children: [
                      Expanded(child: Text(thaiShortDate(_dates[i].day))),
                      if (_timed)
                        TextButton.icon(
                          onPressed: () => _editDateTime(i),
                          icon: const Icon(Icons.schedule, size: 18),
                          label: Text(
                            _dates[i].customTime
                                ? rangeText(_dates[i].startMinute!,
                                    _dates[i].durationMin ?? _duration)
                                : 'เวลาหลัก',
                          ),
                        ),
                      if (_dates[i].customTime)
                        IconButton(
                          tooltip: 'กลับไปใช้เวลาหลัก',
                          icon: const Icon(Icons.undo, size: 18),
                          onPressed: () => setState(() {
                            _dates = [..._dates]..[i] = ScheduledDate(_dates[i].day);
                          }),
                        ),
                      IconButton(
                        tooltip: 'เอาวันนี้ออก',
                        icon: const Icon(Icons.remove_circle_outline, size: 20),
                        onPressed: () => setState(() {
                          _dates = [..._dates]..removeAt(i);
                        }),
                      ),
                    ],
                  ),
                TextButton.icon(
                  onPressed: _addDate,
                  icon: const Icon(Icons.add),
                  label: const Text('เพิ่มวัน'),
                ),
              ],

              if (problem != null) ...[
                const SizedBox(height: 8),
                Text(problem, style: TextStyle(color: c.bad, fontSize: 12)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: problem == null ? () => Navigator.pop(context, _draft) : null,
          child: Text(widget.editing ? 'บันทึก' : 'เพิ่มงาน'),
        ),
      ],
    );
  }
}

/// กล่องแก้เวลาเฉพาะครั้งนี้ → (เริ่ม, ระยะเวลา)
Future<(int, int)?> showOccurrenceTimeDialog(BuildContext context, Occurrence o) {
  var start = minuteOf(o.startAt!);
  var duration = o.endAt!.difference(o.startAt!).inMinutes;
  return showDialog<(int, int)>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('แก้เวลา "${o.title}" เฉพาะ ${thaiShortDate(o.day)}'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PickerTile(
                icon: Icons.schedule,
                label: 'เวลาเริ่ม',
                value: fmtMinute(start),
                onTap: () async {
                  final m = await pickMinute(ctx, start, title: 'เวลาเริ่มกิจกรรม');
                  if (m != null) setLocal(() => start = m);
                },
              ),
              PickerTile(
                icon: Icons.flag_outlined,
                label: 'เวลาจบ',
                value: fmtMinute(start + duration),
                onTap: () async {
                  final m = await pickMinute(ctx, (start + duration) % (24 * 60), title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(start)})');
                  if (m != null) setLocal(() => duration = durationBetween(start, m));
                },
              ),
              Text('รวม ${durationLabel(start, duration)} · วันอื่นของงานนี้ไม่เปลี่ยน',
                  style: TextStyle(color: ctx.noir.muted, fontSize: 13)),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, (start, duration)),
            child: const Text('บันทึก'),
          ),
        ],
      ),
    ),
  );
}

// ---------- กล่องยกเลิก (ต้องมีเหตุผล) ----------

Future<String?> askCancelReason(BuildContext context, Occurrence o) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final text = controller.text.trim();
        return AlertDialog(
          title: Text('ยกเลิก "${o.title}"'),
          content: SizedBox(
            width: 400,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ต้องใส่เหตุผลทุกครั้ง (ใช้ดูสถิติย้อนหลัง)'),
                const SizedBox(height: 8),
                TextField(
                  key: const Key('reason-field'),
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'เหตุผล'),
                  onChanged: (_) => setLocal(() {}),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final quick in ['ป่วย', 'งานด่วน', 'เหนื่อยเกินไป', 'ติดธุระ'])
                      ActionChip(
                        label: Text(quick),
                        onPressed: () => setLocal(() => controller.text = quick),
                      ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('ไม่ยกเลิก'),
            ),
            FilledButton(
              onPressed: text.isEmpty ? null : () => Navigator.pop(ctx, text),
              child: const Text('ยืนยันยกเลิก'),
            ),
          ],
        );
      },
    ),
  );
}

// ---------- กล่องเลื่อน ----------

class RescheduleResult {
  const RescheduleResult.toInbox()
      : toInbox = true,
        series = false,
        day = null,
        startMinute = null,
        durationMin = null;

  const RescheduleResult({
    required this.series,
    this.day,
    this.startMinute,
    this.durationMin,
  }) : toInbox = false;

  final bool toInbox;

  /// true = เลื่อนทั้งแถว (เปลี่ยนเวลางานซ้ำตั้งแต่ครั้งนี้)
  final bool series;
  final DateTime? day;
  final int? startMinute;
  final int? durationMin;
}

Future<RescheduleResult?> showRescheduleDialog(
  BuildContext context,
  Occurrence o, {
  bool fromInbox = false,
}) =>
    showDialog<RescheduleResult>(
      context: context,
      builder: (_) => _RescheduleDialog(o: o, fromInbox: fromInbox),
    );

class _RescheduleDialog extends StatefulWidget {
  const _RescheduleDialog({required this.o, required this.fromInbox});

  final Occurrence o;
  final bool fromInbox;

  @override
  State<_RescheduleDialog> createState() => _RescheduleDialogState();
}

class _RescheduleDialogState extends State<_RescheduleDialog> {
  late DateTime _day = widget.fromInbox
      ? dayOnly(DateTime.now()).add(const Duration(days: 1))
      : widget.o.day;
  late int _start = widget.o.timed ? minuteOf(widget.o.startAt!) : 18 * 60;
  late int _duration = widget.o.timed
      ? widget.o.endAt!.difference(widget.o.startAt!).inMinutes
      : 60;
  bool _series = false;

  bool get _canSeries => widget.o.repeats && widget.o.timed && !widget.fromInbox;

  @override
  Widget build(BuildContext context) {
    final o = widget.o;
    return AlertDialog(
      title: Text(widget.fromInbox ? 'เลือกวันแทน · ${o.title}' : 'เลื่อน "${o.title}"'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_canSeries) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('เฉพาะครั้งนี้')),
                  ButtonSegment(value: true, label: Text('ทั้งแถว')),
                ],
                selected: {_series},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _series = s.first),
              ),
              const SizedBox(height: 6),
              Text(
                _series
                    ? 'เปลี่ยนเวลาของงานซ้ำนี้ ตั้งแต่ ${thaiShortDate(o.day)} เป็นต้นไป'
                    : 'ย้ายแค่ครั้งนี้ไปวัน/เวลาใหม่',
                style: TextStyle(fontSize: 13, color: context.noir.muted),
              ),
            ],
            if (!_series)
              PickerTile(
                icon: Icons.event,
                label: 'วันแทน',
                value: thaiShortDate(_day),
                onTap: () async {
                  final d = await pickDay(context, _day);
                  if (d != null) setState(() => _day = d);
                },
              ),
            if (o.timed) ...[
              PickerTile(
                icon: Icons.schedule,
                label: 'เวลาเริ่ม',
                value: fmtMinute(_start),
                onTap: () async {
                  final m = await pickMinute(context, _start, title: 'เวลาเริ่มกิจกรรม');
                  if (m != null) setState(() => _start = m);
                },
              ),
              PickerTile(
                icon: Icons.flag_outlined,
                label: 'เวลาจบ',
                value: fmtMinute(_start + _duration),
                onTap: () async {
                  final m = await pickMinute(context, (_start + _duration) % (24 * 60), title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(_start)})');
                  if (m != null) setState(() => _duration = durationBetween(_start, m));
                },
              ),
              Text('รวม ${durationLabel(_start, _duration)}',
                  style: TextStyle(color: context.noir.muted, fontSize: 13)),
            ],
          ],
        ),
      ),
      actions: [
        if (!widget.fromInbox && !_series)
          TextButton(
            onPressed: () =>
                Navigator.pop(context, const RescheduleResult.toInbox()),
            child: const Text('ยังไม่รู้วัน → Inbox'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RescheduleResult(
              series: _series,
              day: _series ? null : _day,
              startMinute: o.timed ? _start : null,
              durationMin: o.timed ? _duration : null,
            ),
          ),
          child: const Text('เลื่อน'),
        ),
      ],
    );
  }
}

// ---------- กล่องเวลาทับ ----------

enum OverlapChoice { pickAgain, allow, moveOthersToInbox }

Future<OverlapChoice?> askOverlap(BuildContext context, List<Occurrence> clashes) {
  final names = clashes
      .map((o) => '• ${o.title} (${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)})')
      .join('\n');
  return showDialog<OverlapChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('เวลาทับกับงานอื่น'),
      content: Text('ช่วงเวลานี้ทับกับ:\n$names\n\nจะทำยังไง?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, OverlapChoice.moveOthersToInbox),
          child: const Text('ย้ายงานที่ทับเข้า Inbox'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, OverlapChoice.allow),
          child: const Text('ยอมทับ'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, OverlapChoice.pickAgain),
          child: const Text('เลือกเวลาอื่น'),
        ),
      ],
    ),
  );
}

// ---------- กล่อง Life Base (เวลานอน / ตื่น) ----------

Future<List<LifeBaseDay>?> showLifeBaseDialog(
        BuildContext context, List<LifeBaseDay> current) =>
    showDialog<List<LifeBaseDay>>(
      context: context,
      builder: (_) => _LifeBaseDialog(current: current),
    );

class _LifeBaseDialog extends StatefulWidget {
  const _LifeBaseDialog({required this.current});

  final List<LifeBaseDay> current;

  @override
  State<_LifeBaseDialog> createState() => _LifeBaseDialogState();
}

class _LifeBaseDialogState extends State<_LifeBaseDialog> {
  late List<LifeBaseDay> _days = List.of(widget.current);

  Future<void> _edit(int i, {required bool bed}) async {
    final d = _days[i];
    final m = await pickMinute(context, bed ? d.bedMinute : d.wakeMinute,
        title: bed ? 'เวลาเข้านอน' : 'เวลาตื่นนอน');
    if (m == null) return;
    setState(() {
      _days[i] = bed ? d.copyWith(bedMinute: m) : d.copyWith(wakeMinute: m);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return AlertDialog(
      title: const Text('เวลานอน / ตื่น (Life Base)'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 7; i++)
                Row(
                  children: [
                    SizedBox(width: 72, child: Text(thaiWeekdayLong[i])),
                    TextButton(
                      onPressed: () => _edit(i, bed: false),
                      child: Text('ตื่น ${fmtMinute(_days[i].wakeMinute)}'),
                    ),
                    TextButton(
                      onPressed: () => _edit(i, bed: true),
                      child: Text('นอน ${fmtMinute(_days[i].bedMinute)}'),
                    ),
                    const Spacer(),
                    Text(
                      '${sleepHours(_days[i], _days[(i + 1) % 7]).toStringAsFixed(1)} ชม.',
                      style: TextStyle(color: c.muted, fontSize: 13),
                    ),
                  ],
                ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => setState(() {
                    final mon = _days[0];
                    _days = [
                      for (final d in _days)
                        d.copyWith(
                            bedMinute: mon.bedMinute, wakeMinute: mon.wakeMinute),
                    ];
                  }),
                  icon: const Icon(Icons.copy_all),
                  label: const Text('ใช้เวลาของวันจันทร์กับทุกวัน'),
                ),
              ),
              Text('ชั่วโมงนอน = นอนคืนนั้น → ตื่นเช้าวันถัดไป',
                  style: TextStyle(color: c.muted, fontSize: 12)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _days),
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}


/// ถามเวลาเลิกจริงหลังเรียน (ปุ่มลัด ±15/30 นาที หรือเลือกเวลาเอง) · null = ข้าม
Future<DateTime?> askActualEnd(BuildContext context, Occurrence o) {
  final planned = o.endAt!;
  Widget quick(BuildContext ctx, String label, int diff) => ActionChip(
        label: Text(label),
        onPressed: () => Navigator.pop(ctx, planned.add(Duration(minutes: diff))),
      );
  return showDialog<DateTime>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('เลิกจริงกี่โมง? · ${o.title}'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ตามตารางเลิก ${fmtTime(planned)} · เก็บไว้ทำสถิติว่าวิชานี้เลิกเร็วหรือช้า',
                style: TextStyle(color: ctx.noir.muted, fontSize: 13)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                quick(ctx, 'ก่อน 30 นาที', -30),
                quick(ctx, 'ก่อน 15 นาที', -15),
                quick(ctx, 'ตรงเวลา', 0),
                quick(ctx, 'ช้า 15 นาที', 15),
                quick(ctx, 'ช้า 30 นาที', 30),
                ActionChip(
                  avatar: const Icon(Icons.schedule, size: 18),
                  label: const Text('เลือกเวลาเอง'),
                  onPressed: () async {
                    final m = await pickMinute(ctx, minuteOf(planned), title: 'เวลาเลิกจริง');
                    if (m == null || !ctx.mounted) return;
                    Navigator.pop(ctx, atMinute(o.day, m));
                  },
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ข้าม')),
      ],
    ),
  );
}
