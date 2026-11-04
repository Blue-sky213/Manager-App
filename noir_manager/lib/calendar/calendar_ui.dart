import 'package:flutter/material.dart';

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

/// ตัวเลือกระยะเวลา (นาที)
const List<int> durationChoices = [15, 30, 45, 60, 90, 120, 180, 240];

String durationText(int min) =>
    min < 60 ? '$min นาที' : (min % 60 == 0 ? '${min ~/ 60} ชม.' : '${min / 60} ชม.');

/// เลือกวัน (ปฏิทิน Material)
Future<DateTime?> pickDay(BuildContext context, DateTime initial) =>
    showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 2),
    );

/// เลือกเวลาแบบ 24 ชม. → คืนเป็นนาทีนับจากเที่ยงคืน
Future<int?> pickMinute(BuildContext context, int initial) async {
  final t = await showTimePicker(
    context: context,
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

// ---------- กล่องเพิ่มงาน ----------

Future<NewActivity?> showAddActivityDialog(
  BuildContext context, {
  required DateTime day,
  required List<ActivityCategory> categories,
  NewActivity? initial,
}) =>
    showDialog<NewActivity>(
      context: context,
      builder: (_) =>
          _AddActivityDialog(day: day, categories: categories, initial: initial),
    );

class _AddActivityDialog extends StatefulWidget {
  const _AddActivityDialog({
    required this.day,
    required this.categories,
    required this.initial,
  });

  final DateTime day;
  final List<ActivityCategory> categories;
  final NewActivity? initial;

  @override
  State<_AddActivityDialog> createState() => _AddActivityDialogState();
}

class _AddActivityDialogState extends State<_AddActivityDialog> {
  late final _name = TextEditingController(text: widget.initial?.name ?? '');
  late int? _categoryId = widget.initial?.categoryId ??
      (widget.categories.isEmpty ? null : widget.categories.first.id);
  late int _importance = widget.initial?.importance ?? 2;
  late bool _timed = widget.initial?.timed ?? true;
  late DateTime _day = widget.initial?.day ?? dayOnly(widget.day);
  late int _start = widget.initial?.startMinute ?? 18 * 60;
  late int _duration = widget.initial?.durationMin ?? 60;
  late RepeatKind _repeat = widget.initial?.repeat ?? RepeatKind.none;
  late Set<int> _weekdays = {...?widget.initial?.weekdays};

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _valid =>
      _name.text.trim().isNotEmpty &&
      !(_repeat == RepeatKind.weekly && _weekdays.isEmpty);

  void _save() {
    if (!_valid) return;
    Navigator.pop(
      context,
      NewActivity(
        name: _name.text.trim(),
        categoryId: _categoryId,
        importance: _importance,
        timed: _timed,
        day: _day,
        startMinute: _timed ? _start : null,
        durationMin: _timed ? _duration : null,
        repeat: _repeat,
        weekdays: _repeat == RepeatKind.weekly ? _weekdays : const {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เพิ่มงาน'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                key: const Key('activity-name'),
                controller: _name,
                autofocus: true,
                decoration: const InputDecoration(
                    labelText: 'ชื่องาน', hintText: 'เช่น ออกกำลังกาย, ติว DataCOM'),
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
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ล็อกเวลา'),
                subtitle: Text(_timed
                    ? 'มีเวลาเริ่ม-จบ แสดงในตารางเวลา'
                    : 'แบบลิสต์: แค่ต้องทำวันนั้น ไม่กำหนดเวลา'),
                value: _timed,
                onChanged: (v) => setState(() => _timed = v),
              ),
              PickerTile(
                icon: Icons.event,
                label: _repeat == RepeatKind.none ? 'วันที่' : 'เริ่มวันที่',
                value: thaiShortDate(_day),
                onTap: () async {
                  final d = await pickDay(context, _day);
                  if (d != null) setState(() => _day = d);
                },
              ),
              if (_timed) ...[
                PickerTile(
                  icon: Icons.schedule,
                  label: 'เวลาเริ่ม',
                  value: fmtMinute(_start),
                  onTap: () async {
                    final m = await pickMinute(context, _start);
                    if (m != null) setState(() => _start = m);
                  },
                ),
                Row(
                  children: [
                    const Icon(Icons.timelapse),
                    const SizedBox(width: 16),
                    const Expanded(child: Text('ระยะเวลา')),
                    DropdownButton<int>(
                      value: _duration,
                      items: [
                        for (final d in {...durationChoices, _duration}.toList()..sort())
                          DropdownMenuItem(value: d, child: Text(durationText(d))),
                      ],
                      onChanged: (v) => setState(() => _duration = v ?? _duration),
                    ),
                  ],
                ),
                Text('${fmtMinute(_start)} – ${fmtMinute(_start + _duration)}',
                    style: TextStyle(color: context.noir.muted, fontSize: 13)),
              ],
              const SizedBox(height: 12),
              const Text('ทำซ้ำ'),
              const SizedBox(height: 6),
              SegmentedButton<RepeatKind>(
                segments: const [
                  ButtonSegment(value: RepeatKind.none, label: Text('ไม่ซ้ำ')),
                  ButtonSegment(value: RepeatKind.daily, label: Text('ทุกวัน')),
                  ButtonSegment(value: RepeatKind.weekly, label: Text('ทุกสัปดาห์')),
                ],
                selected: {_repeat},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() {
                  _repeat = s.first;
                  if (_repeat == RepeatKind.weekly && _weekdays.isEmpty) {
                    _weekdays = {_day.weekday};
                  }
                }),
              ),
              if (_repeat == RepeatKind.weekly) ...[
                const SizedBox(height: 8),
                Wrap(
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
          onPressed: _valid ? _save : null,
          child: const Text('เพิ่มงาน'),
        ),
      ],
    );
  }
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
                  final m = await pickMinute(context, _start);
                  if (m != null) setState(() => _start = m);
                },
              ),
              Row(
                children: [
                  const Icon(Icons.timelapse),
                  const SizedBox(width: 16),
                  const Expanded(child: Text('ระยะเวลา')),
                  DropdownButton<int>(
                    value: _duration,
                    items: [
                      for (final d in {...durationChoices, _duration}.toList()..sort())
                        DropdownMenuItem(value: d, child: Text(durationText(d))),
                    ],
                    onChanged: (v) => setState(() => _duration = v ?? _duration),
                  ),
                ],
              ),
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
    final m = await pickMinute(context, bed ? d.bedMinute : d.wakeMinute);
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
