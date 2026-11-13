import 'package:flutter/material.dart';

import '../study/subject_colors.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'calendar_models.dart';
import 'lock_flow.dart' show showLockBadge;

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

/// สัญลักษณ์ของวันสำคัญ: วันสอบ · กำหนดส่งงาน/การบ้าน (งาน "ส่ง: …" จากบันทึกคาบ)
enum DayMark { exam, homework }

DayMark? markOf(Occurrence o) {
  if (!o.active) return null;
  if (o.kind == ActivityKind.exam) return DayMark.exam;
  if (o.title.startsWith('ส่ง:')) return DayMark.homework;
  return null;
}

/// ชื่องานพร้อมสัญลักษณ์นำหน้า (📝 สอบ · ⭐ ส่งงาน) ให้เห็นแต่ไกล
String markedTitle(Occurrence o) {
  final t = switch (markOf(o)) {
    DayMark.exam => '📝 ${o.title}',
    DayMark.homework => '⭐ ${o.title}',
    null => o.title,
  };
  return t;
}

/// ไอคอนกุญแจเล็กหน้าชื่องาน: มีคำมั่น หรือเริ่มแล้ว (แก้ต้องยืนยัน)
Widget? lockBadge(Occurrence o, Color color, {double size = 14}) => showLockBadge(o)
    ? Padding(
        padding: const EdgeInsets.only(right: 4),
        child: Icon(Icons.lock, size: size, color: color, semanticLabel: 'ล็อกอยู่'),
      )
    : null;

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
}) {
  Widget body(bool sheet) => _ActivityDialog(
        day: day,
        categories: categories,
        presets: presets,
        initial: initial,
        editing: editing,
        onSavePreset: onSavePreset,
        onDeletePreset: onDeletePreset,
        sheet: sheet,
      );
  // มือถือ = แผ่นจากด้านล่าง · คอม = กล่องกลางจอ
  return MediaQuery.sizeOf(context).width < 600
      ? showModalBottomSheet<NewActivity>(
          context: context,
          isScrollControlled: true,
          useSafeArea: true,
          showDragHandle: true,
          builder: (_) => body(true),
        )
      : showDialog<NewActivity>(context: context, builder: (_) => Dialog(child: body(false)));
}

class _ActivityDialog extends StatefulWidget {
  const _ActivityDialog({
    required this.day,
    required this.categories,
    required this.presets,
    required this.initial,
    required this.editing,
    required this.onSavePreset,
    required this.onDeletePreset,
    this.sheet = false,
  });

  final bool sheet;
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
    final name = await showMiniForm<String>(
      context,
      (ctx) => MiniForm(
        title: 'บันทึกเป็น Preset · เก็บหมวด ความสำคัญ เวลา ไว้ใช้ซ้ำ',
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, controller.text),
        children: [
          MiniBigField(controller: controller, hint: 'ชื่อ Preset เช่น Stream, ติวเข้ม', onSubmitted: (v) => Navigator.pop(ctx, v)),
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

  // ---------- แผ่นตัวเลือกย่อย (แตะแถวแล้วเปิด) ----------

  /// เปิดแผ่นจากด้านล่าง · [build] ได้ฟังก์ชัน set ที่อัปเดตทั้งแผ่นและฟอร์ม
  Future<void> _sheet(String title, Widget Function(BuildContext ctx, void Function(VoidCallback) set) build) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
          void set(VoidCallback f) {
            setState(f);
            setLocal(() {});
          }

          final c = ctx.noir;
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text))),
                TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('เสร็จ')),
              ]),
              const SizedBox(height: 8),
              Flexible(child: SingleChildScrollView(child: build(ctx, set))),
            ]),
          );
        }),
      );

  Future<void> _editTime() => _sheet('เวลา', (ctx, set) {
        final c = ctx.noir;
        Widget box(String label, int m, VoidCallback onTap) => Expanded(
              child: Material(
                color: c.surface2,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: _timed ? onTap : null,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(label, style: TextStyle(fontSize: 12, color: c.muted)),
                      Text(fmtMinute(m),
                          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: _timed ? c.text : c.muted)),
                    ]),
                  ),
                ),
              ),
            );
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            box('เริ่ม', _start, () async {
              final m = await pickMinute(ctx, _start, title: 'เวลาเริ่มกิจกรรม');
              if (m != null) set(() => _start = m);
            }),
            const SizedBox(width: 10),
            box('จบ', (_start + _duration) % (24 * 60), () async {
              final m = await pickMinute(ctx, (_start + _duration) % (24 * 60),
                  title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(_start)})');
              if (m != null) set(() => _duration = durationBetween(_start, m));
            }),
          ]),
          const SizedBox(height: 12),
          Text('ความยาว · ${durationLabel(_start, _duration)}', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 6),
          MiniSegments<int>(
            value: _duration,
            items: const [(30, '30 น.'), (60, '1 ชม.'), (90, '1.5'), (120, '2 ชม.'), (180, '3 ชม.')],
            onChanged: (v) => set(() {
              _timed = true;
              _duration = v;
            }),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: !_timed,
            onChanged: (v) => set(() => _timed = !v),
            title: const Text('ไม่ล็อกเวลา'),
            subtitle: const Text('แค่ต้องทำวันนั้น · ไม่ขึ้นในตารางเวลา'),
          ),
        ]);
      });

  Future<void> _editRepeat() => _sheet('ทำซ้ำ', (ctx, set) {
        final c = ctx.noir;
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MiniSegments<RepeatKind>(
            value: _repeat,
            items: const [
              (RepeatKind.none, 'ครั้งเดียว'),
              (RepeatKind.daily, 'ทุกวัน'),
              (RepeatKind.weekly, 'ทุกสัปดาห์'),
              (RepeatKind.dates, 'เลือกวันเอง'),
            ],
            onChanged: (kind) => set(() {
              _repeat = kind;
              if (_repeat == RepeatKind.weekly && _weekdays.isEmpty) _weekdays = {_day.weekday};
              if (_repeat == RepeatKind.dates && _dates.isEmpty) _dates = [ScheduledDate(_day)];
            }),
          ),
          const SizedBox(height: 12),
          if (_repeat == RepeatKind.weekly)
            Row(children: [
              for (var d = 1; d <= 7; d++)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Material(
                      color: _weekdays.contains(d) ? c.accent : c.surface2,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: () => set(() {
                          _weekdays = _weekdays.contains(d) ? ({..._weekdays}..remove(d)) : {..._weekdays, d};
                        }),
                        child: AspectRatio(
                          aspectRatio: 1,
                          child: Center(
                            child: Text(thaiWeekdayShort[d - 1],
                                style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: _weekdays.contains(d) ? c.onAccent : c.text)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ]),
          if (_repeat == RepeatKind.daily || _repeat == RepeatKind.weekly)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ถึงวันที่'),
              onTap: () async {
                final d = await pickDay(ctx, _endDate ?? _day.add(const Duration(days: 7)));
                if (d != null) set(() => _endDate = dayOnly(d));
              },
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(_endDate == null ? 'ไม่กำหนด' : thaiShortDate(_endDate!),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (_endDate != null)
                  IconButton(
                    tooltip: 'ไม่กำหนดวันสิ้นสุด',
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => set(() => _endDate = null),
                  ),
              ]),
            ),
          if (_repeat == RepeatKind.dates) ...[
            Text(_timed ? 'แตะ 🕑 = ตั้งเวลาเฉพาะวันนั้น (ไม่ตั้ง = เวลาหลัก)' : 'เลือกได้หลายวัน',
                style: TextStyle(color: c.muted, fontSize: 12)),
            for (var i = 0; i < _dates.length; i++)
              Row(children: [
                Expanded(child: Text(thaiShortDate(_dates[i].day))),
                if (_timed)
                  TextButton.icon(
                    onPressed: () async {
                      await _editDateTime(i);
                      set(() {});
                    },
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text(_dates[i].customTime
                        ? rangeText(_dates[i].startMinute!, _dates[i].durationMin ?? _duration)
                        : 'เวลาหลัก'),
                  ),
                IconButton(
                  tooltip: 'เอาวันนี้ออก',
                  icon: const Icon(Icons.remove_circle_outline, size: 20),
                  onPressed: () => set(() => _dates = [..._dates]..removeAt(i)),
                ),
              ]),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () async {
                  await _addDate();
                  set(() {});
                },
                icon: const Icon(Icons.add),
                label: const Text('เพิ่มวัน'),
              ),
            ),
          ],
        ]);
      });

  Future<void> _editCategory() => _sheet('หมวด', (ctx, set) {
        return Column(children: [
          for (final cat in widget.categories)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 7, backgroundColor: categoryColors(ctx.noir, cat.colorKey).$1),
              title: Text(cat.name),
              trailing: cat.id == _categoryId ? const Icon(Icons.check) : null,
              onTap: () {
                set(() => _categoryId = cat.id);
                Navigator.pop(ctx);
              },
            ),
        ]);
      });

  Future<void> _editImportance() => _sheet('ความสำคัญ', (ctx, set) {
        return Column(children: [
          for (final (v, label, hint) in const [
            (3, 'สำคัญ', 'ห้ามพลาด · ไม่แนะนำให้จองทับ'),
            (2, 'กลาง', 'ค่าเริ่มต้น'),
            (1, 'น้อย', 'ย้ายได้ · หน้าจองติวทับได้ (⇄ แทนได้)'),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: _ImportanceDots(v),
              title: Text(label),
              subtitle: Text(hint),
              trailing: v == _importance ? const Icon(Icons.check) : null,
              onTap: () {
                set(() => _importance = v);
                Navigator.pop(ctx);
              },
            ),
        ]);
      });

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final problem = _problem;
    final cat = widget.categories.where((x) => x.id == _categoryId).firstOrNull;
    void submit() {
      if (_problem == null) Navigator.pop(context, _draft);
    }

    // 1 แถว = ไอคอน · ชื่อ · ค่าปัจจุบัน (ขวา) · แตะ = เปิดตัวเลือก
    Widget row(IconData icon, String label, Widget value, VoidCallback onTap, {Key? key}) => InkWell(
          key: key,
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
            decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              Icon(icon, size: 20, color: c.muted),
              const SizedBox(width: 12),
              Text(label, style: TextStyle(color: c.muted)),
              const SizedBox(width: 12),
              Expanded(child: Align(alignment: Alignment.centerRight, child: value)),
              Icon(Icons.chevron_right, size: 20, color: c.muted),
            ]),
          ),
        );
    Text strong(String t) => Text(t,
        maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: c.text));

    final repeatText = switch (_repeat) {
      RepeatKind.none => 'ครั้งเดียว',
      RepeatKind.daily => _endDate == null ? 'ทุกวัน' : 'ทุกวัน ถึง ${thaiShortDate(_endDate!)}',
      RepeatKind.weekly =>
        'ทุก ${([..._weekdays]..sort()).map((d) => thaiWeekdayShort[d - 1]).join(' ')}${_endDate == null ? '' : ' ถึง ${thaiShortDate(_endDate!)}'}',
      RepeatKind.dates => 'เลือกวันเอง · ${_dates.length} วัน',
    };

    final form = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(
            '${widget.editing ? 'แก้ไขงาน' : 'เพิ่มงาน'} · ${thaiShortDate(_day)}',
            style: TextStyle(fontSize: 13, color: c.muted),
          ),
        ),
        IconButton(
          tooltip: 'ปิด',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 20),
        ),
      ]),
      // ชื่องานตัวใหญ่ ไม่มีกรอบ · Enter = เพิ่มเลย (ค่าอื่นใช้ค่าเริ่มต้น)
      TextField(
        key: const Key('activity-name'),
        controller: _name,
        autofocus: !widget.editing,
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.text),
        textInputAction: TextInputAction.done,
        decoration: InputDecoration(
          hintText: _presetId == null ? 'ชื่องาน เช่น อ่านสไลด์บท 3' : 'ชื่องาน เช่น RE4, Minecraft',
          border: InputBorder.none,
          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.line)),
          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.accent)),
        ),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => submit(),
      ),
      // Preset = ป้ายเล็กแถวเดียว · แตะ = เติมค่าให้ · กดค้าง / คลิกขวา = ลบ
      if (_presets.isNotEmpty || widget.onSavePreset != null)
        SizedBox(
          height: 44,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            for (final p in _presets)
              Padding(
                padding: const EdgeInsets.only(right: 6, top: 6),
                child: GestureDetector(
                  onLongPress: widget.onDeletePreset == null
                      ? null
                      : () {
                          _presetId = p.id;
                          _deletePreset();
                        },
                  onSecondaryTap: widget.onDeletePreset == null
                      ? null
                      : () {
                          _presetId = p.id;
                          _deletePreset();
                        },
                  child: ChoiceChip(
                    visualDensity: VisualDensity.compact,
                    showCheckmark: false,
                    avatar: const Icon(Icons.bolt, size: 16),
                    label: Text(p.name),
                    selected: _presetId == p.id,
                    onSelected: (on) => _applyPreset(on ? p.id : null),
                  ),
                ),
              ),
            if (widget.onSavePreset != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.bookmark_add_outlined, size: 16),
                  label: const Text('บันทึก preset'),
                  onPressed: _savePreset,
                ),
              ),
          ]),
        ),
      const SizedBox(height: 4),
      row(Icons.schedule, 'เวลา',
          _timed ? strong('${rangeText(_start, _duration)} · ${durationText(_duration)}') : strong('ไม่ล็อกเวลา'),
          _editTime,
          key: const Key('row-time')),
      if (_repeat != RepeatKind.dates)
        row(Icons.event, _repeat == RepeatKind.none ? 'วันที่' : 'เริ่มวันที่', strong(thaiShortDate(_day)), () async {
          final d = await pickDay(context, _day);
          if (d != null) setState(() => _day = dayOnly(d));
        }),
      row(Icons.repeat, 'ทำซ้ำ', strong(repeatText), _editRepeat, key: const Key('row-repeat')),
      row(
        Icons.label_outline,
        'หมวด',
        Row(mainAxisSize: MainAxisSize.min, children: [
          if (cat != null) CircleAvatar(radius: 5, backgroundColor: categoryColors(c, cat.colorKey).$1),
          const SizedBox(width: 6),
          Flexible(child: strong(cat?.name ?? 'ไม่มี')),
        ]),
        _editCategory,
      ),
      row(
        Icons.priority_high,
        'ความสำคัญ',
        Row(mainAxisSize: MainAxisSize.min, children: [
          _ImportanceDots(_importance),
          const SizedBox(width: 6),
          strong(const {3: 'สำคัญ', 2: 'กลาง', 1: 'น้อย'}[_importance]!),
        ]),
        _editImportance,
      ),
      if (problem != null && _name.text.trim().isNotEmpty) ...[
        const SizedBox(height: 8),
        Text(problem, style: TextStyle(color: c.bad, fontSize: 12)),
      ],
      const SizedBox(height: 16),
      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: problem == null ? submit : null,
          child: Text(widget.editing ? 'บันทึก' : 'เพิ่มงาน'),
        ),
      ]),
    ]);

    return Padding(
      key: const Key('activity-form'),
      padding: EdgeInsets.fromLTRB(20, widget.sheet ? 0 : 16, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(child: form),
      ),
    );
  }
}

/// กล่องแก้เวลาเฉพาะครั้งนี้ → (เริ่ม, ระยะเวลา)
Future<(int, int)?> showOccurrenceTimeDialog(BuildContext context, Occurrence o) {
  var start = minuteOf(o.startAt!);
  var duration = o.endAt!.difference(o.startAt!).inMinutes;
  return showMiniForm<(int, int)>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => MiniForm(
        title: 'แก้เวลา "${o.title}" เฉพาะ ${thaiShortDate(o.day)}',
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, (start, duration)),
        children: [
          MiniRow(
            icon: Icons.schedule,
            label: 'เริ่ม',
            valueText: fmtMinute(start),
            onTap: () async {
              final m = await pickMinute(ctx, start, title: 'เวลาเริ่มกิจกรรม');
              if (m != null) setLocal(() => start = m);
            },
          ),
          MiniRow(
            icon: Icons.flag_outlined,
            label: 'จบ',
            valueText: '${fmtMinute(start + duration)} · ${durationLabel(start, duration)}',
            last: true,
            onTap: () async {
              final m = await pickMinute(ctx, (start + duration) % (24 * 60), title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(start)})');
              if (m != null) setLocal(() => duration = durationBetween(start, m));
            },
          ),
          const MiniLabel('วันอื่นของงานนี้ไม่เปลี่ยน'),
        ],
      ),
    ),
  );
}

// ---------- กล่องยกเลิก (ต้องมีเหตุผล) ----------

Future<String?> askCancelReason(BuildContext context, Occurrence o) {
  final controller = TextEditingController();
  return showMiniForm<String>(
    context,
    (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final text = controller.text.trim();
        return MiniForm(
          title: 'ยกเลิก "${o.title}" · ต้องมีเหตุผล (ดูสถิติย้อนหลัง)',
          primaryLabel: 'ยืนยันยกเลิก',
          secondaryLabel: 'ไม่ยกเลิก',
          onPrimary: text.isEmpty ? null : () => Navigator.pop(ctx, text),
          children: [
            MiniBigField(
              key: const Key('reason-field'),
              controller: controller,
              hint: 'เหตุผล',
              onChanged: (_) => setLocal(() {}),
            ),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final quick in ['ป่วย', 'งานด่วน', 'เหนื่อยเกินไป', 'ติดธุระ'])
                ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  label: Text(quick),
                  selected: text == quick,
                  onSelected: (_) => setLocal(() => controller.text = quick),
                ),
            ]),
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
    showMiniForm<RescheduleResult>(context, (_) => _RescheduleDialog(o: o, fromInbox: fromInbox));

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
    final c = context.noir;
    return MiniForm(
      title: widget.fromInbox ? 'เลือกวันแทน · ${o.title}' : 'เลื่อน "${o.title}"',
      primaryLabel: 'เลื่อน',
      onPrimary: () => Navigator.pop(
        context,
        RescheduleResult(
          series: _series,
          day: _series ? null : _day,
          startMinute: o.timed ? _start : null,
          durationMin: o.timed ? _duration : null,
        ),
      ),
      children: [
        if (_canSeries) ...[
          MiniSegments<bool>(
            value: _series,
            items: const [(false, 'เฉพาะครั้งนี้'), (true, 'ทั้งแถว')],
            onChanged: (v) => setState(() => _series = v),
          ),
          MiniLabel(_series
              ? 'เปลี่ยนเวลาของงานซ้ำนี้ ตั้งแต่ ${thaiShortDate(o.day)} เป็นต้นไป'
              : 'ย้ายแค่ครั้งนี้ไปวัน/เวลาใหม่'),
        ],
        if (!_series)
          MiniRow(
            icon: Icons.event,
            label: 'วันแทน',
            valueText: thaiShortDate(_day),
            last: !o.timed,
            onTap: () async {
              final d = await pickDay(context, _day);
              if (d != null) setState(() => _day = d);
            },
          ),
        if (o.timed) ...[
          MiniRow(
            icon: Icons.schedule,
            label: 'เริ่ม',
            valueText: fmtMinute(_start),
            onTap: () async {
              final m = await pickMinute(context, _start, title: 'เวลาเริ่มกิจกรรม');
              if (m != null) setState(() => _start = m);
            },
          ),
          MiniRow(
            icon: Icons.flag_outlined,
            label: 'จบ',
            valueText: '${fmtMinute(_start + _duration)} · ${durationLabel(_start, _duration)}',
            last: true,
            onTap: () async {
              final m = await pickMinute(context, (_start + _duration) % (24 * 60),
                  title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(_start)})');
              if (m != null) setState(() => _duration = durationBetween(_start, m));
            },
          ),
        ],
        if (!widget.fromInbox && !_series)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => Navigator.pop(context, const RescheduleResult.toInbox()),
              icon: Icon(Icons.inbox_outlined, size: 18, color: c.muted),
              label: const Text('ยังไม่รู้วัน → Updates'),
            ),
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
  return showMiniForm<OverlapChoice>(
    context,
    (ctx) => MiniForm(title: 'เวลาทับกับงานอื่น', children: [
      Text('ช่วงเวลานี้ทับกับ:\n$names', style: TextStyle(color: ctx.noir.text, height: 1.5)),
      const SizedBox(height: 8),
      MiniRow(label: 'เลือกเวลาอื่น', onTap: () => Navigator.pop(ctx, OverlapChoice.pickAgain)),
      MiniRow(label: 'ยอมทับ', onTap: () => Navigator.pop(ctx, OverlapChoice.allow)),
      MiniRow(
          label: 'ย้ายงานที่ทับไป Updates',
          last: true,
          onTap: () => Navigator.pop(ctx, OverlapChoice.moveOthersToInbox)),
    ]),
  );
}

// ---------- กล่อง Life Base (เวลานอน / ตื่น) ----------

Future<List<LifeBaseDay>?> showLifeBaseDialog(
        BuildContext context, List<LifeBaseDay> current) =>
    showMiniForm<List<LifeBaseDay>>(context, (_) => _LifeBaseDialog(current: current));

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
    return MiniForm(
      title: 'เวลานอน / ตื่น (Life Base) · นอนคืนนั้น → ตื่นเช้าวันถัดไป',
      menu: [
        miniMenu(
            'ใช้เวลาของวันจันทร์กับทุกวัน',
            () => setState(() {
                  final mon = _days[0];
                  _days = [for (final d in _days) d.copyWith(bedMinute: mon.bedMinute, wakeMinute: mon.wakeMinute)];
                })),
      ],
      primaryLabel: 'บันทึก',
      onPrimary: () => Navigator.pop(context, _days),
      children: [
        for (var i = 0; i < 7; i++)
          Container(
            decoration: BoxDecoration(border: i == 6 ? null : Border(bottom: BorderSide(color: c.line))),
            child: Row(children: [
              SizedBox(width: 64, child: Text(thaiWeekdayLong[i], style: TextStyle(color: c.muted))),
              TextButton(onPressed: () => _edit(i, bed: false), child: Text('ตื่น ${fmtMinute(_days[i].wakeMinute)}')),
              TextButton(onPressed: () => _edit(i, bed: true), child: Text('นอน ${fmtMinute(_days[i].bedMinute)}')),
              const Spacer(),
              Text('${sleepHours(_days[i], _days[(i + 1) % 7]).toStringAsFixed(1)} ชม.',
                  style: TextStyle(color: c.muted, fontSize: 13)),
            ]),
          ),
      ],
    );
  }
}


/// ถามเวลาเลิกจริงหลังเรียน (ปุ่มลัด ±15/30 นาที หรือเลือกเวลาเอง) · null = ข้าม
Future<DateTime?> askActualEnd(BuildContext context, Occurrence o) {
  final planned = o.endAt!;
  return showMiniForm<DateTime>(
    context,
    (ctx) => MiniForm(
      title: 'เลิกจริงกี่โมง? · ${o.title}',
      primaryLabel: 'ตรงเวลา ${fmtTime(planned)}',
      onPrimary: () => Navigator.pop(ctx, planned),
      secondaryLabel: 'ข้าม',
      children: [
        MiniLabel('ตามตารางเลิก ${fmtTime(planned)} · เก็บไว้ดูว่าวิชานี้เลิกเร็วหรือช้า'),
        MiniSegments<int>(
          value: 0,
          items: const [(-30, '−30 น.'), (-15, '−15'), (0, 'ตรง'), (15, '+15'), (30, '+30 น.')],
          onChanged: (d) => Navigator.pop(ctx, planned.add(Duration(minutes: d))),
        ),
        const SizedBox(height: 6),
        MiniRow(
          icon: Icons.schedule,
          label: 'เลือกเวลาเอง',
          last: true,
          onTap: () async {
            final m = await pickMinute(ctx, minuteOf(planned), title: 'เวลาเลิกจริง');
            if (m == null || !ctx.mounted) return;
            Navigator.pop(ctx, atMinute(o.day, m));
          },
        ),
      ],
    ),
  );
}

/// กรอบเส้นประมุมมน: ใช้กับ "รอบติว" ให้แยกจากคาบเรียน (พื้นทึบ) ได้ทันที
class DashedRoundedBorder extends ShapeBorder {
  const DashedRoundedBorder({required this.color, this.radius = 8, this.width = 1.5, this.dash = 5, this.gap = 3});
  final Color color;
  final double radius;
  final double width;
  final double dash;
  final double gap;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  RRect _rrect(Rect r) => RRect.fromRectAndRadius(r, Radius.circular(radius));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect.deflate(width)));

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => Path()..addRRect(_rrect(rect));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    final path = Path()..addRRect(_rrect(rect.deflate(width / 2)));
    for (final m in path.computeMetrics()) {
      for (var d = 0.0; d < m.length; d += dash + gap) {
        canvas.drawPath(m.extractPath(d, (d + dash).clamp(0, m.length)), paint);
      }
    }
  }

  @override
  ShapeBorder scale(double t) =>
      DashedRoundedBorder(color: color, radius: radius * t, width: width * t, dash: dash, gap: gap);
}

/// พื้น + กรอบของงาน 1 ครั้ง (ใช้ร่วมกันทุกมุมมอง)
/// คาบเรียน / งานทั่วไป = พื้นสีเต็ม · รอบติว = พื้นจาง + กรอบเส้นประสีวิชา · ทับเวลา = กรอบแดง
(Color, ShapeBorder) occurrenceLook(NoirColors c, Occurrence o, Color bg, Color fg,
    {bool clash = false, double radius = 8}) {
  if (clash) {
    return (
      o.kind == ActivityKind.tutor ? Color.alphaBlend(bg.withValues(alpha: 0.25), c.surface) : bg,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius), side: BorderSide(color: c.bad, width: 2)),
    );
  }
  if (o.kind == ActivityKind.tutor) {
    return (
      Color.alphaBlend(bg.withValues(alpha: 0.25), c.surface),
      DashedRoundedBorder(color: fg.withValues(alpha: 0.75), radius: radius),
    );
  }
  return (bg, RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)));
}


/// ส้มของความสำคัญระดับกลาง (อ่านออกทั้งธีมมืดและสว่าง)
const importanceOrange = Color(0xFFE8822E);

/// ความสำคัญเป็นจุด 3 ระดับ (เต็ม = สำคัญ)
class _ImportanceDots extends StatelessWidget {
  const _ImportanceDots(this.level);
  final int level;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    // สีตามระดับ: น้อย = เขียว · กลาง = ส้ม · สำคัญ = แดง (นัวร์เลือก)
    final on = switch (level) { >= 3 => c.bad, 2 => importanceOrange, _ => c.good };
    return Row(mainAxisSize: MainAxisSize.min, children: [
      for (var i = 1; i <= 3; i++)
        Container(
          width: 8,
          height: 8,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(shape: BoxShape.circle, color: i <= level ? on : c.line2),
        ),
    ]);
  }
}
