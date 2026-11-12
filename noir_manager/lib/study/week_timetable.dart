import 'package:flutter/material.dart';

import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart';
import '../data/study_models.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'class_schedule_card.dart';
import 'credit_hours.dart';
import 'subject_colors.dart';
import 'timetable_sim.dart';

/// คาบเรียน 1 ช่องบนตาราง: วิชาเดียวกัน วันเดียวกัน เวลา/ประเภท/ห้อง/กลุ่มเดียวกัน
/// คาบที่ถูกแยกช่วงวันที่ (เช่น ก่อน/หลังกลางภาค) รวมเป็นช่องเดียว จะได้ไม่ซ้อนกันเอง
class WeekSlot {
  WeekSlot({required this.subject, required this.weekday, required this.start, required this.minutes, required this.info});

  final Subject subject;
  final int weekday; // 1 = จันทร์ … 7 = อาทิตย์
  final int start; // นาทีนับจากเที่ยงคืน
  final int minutes;
  final ClassInfo info;
  final List<Activity> activities = [];

  int get end => start + minutes;
}

/// ช่วงวันที่ของคาบทับกันไหม (endDate null = ไม่มีกำหนด)
bool _datesOverlap(Activity a, Activity b) {
  final aEnd = a.endDate ?? DateTime(9999), bEnd = b.endDate ?? DateTime(9999);
  return !a.startDate.isAfter(bEnd) && !b.startDate.isAfter(aEnd);
}

/// วันจันทร์ของสัปดาห์ที่มี [d]
DateTime mondayOf(DateTime d) => dayOnly(d).subtract(Duration(days: d.weekday - 1));

/// รวมคาบประจำของทุกวิชาเป็นช่องบนตาราง
/// [week] = วันจันทร์ของสัปดาห์ที่ดู → เอาเฉพาะคาบที่มีจริงในวันนั้น ๆ ของสัปดาห์นั้น
/// (คาบก่อน/หลังกลางภาคจึงไม่ถูกนับซ้อนกัน) · null = ทุกช่วงของเทอมซ้อนกัน
/// [onlyCurrent] (ใช้ตอน week = null) = ซ่อนคาบที่จบไปแล้วก่อน [today]
List<WeekSlot> buildWeekSlots(Map<Subject, List<Activity>> bySubject,
    {DateTime? today, bool onlyCurrent = true, DateTime? week}) {
  final day = dayOnly(today ?? DateTime.now());
  final slots = <String, WeekSlot>{};
  for (final MapEntry(key: subject, value: acts) in bySubject.entries) {
    for (final a in acts) {
      if (a.kind != ActivityKind.classSession || a.repeat != RepeatKind.weekly || !a.timed) continue;
      if (week == null && onlyCurrent && a.endDate != null && a.endDate!.isBefore(day)) continue;
      for (final wd in a.weekdays) {
        if (week != null) {
          final date = week.add(Duration(days: wd - 1));
          if (date.isBefore(dayOnly(a.startDate)) || (a.endDate != null && date.isAfter(dayOnly(a.endDate!)))) {
            continue;
          }
        }
        final i = a.classInfo;
        final key = '${subject.id}|$wd|${a.startMinute}|${a.durationMin}|${i.type}|${i.room}|${i.section}';
        (slots[key] ??= WeekSlot(
          subject: subject,
          weekday: wd,
          start: a.startMinute ?? 0,
          minutes: a.durationMin ?? 60,
          info: i,
        ))
            .activities
            .add(a);
      }
    }
  }
  return slots.values.toList()..sort((a, b) => a.weekday != b.weekday ? a.weekday - b.weekday : a.start - b.start);
}

/// ช่องที่ชนกัน: วันเดียวกัน เวลาซ้อน และช่วงวันที่ของเทอมทับกันจริง
Set<WeekSlot> findWeekClashes(List<WeekSlot> slots) {
  final out = <WeekSlot>{};
  for (var i = 0; i < slots.length; i++) {
    for (var j = i + 1; j < slots.length; j++) {
      final a = slots[i], b = slots[j];
      if (a.weekday != b.weekday || a.start >= b.end || b.start >= a.end) continue;
      if (a.activities.any((x) => b.activities.any((y) => _datesOverlap(x, y)))) out.addAll([a, b]);
    }
  }
  return out;
}

/// หน้า "ตารางเรียนทั้งสัปดาห์": คาบของทุกวิชาบนตารางเดียว · เพิ่มคาบ · ขอบแดงเมื่อชน · ตรวจหน่วยกิต
class WeekTimetablePage extends StatefulWidget {
  const WeekTimetablePage({super.key, this.onOpenSubject});

  /// แตะ "เปิดวิชา" ในคาบ → ไปหน้ารายวิชา
  final ValueChanged<Subject>? onOpenSubject;

  @override
  State<WeekTimetablePage> createState() => _WeekTimetablePageState();
}

class _WeekTimetablePageState extends State<WeekTimetablePage> with CalendarListener<WeekTimetablePage> {
  List<Subject> _subjects = [];
  Map<Subject, List<Activity>> _bySubject = {};
  bool _onlyCurrent = true;
  bool _loaded = false;

  /// สัปดาห์ที่ดู (วันจันทร์) · null = ทุกช่วงของเทอมซ้อนกัน
  DateTime? _week = mondayOf(DateTime.now());
  // ตรวจหน่วยกิตต้องนับทีละสัปดาห์เสมอ → โหมดทุกช่วงใช้สัปดาห์นี้แทน
  DateTime get _creditWeek => _week ?? mondayOf(DateTime.now());

  /// id ของคาบจำลองที่ยังอยู่ (ลบทั้งชุดได้)
  List<int> _simIds = [];

  @override
  Future<void> reload() async {
    final subjects = await StudyScope.of(context).subjects();
    final simText = await calendar!.getSetting(simIdsKey) ?? '';
    final simIds = [for (final t in simText.split(',')) ?int.tryParse(t)];
    final by = <Subject, List<Activity>>{};
    for (final s in subjects) {
      by[s] = await calendar!.activitiesForSubject(s.id);
    }
    if (!mounted) return;
    setState(() {
      _subjects = subjects;
      _bySubject = by;
      // คาบจำลองที่นัวร์ลบเองไปแล้ว ไม่ต้องนับ
      final alive = {for (final l in by.values) for (final a in l) a.id};
      _simIds = [for (final id in simIds) if (alive.contains(id)) id];
      _loaded = true;
    });
  }

  /// จำลองตารางเรียน 1 ภาคตามกฎ (คาบ ≤ 2 ชม. · วิชา ≤ 4 ชม./สัปดาห์ · ทฤษฎี/ปฏิบัติแยกคาบ)
  /// ไม่แตะคาบเดิม: ข้ามวิชาที่มีคาบแล้ว และวางไม่ให้ชนคาบเดิม
  Future<void> _simulate() async {
    final years = {for (final s in _subjects) if (s.planYear != null && s.planTerm != null) s.planYear!}.toList()..sort();
    if (years.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('ยังไม่มีวิชาที่จัดปี/ภาค · ใส่แผน 4 ปีก่อน (หน้าวิชา ⋮)')));
      return;
    }
    var year = years.first, term = 1;
    final pick = await showMiniForm<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => MiniForm(
          title: 'จำลองตารางเรียน (ทดสอบ)',
          primaryLabel: 'จำลอง',
          onPrimary: () => Navigator.pop(ctx, true),
          onSecondary: () => Navigator.pop(ctx, false),
          children: [
            const MiniLabel('คาบ ≤ 2 ชม. · ทฤษฎี/ปฏิบัติแยกคาบ · วิชา ≤ 4 ชม./สัปดาห์ · '
                'จ–ศ 08:00–18:00 · ไม่ชนคาบเดิม · ข้ามวิชาที่มีคาบแล้ว'),
            MiniSegments<int>(
              value: year,
              items: [for (final y in years) (y, 'ปี $y')],
              onChanged: (y) => setLocal(() => year = y),
            ),
            const SizedBox(height: 8),
            MiniSegments<int>(
              value: term,
              items: const [(1, 'ภาค 1'), (2, 'ภาค 2')],
              onChanged: (t) => setLocal(() => term = t),
            ),
          ],
        ),
      ),
    );
    if (pick != true || !mounted) return;

    final repo = calendar!;
    final hasClass = {
      for (final e in _bySubject.entries)
        if (e.value.any((a) => a.kind == ActivityKind.classSession)) e.key.id
    };
    final target = [for (final s in _subjects) if (s.planYear == year && s.planTerm == term) s];
    final todo = [for (final s in target) if (!hasClass.contains(s.id)) s];
    // ช่วงเทอม: เทอมในปฏิทินที่ครอบวันนี้ · ไม่มี → 16 สัปดาห์จากสัปดาห์นี้
    final today = dayOnly(DateTime.now());
    final termNow = (await repo.terms()).where((t) => !today.isBefore(t.start) && !today.isAfter(t.end)).firstOrNull;
    final from = termNow?.start ?? mondayOf(today);
    final to = termNow?.end ?? mondayOf(today).add(const Duration(days: 16 * 7 - 3));
    final busy = [
      for (final w in buildWeekSlots(_bySubject, week: mondayOf(today)))
        (weekday: w.weekday, start: w.start, end: w.end),
    ];
    final plan = planSimTimetable(todo, busy: busy);
    final cat = studyCategoryId(await repo.categories());
    final ids = [..._simIds];
    for (final s in plan.sessions) {
      ids.add(await repo.addActivity(simToActivity(s, categoryId: cat ?? 1, from: from, to: to)));
    }
    await repo.setSetting(simIdsKey, ids.join(','));
    if (!mounted) return;
    await reload(); // setting ไม่แจ้งเปลี่ยนเอง
    if (!mounted) return;
    setState(() => _week = mondayOf(today));
    final skippedHas = target.length - todo.length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('จำลอง ${plan.sessions.length} คาบ · ${todo.length - plan.skipped.length} วิชา'
          '${skippedHas > 0 ? ' · ข้าม $skippedHas วิชาที่มีคาบแล้ว' : ''}'
          '${plan.skipped.isNotEmpty ? ' · วางไม่ลง ${plan.skipped.length}' : ''}'),
    ));
  }

  /// ลบเฉพาะคาบที่จำลอง (จำ id ไว้) · คาบที่ใส่เองไม่ถูกแตะ
  Future<void> _clearSim() async {
    final ok = await confirmDelete(context, 'ตารางจำลอง ${_simIds.length} คาบ');
    if (!ok) return;
    final repo = calendar!;
    final existing = {for (final l in _bySubject.values) for (final a in l) a.id};
    for (final id in _simIds) {
      if (existing.contains(id)) await repo.deleteActivity(id);
    }
    await repo.setSetting(simIdsKey, '');
    await reload();
  }

  Future<void> _add() async {
    final subject = await _pickSubject();
    if (subject == null || !mounted) return;
    await addClassSlot(context, calendar!, subject);
  }

  /// เลือกวิชา: เรียงตามปี/เทอมในแผน · วิชาที่มีคาบอยู่แล้วขึ้นก่อน
  Future<Subject?> _pickSubject() {
    final hasSlots = {for (final e in _bySubject.entries) if (e.value.any((a) => a.kind == ActivityKind.classSession)) e.key.id};
    int order(Subject s) => (hasSlots.contains(s.id) ? 0 : 1000) + (s.planYear ?? 9) * 10 + (s.planTerm ?? 9);
    final list = [..._subjects]..sort((a, b) => order(a).compareTo(order(b)));
    return showMiniForm<Subject>(
      context,
      (ctx) => MiniForm(title: 'เพิ่มคาบให้วิชาไหน', children: [
        for (final (i, s) in list.indexed)
          MiniRow(
            value: Text(
              [
                if (s.code != null) s.code!,
                if (s.planYear != null) 'ปี ${s.planYear} · ${s.planTerm == 3 ? 'ฤดูร้อน' : 'ภาค ${s.planTerm}'}',
                if (hasSlots.contains(s.id)) 'มีคาบแล้ว',
              ].join(' · '),
              style: TextStyle(fontSize: 12, color: ctx.noir.muted),
            ),
            label: s.name,
            last: i == list.length - 1,
            trailing: CircleAvatar(radius: 6, backgroundColor: subjectColorOf(s)),
            onTap: () => Navigator.pop(ctx, s),
          ),
      ]),
    );
  }

  /// คลิกซ้าย = เปิดวิชา (กลับมาด้วยปุ่ม "กลับตารางเรียน" / เมาส์ปุ่ม 4)
  void _openSlot(WeekSlot slot) => widget.onOpenSubject?.call(slot.subject);

  /// คลิกขวา / กดค้าง = เมนูตรงตำแหน่งเมาส์
  Future<void> _slotMenu(WeekSlot slot, Offset at) async {
    final action = await showContextMenuAt<String>(context, at, [
      if (widget.onOpenSubject != null) ctxItem('open', Icons.open_in_new, 'เปิดวิชา (แก้คาบ ประเภท ห้อง)'),
      ctxItem('delete', Icons.delete_outline, 'ลบคาบนี้', danger: true),
    ]);
    if (!mounted) return;
    switch (action) {
      case 'open':
        widget.onOpenSubject!(slot.subject);
      case 'delete':
        // คาบหลายวันในรายการเดียว → ลบทั้งรายการ (บอกให้รู้ก่อน)
        final multi = slot.activities.any((a) => a.weekdays.length > 1);
        final ok = await confirmDelete(
            context,
            '${slot.subject.name} ${thaiWeekdayShort[slot.weekday - 1]} ${fmtMinute(slot.start)}'
            '${multi ? ' (รวมวันอื่นที่ตั้งไว้ด้วยกัน)' : ''}');
        if (!ok) return;
        for (final a in slot.activities) {
          await calendar!.deleteActivity(a.id);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final slots = buildWeekSlots(_bySubject, onlyCurrent: _onlyCurrent, week: _week);
    final clashes = findWeekClashes(slots);
    final creditSlots = _week == null ? buildWeekSlots(_bySubject, week: _creditWeek) : slots;
    final thisWeek = mondayOf(DateTime.now());
    String range(DateTime m) => '${thaiShortDate(m)} – ${thaiShortDate(m.add(const Duration(days: 6)))}';
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        title: const Text('ตารางเรียนทั้งสัปดาห์'),
        actions: [
          FilledButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('เพิ่มคาบ')),
          PopupMenuButton<String>(
            tooltip: 'ตัวเลือก',
            onSelected: (v) => v == 'sim' ? _simulate() : _clearSim(),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'sim', child: Text('จำลองตารางเรียน (ทดสอบ)')),
              PopupMenuItem(
                value: 'clear',
                enabled: _simIds.isNotEmpty,
                child: Text('ลบตารางจำลอง (${_simIds.length} คาบ)'),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton(
                      tooltip: 'สัปดาห์ก่อน',
                      onPressed: () => setState(() => _week = (_week ?? thisWeek).subtract(const Duration(days: 7))),
                      icon: const Icon(Icons.chevron_left),
                    ),
                    Text(_week == null ? 'ทุกช่วงของเทอม (ซ้อนกัน)' : 'สัปดาห์ ${range(_week!)}',
                        style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                    IconButton(
                      tooltip: 'สัปดาห์ถัดไป',
                      onPressed: () => setState(() => _week = (_week ?? thisWeek).add(const Duration(days: 7))),
                      icon: const Icon(Icons.chevron_right),
                    ),
                    if (_week != thisWeek)
                      TextButton(onPressed: () => setState(() => _week = thisWeek), child: const Text('สัปดาห์นี้')),
                    ChoiceChip(
                      label: const Text('ทุกช่วงของเทอม'),
                      selected: _week == null,
                      onSelected: (on) => setState(() => _week = on ? null : thisWeek),
                    ),
                  ],
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('${slots.length} คาบ · ${slots.map((s) => s.subject.id).toSet().length} วิชา',
                        style: TextStyle(color: c.muted)),
                    if (clashes.isNotEmpty)
                      Text('⚠ ชนกัน ${clashes.length} คาบ (ขอบแดง) · ยังใช้ได้ แค่เตือน',
                          style: TextStyle(color: c.bad, fontWeight: FontWeight.w600)),
                    if (_week == null)
                      FilterChip(
                        label: const Text('แสดงคาบที่จบเทอมแล้ว'),
                        selected: !_onlyCurrent,
                        onSelected: (v) => setState(() => _onlyCurrent = !v),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                if (slots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 32),
                    child: Text(
                        _week != null && _bySubject.values.any((l) => l.any((a) => a.kind == ActivityKind.classSession))
                            ? 'สัปดาห์นี้ไม่มีคาบเรียน (ปิดเทอม / ช่วงสอบ?) · กด ‹ › ดูสัปดาห์อื่น'
                            : 'ยังไม่มีคาบเรียน · กด "เพิ่มคาบ" แล้วเลือกวิชา',
                        textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
                  )
                else
                  WeekGrid(slots: slots, clashes: clashes, onTap: _openSlot, onContextMenu: _slotMenu),
                const SizedBox(height: 20),
                _CreditTable(slots: creditSlots, weekText: range(_creditWeek)),
              ],
            ),
    );
  }
}

/// ตารางแบบมหาลัย: แถว = วัน · คอลัมน์ = ชั่วโมง · คาบชนกันแยกเป็นแถวย่อยในวันเดียวกัน
class WeekGrid extends StatelessWidget {
  const WeekGrid({super.key, required this.slots, required this.clashes, required this.onTap, this.onContextMenu});

  final List<WeekSlot> slots;
  final Set<WeekSlot> clashes;
  final ValueChanged<WeekSlot> onTap;
  final void Function(WeekSlot slot, Offset at)? onContextMenu;

  static const double _dayCol = 56;
  static const double _laneH = 64;
  static const double _headH = 28;
  static const double _minHourW = 72;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    // จันทร์–ศุกร์เสมอ · เสาร์/อาทิตย์เมื่อมีคาบ
    final days = {1, 2, 3, 4, 5, ...slots.map((s) => s.weekday)}.toList()..sort();
    var h0 = 8, h1 = 18;
    for (final s in slots) {
      if (s.start ~/ 60 < h0) h0 = s.start ~/ 60;
      if ((s.end + 59) ~/ 60 > h1) h1 = (s.end + 59) ~/ 60;
    }
    if (h1 > 24) h1 = 24;

    // แต่ละวัน: วางคาบลงแถวย่อยแถวแรกที่ว่าง (คาบชนกันจึงไม่ทับกันบนจอ)
    final lane = <WeekSlot, int>{};
    final lanesOf = <int, int>{};
    for (final d in days) {
      final ends = <int>[];
      for (final s in slots.where((s) => s.weekday == d)) {
        var i = ends.indexWhere((e) => e <= s.start);
        if (i < 0) {
          ends.add(s.end);
          i = ends.length - 1;
        } else {
          ends[i] = s.end;
        }
        lane[s] = i;
      }
      lanesOf[d] = ends.isEmpty ? 1 : ends.length;
    }

    return LayoutBuilder(builder: (context, size) {
      final hours = h1 - h0;
      final hourW = ((size.maxWidth - _dayCol) / hours).clamp(_minHourW, 200.0);
      final width = _dayCol + hourW * hours;
      double x(int minute) => _dayCol + (minute - h0 * 60) / 60 * hourW;

      final rowTop = <int, double>{};
      var y = _headH;
      for (final d in days) {
        rowTop[d] = y;
        y += lanesOf[d]! * _laneH;
      }
      final height = y;

      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: c.surface,
            border: Border.all(color: c.line),
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              // หัวชั่วโมง + เส้นแนวตั้ง
              for (var h = h0; h < h1; h++) ...[
                Positioned(
                  left: x(h * 60),
                  top: 0,
                  width: hourW,
                  height: _headH,
                  child: Center(
                    child: Text('${h.toString().padLeft(2, '0')}:00',
                        style: TextStyle(fontSize: 11, color: c.muted)),
                  ),
                ),
                Positioned(left: x(h * 60), top: _headH, bottom: 0, child: Container(width: 1, color: c.line)),
              ],
              // แถววัน
              for (final d in days) ...[
                Positioned(left: 0, right: 0, top: rowTop[d], child: Container(height: 1, color: c.line)),
                Positioned(
                  left: 0,
                  top: rowTop[d],
                  width: _dayCol,
                  height: lanesOf[d]! * _laneH,
                  child: Center(
                    child: Text(thaiWeekdayShort[d - 1],
                        style: TextStyle(fontWeight: FontWeight.w600, color: c.muted)),
                  ),
                ),
              ],
              // คาบ
              for (final s in slots)
                Positioned(
                  left: x(s.start) + 2,
                  top: rowTop[s.weekday]! + lane[s]! * _laneH + 3,
                  width: s.minutes / 60 * hourW - 4,
                  height: _laneH - 6,
                  child: _SlotBlock(
                    slot: s,
                    clash: clashes.contains(s),
                    onTap: () => onTap(s),
                    onContextMenu: onContextMenu == null ? null : (at) => onContextMenu!(s, at),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}

class _SlotBlock extends StatelessWidget {
  const _SlotBlock({required this.slot, required this.clash, required this.onTap, this.onContextMenu});

  final WeekSlot slot;
  final bool clash;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onContextMenu;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final color = subjectColorOf(slot.subject);
    final i = slot.info;
    final type = switch (i.type) { ClassType.theory => 'S', ClassType.lab => 'L', null => '' };
    final detail = [
      if (type.isNotEmpty) type,
      if (i.room != null) i.room!,
      if (i.section != null) i.section!,
      '${fmtMinute(slot.start)}–${fmtMinute(slot.end)}',
    ].join(' · ');
    var pressAt = Offset.zero;
    return Material(
        color: Color.alphaBlend(color.withValues(alpha: 0.16), c.surface),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: clash ? c.bad : color.withValues(alpha: 0.6), width: clash ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onSecondaryTapUp: onContextMenu == null ? null : (d) => onContextMenu!(d.globalPosition),
          // จอสัมผัส: กดค้าง = คลิกขวา
          onTapDown: (d) => pressAt = d.globalPosition,
          onLongPress: onContextMenu == null ? null : () => onContextMenu!(pressAt),
          child: Row(
            children: [
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(slot.subject.code ?? slot.subject.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: c.text)),
                      Text(slot.subject.code == null ? detail : slot.subject.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: c.text)),
                      if (slot.subject.code != null)
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 10.5, color: c.muted)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
    );
  }
}

/// นาทีต่อสัปดาห์ของ [subject] จากช่องบนตาราง 1 สัปดาห์ (ช่อง = 1 วัน จึงบวกตรง ๆ ได้)
WeeklyClassMinutes weekMinutes(Subject subject, List<WeekSlot> week) {
  var theory = 0, lab = 0, unknown = 0;
  for (final s in week.where((s) => s.subject == subject)) {
    switch (s.info.type) {
      case ClassType.theory:
        theory += s.minutes;
      case ClassType.lab:
        lab += s.minutes;
      case null:
        unknown += s.minutes;
    }
  }
  return WeeklyClassMinutes(theory: theory, lab: lab, unknown: unknown);
}

/// ตรวจหน่วยกิตจากคาบ 1 สัปดาห์ · หน่วยกิตอ่านไม่ได้ → null
CreditCheck? weekCreditCheck(Subject subject, List<WeekSlot> week) {
  final h = parseCreditHours(subject.credits);
  if (h == null) return null;
  final w = weekMinutes(subject, week);
  return CreditCheck(
    hours: h,
    theory: HourCheck(w.theory, h.theory * 60),
    lab: HourCheck(w.lab, h.lab * 60),
    unknown: w.unknown,
  );
}

/// ตรวจตามหลักหน่วยกิต ทุกวิชาที่มีคาบในตาราง
class _CreditTable extends StatelessWidget {
  const _CreditTable({required this.slots, required this.weekText});

  /// คาบของ 1 สัปดาห์ (นับซ้อนหลายช่วงเทอมไม่ได้ ชั่วโมงจะเกินจริง)
  final List<WeekSlot> slots;
  final String weekText;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final shown = <Subject>{for (final s in slots) s.subject}.toList()
      ..sort((a, b) => (a.code ?? a.name).compareTo(b.code ?? b.name));
    if (shown.isEmpty) return const SizedBox.shrink();

    Widget cell(HourCheck? h, int fallback) {
      if (h == null) return Text('${hoursText(fallback)} ชม.', style: TextStyle(color: c.muted));
      final (text, color) = switch (h.status) {
        HourStatus.ok => ('${hoursText(h.have)}/${hoursText(h.need)} ✓', c.good),
        HourStatus.short => ('${hoursText(h.have)}/${hoursText(h.need)} ขาด ${hoursText(h.need - h.have)}', c.warn),
        HourStatus.over => ('${hoursText(h.have)}/${hoursText(h.need)} เกิน', c.bad),
      };
      return Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: c.surface,
        border: Border.all(color: c.line),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('ตรวจตามหลักหน่วยกิต (ชม./สัปดาห์) · $weekText',
              style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 52,
              columns: const [
                DataColumn(label: Text('วิชา')),
                DataColumn(label: Text('หน่วยกิต')),
                DataColumn(label: Text('ทฤษฎี')),
                DataColumn(label: Text('ปฏิบัติ')),
                DataColumn(label: Text('หมายเหตุ')),
              ],
              rows: [
                for (final s in shown)
                  () {
                    final check = weekCreditCheck(s, slots);
                    final w = weekMinutes(s, slots);
                    return DataRow(cells: [
                      DataCell(Text(s.name)),
                      DataCell(Text(s.credits ?? '—')),
                      DataCell(cell(check?.theory, w.theory)),
                      DataCell(cell(check?.lab, w.lab)),
                      DataCell(Text(
                        check == null
                            ? 'ยังไม่มีหน่วยกิต'
                            : check.unknown > 0
                                ? 'ยังไม่ตั้งประเภท ${hoursText(check.unknown)} ชม.${check.totalMatchesOnly ? ' (รวมแล้วครบ)' : ''}'
                                : 'ศึกษาเอง ${check.hours.self} ชม.',
                        style: TextStyle(color: c.muted),
                      )),
                    ]);
                  }(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
