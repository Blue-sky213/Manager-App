/// หน้าต่าง "จองเวลา" (เช่น รอบติว): เห็นภาพทั้งสัปดาห์ / ทั้งเดือนก่อน แล้วค่อยแตะเลือก
/// สัปดาห์ = 7 คอลัมน์ × เวลา (เส้นทุกชั่วโมง) · เดือน = ชั่วโมงว่างต่อวัน 3 ระดับสี
library;

import 'package:flutter/material.dart';

import '../study/subject_colors.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';
import 'free_slots.dart';
import 'lock_flow.dart' show showLockBadge;
import '../widgets/mini_segments.dart';

/// ผลที่เลือก: วัน · นาทีเริ่ม · ความยาว
typedef PickedSlot = ({DateTime day, int start, int minutes});

/// ข้อมูล 1 วันในหน้าจอง
class SlotDay {
  SlotDay(this.day, this.busy, this.from, this.to);
  final DateTime day;
  final List<Busy> busy;

  /// ช่วงที่จองได้ของวัน (ตื่น → นอน · วันนี้เริ่มหลังเวลาปัจจุบัน)
  final int from;
  final int to;

  /// ช่วงว่างจริง (ไม่ทับงานไหนเลย) · ใช้แนะนำ + นับชั่วโมงว่าง
  List<Gap> get gaps => from < to ? freeGaps(busy, from, to) : const [];

  /// ช่วงที่จองได้ ถ้ายอมทับงาน "แทนได้"
  List<Gap> get bookable => from < to ? freeGaps(busy.where((b) => !b.replaceable).toList(), from, to) : const [];

  /// ชั่วโมงว่างที่ยาวพอสำหรับรอบยาว [len] นาที
  double freeHours(int len) => gaps.where((g) => g.length >= len).fold(0, (s, g) => s + g.length) / 60;
}

/// ระดับสีของหน้าเดือน: 0 = ไม่มีช่องยาวพอ · 1 = < 3 ชม. · 2 = 3–7 ชม. · 3 = 7 ชม.ขึ้นไป
int freeLevel(double hours) => hours <= 0 ? 0 : (hours < 3 ? 1 : (hours < 7 ? 2 : 3));

/// เลือกเวลาเริ่มจากจุดที่แตะ: ปัด 15 นาที แล้วขยับให้ทั้งรอบอยู่ในช่องที่จองได้ · null = ช่องสั้นเกิน / แตะโดนงานที่ทับไม่ได้
int? fitStart(List<Gap> bookable, int minute, int len) {
  for (final g in bookable) {
    if (minute < g.start || minute >= g.end) continue;
    if (g.length < len) return null;
    final s = (minute ~/ 15) * 15;
    return s.clamp(g.start, g.end - len);
  }
  return null;
}

Future<SlotDay> _loadDay(CalendarRepository repo, DateTime day, List<LifeBaseDay> lifeBase, int bufferAfter) async {
  final now = DateTime.now();
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
        tutor: x.kind == ActivityKind.tutor,
        classSession: x.kind == ActivityKind.classSession,
        locked: showLockBadge(x)));
  }
  final lb = lifeBase[day.weekday - 1];
  var from = lb.wakeMinute;
  final to = lb.bedMinute < 12 * 60 ? 24 * 60 : lb.bedMinute;
  final today = dayOnly(now);
  if (day.isBefore(today)) {
    from = to; // วันที่ผ่านแล้ว จองไม่ได้
  } else if (day == today) {
    final nowMin = ((now.hour * 60 + now.minute + 14) ~/ 15) * 15;
    if (nowMin > from) from = nowMin;
  }
  return SlotDay(day, list, from, to);
}

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
  int? subjectId,
}) async {
  final lifeBase = await repo.lifeBase();
  if (!context.mounted) return null;
  final anchor = dayOnly(days.isEmpty ? DateTime.now() : days.first);
  final wide = MediaQuery.sizeOf(context).width >= 720;
  final body = _SlotPicker(
    repo: repo,
    title: title,
    note: note,
    minutes: minutes,
    anchor: anchor,
    lifeBase: lifeBase,
    preferStart: preferStart,
    bufferAfter: bufferAfter,
    avoidDays: avoidDays,
    subjectColors: subjectColors,
    subjectId: subjectId,
  );
  return showDialog<PickedSlot>(
    context: context,
    builder: (_) => wide
        ? Dialog(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760), child: body))
        : Dialog.fullscreen(child: SafeArea(child: body)),
  );
}

class _SlotPicker extends StatefulWidget {
  const _SlotPicker({
    required this.repo,
    required this.title,
    required this.note,
    required this.minutes,
    required this.anchor,
    required this.lifeBase,
    required this.preferStart,
    required this.bufferAfter,
    required this.avoidDays,
    required this.subjectColors,
    required this.subjectId,
  });

  final CalendarRepository repo;
  final String title;
  final String? note;
  final int minutes;
  final DateTime anchor;
  final List<LifeBaseDay> lifeBase;
  final int preferStart;
  final int bufferAfter;
  final Set<DateTime> avoidDays;
  final Map<int, Color> subjectColors;
  final int? subjectId;

  @override
  State<_SlotPicker> createState() => _SlotPickerState();
}

class _SlotPickerState extends State<_SlotPicker> {
  late int _len = widget.minutes;
  late DateTime _monday = _mondayOf(widget.anchor);
  late DateTime _month = DateTime(widget.anchor.year, widget.anchor.month);
  bool _monthView = false;
  List<SlotDay> _week = [];
  Map<DateTime, SlotDay> _monthDays = {};
  DateTime? _day;
  int? _start;
  bool _autoPicked = false;

  static DateTime _mondayOf(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

  @override
  void initState() {
    super.initState();
    _loadWeek();
  }

  Future<void> _loadWeek() async {
    final week = [
      for (var i = 0; i < 7; i++)
        await _loadDay(widget.repo, DateTime(_monday.year, _monday.month, _monday.day + i), widget.lifeBase,
            widget.bufferAfter),
    ];
    if (!mounted) return;
    setState(() {
      _week = week;
      // เปิดครั้งแรก: เลือกช่องแนะนำอันแรกไว้ให้เลย
      if (!_autoPicked) {
        _autoPicked = true;
        final r = _recommend();
        if (r.isNotEmpty) {
          _day = r.first.$1;
          _start = r.first.$2;
        }
      }
    });
  }

  Future<void> _loadMonth() async {
    final first = DateTime(_month.year, _month.month);
    final last = DateTime(_month.year, _month.month + 1, 0);
    final out = <DateTime, SlotDay>{};
    for (var d = first; !d.isAfter(last); d = DateTime(d.year, d.month, d.day + 1)) {
      out[d] = await _loadDay(widget.repo, d, widget.lifeBase, widget.bufferAfter);
    }
    if (!mounted) return;
    setState(() => _monthDays = out);
  }

  /// ช่องแนะนำของสัปดาห์ (ไม่เกิน 3): ใกล้เวลาที่ชอบ · วันที่มีคาบเรียนวิชานี้ไว้ท้าย
  List<(DateTime, int)> _recommend() {
    final gaps = {for (var i = 0; i < _week.length; i++) i: _week[i].gaps};
    final raw = suggestSlots(gaps, _len + widget.bufferAfter, widget.preferStart, limit: 14);
    final sorted = [
      ...raw.where((s) => !widget.avoidDays.contains(_week[s.row].day)),
      ...raw.where((s) => widget.avoidDays.contains(_week[s.row].day)),
    ];
    final seen = <DateTime>{};
    final out = <(DateTime, int)>[];
    for (final s in sorted) {
      if (seen.add(_week[s.row].day)) out.add((_week[s.row].day, s.start));
      if (out.length == 3) break;
    }
    return out;
  }

  /// ติววิชานี้ในสัปดาห์ที่ดูอยู่: (นาทีรวม ไม่นับเวลาพักหลังติว, จำนวนรอบ)
  (int, int) _tutorWeek() {
    var mins = 0, rounds = 0;
    for (final d in _week) {
      for (final b in d.busy) {
        if (!b.tutor || (widget.subjectId != null && b.subjectId != widget.subjectId)) continue;
        mins += (b.end - b.start - widget.bufferAfter).clamp(0, 24 * 60);
        rounds++;
      }
    }
    return (mins, rounds);
  }

  void _shiftWeek(int dir) {
    setState(() {
      _monday = DateTime(_monday.year, _monday.month, _monday.day + 7 * dir);
      _week = [];
    });
    _loadWeek();
  }

  void _shiftMonth(int dir) {
    setState(() {
      _month = DateTime(_month.year, _month.month + dir);
      _monthDays = {};
    });
    _loadMonth();
  }

  // ---- ลากกล่องที่เลือก: ย้ายเวลา / วัน · ลากขีดล่าง = เปลี่ยนความยาว · ปล่อยตรงที่ห้ามทับ = เด้งกลับ ----
  (DateTime?, int?, int)? _beforeDrag;

  void _dragStart() => _beforeDrag = (_day, _start, _len);

  void _dragMove(SlotDay d, int start) {
    setState(() {
      _day = d.day;
      _start = start.clamp(0, 24 * 60 - _len);
    });
  }

  void _dragResize(int len) => setState(() => _len = len.clamp(15, 240));

  void _dragEnd() {
    final d = _week.where((x) => x.day == _day).firstOrNull;
    if (d == null || _start == null || _blocked(d, _start!, _len)) {
      final b = _beforeDrag;
      if (b != null) {
        setState(() {
          _day = b.$1;
          _start = b.$2;
          _len = b.$3;
        });
      }
    }
    _beforeDrag = null;
  }

  /// เปลี่ยนความยาว · ช่องไม่พอ = กล่องแดง (ไม่ขยับเวลาให้เอง)
  void _setLen(int len) => setState(() => _len = len.clamp(15, 240));

  void _tap(SlotDay d, int minute) {
    final s = fitStart(d.bookable, minute, _len);
    if (s == null) return;
    setState(() {
      _day = d.day;
      _start = s;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final selDay = _week.where((d) => d.day == _day).firstOrNull ?? _monthDays[_day];
    final hits = selDay == null || _start == null ? const <Busy>[] : clashesAt(selDay.busy, _start!, _len);
    final blocked = selDay != null && _start != null && _blocked(selDay, _start!, _len);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(widget.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
          ),
          IconButton(tooltip: 'ปิด', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
        ]),
        if (widget.note != null) Text(widget.note!, style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 8),
        // ความยาวรอบ (− / + ทีละ 15 นาที · ลากยืดกล่องแล้วตัวเลขเปลี่ยนตาม) + สัปดาห์ | เดือน ในแถวเดียว
        Row(children: [
          Container(
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'สั้นลง 15 นาที',
                visualDensity: VisualDensity.compact,
                onPressed: _len <= 15 ? null : () => _setLen(_len - 15),
                icon: const Icon(Icons.remove, size: 18),
              ),
              SizedBox(
                width: 92,
                child: Text(durationText(_len),
                    key: const ValueKey('slot-len'),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
              ),
              IconButton(
                tooltip: 'ยาวขึ้น 15 นาที',
                visualDensity: VisualDensity.compact,
                onPressed: _len >= 240 ? null : () => _setLen(_len + 15),
                icon: const Icon(Icons.add, size: 18),
              ),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: MiniSegments<bool>(
              value: _monthView,
              items: const [(false, 'สัปดาห์'), (true, 'เดือน')],
              onChanged: (v) {
                setState(() => _monthView = v);
                if (v && _monthDays.isEmpty) _loadMonth();
              },
            ),
          ),
        ]),
        const SizedBox(height: 4),
        Row(children: [
          IconButton(
            tooltip: _monthView ? 'เดือนก่อน' : 'สัปดาห์ก่อน',
            onPressed: () => _monthView ? _shiftMonth(-1) : _shiftWeek(-1),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(
              _monthView
                  ? thaiMonthYear(_month)
                  : '${thaiShortDate(_monday)} – ${thaiShortDate(_monday.add(const Duration(days: 6)))}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.text),
            ),
          ),
          IconButton(
            tooltip: _monthView ? 'เดือนถัดไป' : 'สัปดาห์ถัดไป',
            onPressed: () => _monthView ? _shiftMonth(1) : _shiftWeek(1),
            icon: const Icon(Icons.chevron_right),
          ),
        ]),
        const SizedBox(height: 4),
        Expanded(
          child: _monthView
              ? _MonthFree(
                  month: _month,
                  days: _monthDays,
                  len: _len,
                  selected: _day,
                  onPick: (d) {
                    setState(() {
                      _monthView = false;
                      _monday = _mondayOf(d);
                      _week = [];
                      final g = _monthDays[d]?.gaps.where((g) => g.length >= _len).firstOrNull;
                      _day = g == null ? null : d;
                      _start = g?.start;
                    });
                    _loadWeek();
                  },
                )
              : _week.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _WeekGrid(
                      week: _week,
                      len: _len,
                      recommended: _recommend(),
                      selectedDay: _day,
                      selectedStart: _start,
                      subjectColors: widget.subjectColors,
                      subjectId: widget.subjectId,
                      onTap: _tap,
                      onDragStart: _dragStart,
                      onDragMove: _dragMove,
                      onDragResize: _dragResize,
                      onDragEnd: _dragEnd,
                      axisFrom: (widget.lifeBase.map((l) => l.wakeMinute).reduce((a, b) => a < b ? a : b) ~/ 60) * 60,
                    ),
        ),
        const SizedBox(height: 8),
        _Legend(month: _monthView),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [
            if (_tutorWeek() case (final mins, final rounds) when !_monthView)
              Text(
                'ติวสัปดาห์นี้ ${mins == 0 ? '0 ชม.' : durationText(mins)} ($rounds รอบ)'
                '${_day == null ? '' : ' → รวมรอบนี้ ${durationText(mins + _len)}'}',
                style: TextStyle(fontSize: 12, color: c.muted),
              ),
            Text(
              _day == null || _start == null
                  ? 'แตะช่องสีเขียวเพื่อเลือกเวลา · ลากกล่องเพื่อย้าย'
                  : blocked
                      ? '⚠ วางตรงนี้ไม่ได้ ${hits.where((b) => !b.replaceable).map((b) => b.title).join(', ')}'
                      : hits.isEmpty
                          ? '${thaiShortDate(_day!)} ${rangeText(_start!, _len)} · ${durationText(_len)}'
                          : '${thaiShortDate(_day!)} ${rangeText(_start!, _len)} · ทับ ${hits.map((b) => b.title).join(', ')} (ย้ายได้ที่ปฏิทิน)',
              style: TextStyle(fontWeight: FontWeight.w600, color: blocked ? c.bad : c.text),
            ),
            FilledButton(
              onPressed: _day == null || _start == null || blocked
                  ? null
                  : () => Navigator.pop(context, (day: _day!, start: _start!, minutes: _len)),
              child: const Text('จองเวลานี้'),
            ),
          ],
        ),
      ]),
    );
  }
}

/// วางไม่ได้: นอกช่วงที่จองได้ของวัน หรือทับงานที่ห้ามทับ (เรียน / ติว / ล็อก)
bool _blocked(SlotDay d, int start, int len) =>
    start < d.from || start + len > d.to || clashesAt(d.busy, start, len).any((b) => !b.replaceable);

/// สีพื้นของช่วงว่าง / ไม่ว่าง (ใช้ทั้งตารางและคำอธิบาย)
Color _freeColor(NoirColors c) => c.greenBg;

class _Legend extends StatelessWidget {
  const _Legend({required this.month});
  final bool month;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    Widget item(Widget mark, String text) => Row(mainAxisSize: MainAxisSize.min, children: [
          mark,
          const SizedBox(width: 4),
          Text(text, style: TextStyle(fontSize: 11, color: c.muted)),
        ]);
    Widget box(Color color, {Border? border}) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, border: border, borderRadius: BorderRadius.circular(3)));
    if (month) {
      return Wrap(spacing: 12, runSpacing: 4, children: [
        for (final l in [1, 2, 3]) item(box(monthLevelColor(c, l).$1), const ['', 'ว่างน้อย < 3 ชม.', '3–7 ชม.', 'ว่างมาก 7+ ชม.'][l]),
        item(box(c.line), 'ไม่มีช่องยาวพอ'),
      ]);
    }
    return Wrap(spacing: 12, runSpacing: 4, children: [
      item(box(_freeColor(c)), 'ว่าง'),
      item(const Text('🎓', style: TextStyle(fontSize: 11)), 'เรียน'),
      item(SizedBox(width: 12, height: 12, child: DecoratedBox(decoration: ShapeDecoration(shape: DashedRoundedBorder(color: c.muted, radius: 3, width: 1.2, dash: 3, gap: 2)))), 'ติว'),
      item(const _Hatch(width: 12, height: 12), '⇄ แทนได้ (จองทับได้)'),
      item(const Text('🔒', style: TextStyle(fontSize: 11)), 'ล็อก'),
      item(box(Colors.transparent, border: Border.all(color: c.good, width: 1.5)), '★ แนะนำ'),
    ]);
  }
}

/// สีหน้าเดือน 3 ระดับ (พื้น, ตัวหนังสือ) · ว่างมาก = เขียวเข้มตัวขาว
(Color, Color) monthLevelColor(NoirColors c, int level) => switch (level) {
      1 => (Color.alphaBlend(c.good.withValues(alpha: 0.18), c.surface), c.text),
      2 => (Color.alphaBlend(c.good.withValues(alpha: 0.5), c.surface), c.text),
      3 => (c.good, Colors.white),
      _ => (c.line, c.muted),
    };

/// ลายขีดเฉียง = งาน "แทนได้"
class _Hatch extends StatelessWidget {
  const _Hatch({this.width, this.height});
  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) =>
      SizedBox(width: width, height: height, child: CustomPaint(painter: _HatchPainter(context.noir.muted)));
}

class _HatchPainter extends CustomPainter {
  _HatchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color.withValues(alpha: 0.35)
      ..strokeWidth = 1.2;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    for (var x = -size.height; x < size.width; x += 6) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HatchPainter old) => old.color != color;
}

/// ตารางสัปดาห์: 7 คอลัมน์ × เวลา · เส้นทุกชั่วโมง (ประครึ่งชั่วโมง) · กล่องมีชื่อ + ไอคอน
class _WeekGrid extends StatelessWidget {
  const _WeekGrid({
    required this.week,
    required this.len,
    required this.recommended,
    required this.selectedDay,
    required this.selectedStart,
    required this.subjectColors,
    required this.subjectId,
    required this.onTap,
    required this.axisFrom,
    required this.onDragStart,
    required this.onDragMove,
    required this.onDragResize,
    required this.onDragEnd,
  });

  final VoidCallback onDragStart;
  final void Function(SlotDay day, int start) onDragMove;
  final ValueChanged<int> onDragResize;
  final VoidCallback onDragEnd;
  static final _rowKey = GlobalKey();

  /// จุดที่จับในกล่อง (นาทีจากหัวกล่อง) · เก็บไว้นอก build เพราะกล่องถูกสร้างใหม่ทุกครั้งที่ขยับ
  static int _grab = 0;

  /// เวลาบนสุดของตาราง (ตื่นเร็วสุดของสัปดาห์ ปัดลงเป็นชั่วโมง)
  final int axisFrom;
  final List<SlotDay> week;
  final int len;
  final List<(DateTime, int)> recommended;
  final DateTime? selectedDay;
  final int? selectedStart;
  final Map<int, Color> subjectColors;
  final int? subjectId;
  final void Function(SlotDay day, int minute) onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final today = dayOnly(DateTime.now());
    const axisTo = 24 * 60;
    final hours = (axisTo - axisFrom) ~/ 60;

    return LayoutBuilder(builder: (context, box) {
      const head = 36.0;
      final pxH = ((box.maxHeight - head) / hours).clamp(26.0, 60.0);
      final narrow = box.maxWidth < 600;
      final colW = (box.maxWidth - 34) / 7;
      final selIdx = selectedStart == null ? -1 : week.indexWhere((d) => d.day == selectedDay);
      double y(int m) => (m - axisFrom) / 60 * pxH;

      Widget column(SlotDay d) {
        final past = d.day.isBefore(today);
        return LayoutBuilder(builder: (context, cb) {
          return GestureDetector(
            key: ValueKey('slotcol-${d.day.day}'),
            behavior: HitTestBehavior.opaque,
            onTapUp: (e) => onTap(d, axisFrom + (e.localPosition.dy / pxH * 60).round()),
            child: SizedBox(
              height: hours * pxH,
              child: Stack(clipBehavior: Clip.hardEdge, children: [
                // พื้น: ช่วงจองได้ = เขียว · นอก (นอน / ผ่านไปแล้ว) = เทา
                Positioned.fill(child: ColoredBox(color: c.surface2)),
                if (d.from < d.to)
                  Positioned(left: 0, right: 0, top: y(d.from), height: y(d.to) - y(d.from), child: ColoredBox(color: _freeColor(c))),
                for (var h = 0; h < hours; h++) ...[
                  Positioned(left: 0, right: 0, top: h * pxH, child: Container(height: 1, color: c.line)),
                  Positioned(left: 0, right: 0, top: h * pxH + pxH / 2, child: Container(height: 1, color: c.line.withValues(alpha: 0.4))),
                ],
                for (final b in d.busy)
                  if (b.end > axisFrom)
                    Positioned(
                      left: 1,
                      right: 1,
                      top: y(b.start.clamp(axisFrom, axisTo)),
                      height: (y(b.end) - y(b.start.clamp(axisFrom, axisTo)) - 1).clamp(2.0, double.infinity),
                      child: _BusyBox(b: b, color: _colorOf(c, b), narrow: narrow, thisSubject: b.subjectId != null && b.subjectId == subjectId),
                    ),
                for (final (rd, rs) in recommended)
                  if (rd == d.day)
                    Positioned(
                      left: 1,
                      right: 1,
                      top: y(rs),
                      height: y(rs + len) - y(rs),
                      child: IgnorePointer(
                        child: Container(
                          alignment: Alignment.topRight,
                          decoration: BoxDecoration(
                            border: Border.all(color: c.good, width: 1.5),
                            borderRadius: BorderRadius.circular(5),
                          ),
                          child: Text('★', style: TextStyle(fontSize: 10, color: c.good)),
                        ),
                      ),
                    ),
                if (past) Positioned.fill(child: IgnorePointer(child: ColoredBox(color: c.bg.withValues(alpha: 0.5)))),
              ]),
            ),
          );
        });
      }

      return SingleChildScrollView(
        child: Column(children: [
          // หัววัน
          SizedBox(
            height: head,
            child: Row(children: [
              const SizedBox(width: 34),
              for (final d in week)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Text(thaiWeekdayShort[d.day.weekday - 1], style: TextStyle(fontSize: 11, color: c.muted)),
                    Text('${d.day.day}',
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: d.day == today ? c.accent : c.text)),
                  ]),
                ),
            ]),
          ),
          // กล่องที่เลือกวางทับทั้งตาราง (ไม่อยู่ในคอลัมน์วัน) → ลากข้ามวันได้ต่อเนื่อง ไม่หลุดกลางทาง
          Stack(clipBehavior: Clip.none, children: [
          Row(key: _rowKey, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 34,
              height: hours * pxH,
              child: Stack(children: [
                for (var h = 0; h < hours; h++)
                  if (h % (pxH < 34 ? 2 : 1) == 0)
                    Positioned(
                      top: h * pxH - 6,
                      right: 4,
                      child: Text((axisFrom ~/ 60 + h).toString().padLeft(2, '0'),
                          style: TextStyle(fontSize: 10, color: c.muted)),
                    ),
              ]),
            ),
            for (final d in week)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1.5),
                  child: ClipRRect(borderRadius: BorderRadius.circular(6), child: column(d)),
                ),
              ),
          ]),
          if (selIdx >= 0)
            Positioned(
              key: const ValueKey('slot-selected-pos'),
              left: 34 + selIdx * colW + 2.5,
              width: colW - 5,
              top: y(selectedStart!),
              height: y(selectedStart! + len) - y(selectedStart!),
              child: _selectionBox(context, week[selIdx], colW - 5, pxH, axisFrom),
            ),
          ]),
        ]),
      );
    });
  }

  /// กล่องที่เลือก: ลากทั้งกล่อง = ย้าย (ข้ามวันได้) · ลากขีดล่าง = ยืด / หด · สีแดง = วางตรงนี้ไม่ได้
  Widget _selectionBox(BuildContext context, SlotDay d, double w, double pxH, int axisFrom) {
    final c = context.noir;
    final bad = _blocked(d, selectedStart!, len);
    final color = bad ? c.bad : c.accent;
    int snap(double m) => ((m / 15).round() * 15);
    (int, double)? at(Offset global) {
      final box = _rowKey.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) return null;
      final p = box.globalToLocal(global);
      final colW = (box.size.width - 34) / 7;
      return (((p.dx - 34) / colW).floor().clamp(0, 6), axisFrom + p.dy / pxH * 60);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: GestureDetector(
        key: const ValueKey('slot-selected'),
        onPanStart: (e) {
          _grab = (e.localPosition.dy / pxH * 60).round();
          onDragStart();
        },
        onPanUpdate: (e) {
          final hit = at(e.globalPosition);
          if (hit != null) onDragMove(week[hit.$1], snap(hit.$2 - _grab));
        },
        onPanEnd: (_) => onDragEnd(),
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: (bad ? c.bad : c.surface).withValues(alpha: bad ? 0.25 : 0.9),
            shape: DashedRoundedBorder(color: color, radius: 5, width: 2),
          ),
          child: Stack(children: [
            Padding(
              padding: const EdgeInsets.all(2),
              child: Text(
                w < 60
                    ? '${fmtMinute(selectedStart!)}\n${durationText(len)}'
                    : '${rangeText(selectedStart!, len)}\n${durationText(len)}',
                maxLines: 3,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
              ),
            ),
            // ขีดล่าง: ลากขึ้นลงเพื่อเปลี่ยนความยาวรอบ
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 12,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeUpDown,
                child: GestureDetector(
                  key: const ValueKey('slot-resize'),
                  behavior: HitTestBehavior.opaque,
                  onVerticalDragStart: (_) => onDragStart(),
                  onVerticalDragUpdate: (e) {
                    final hit = at(e.globalPosition);
                    if (hit != null) onDragResize(snap(hit.$2 - selectedStart!));
                  },
                  onVerticalDragEnd: (_) => onDragEnd(),
                  child: Center(
                    child: Container(
                      width: 22,
                      height: 4,
                      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Color _colorOf(NoirColors c, Busy b) {
    if (b.subjectId != null) return subjectColors[b.subjectId] ?? c.line2;
    return c.line2;
  }
}

/// กล่องงาน 1 ชิ้นในตาราง: ไอคอน (🔒 🎓 ✎ ⇄) + ชื่อ
class _BusyBox extends StatelessWidget {
  const _BusyBox({required this.b, required this.color, required this.narrow, required this.thisSubject});
  final Busy b;
  final Color color;
  final bool narrow;
  final bool thisSubject;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final name = b.title.replaceFirst('เรียน · ', '').replaceFirst('ติว · ', '');
    final icon = [
      if (b.locked) '🔒',
      if (b.classSession && !narrow) '🎓',
      if (b.tutor) '✎',
      if (b.replaceable) '⇄',
    ].join();
    final text = Text(
      '$icon${icon.isEmpty ? '' : ' '}$name',
      maxLines: 4,
      overflow: TextOverflow.clip,
      style: TextStyle(
        fontSize: narrow ? 8.5 : 11,
        height: 1.15,
        fontWeight: thisSubject ? FontWeight.w600 : FontWeight.w400,
        color: b.tutor || b.replaceable ? c.text : onColor(color),
      ),
    );
    return Tooltip(
      message: '${b.title}\n${rangeText(b.start, b.end - b.start)}${b.replaceable ? '\n⇄ แทนได้ · จองทับได้' : ''}',
      child: b.tutor
          ? DecoratedBox(
              decoration: ShapeDecoration(
                color: c.surface,
                shape: DashedRoundedBorder(color: color, radius: 4, width: 1.5, dash: 4, gap: 2),
              ),
              child: Padding(padding: const EdgeInsets.all(2), child: text),
            )
          : b.replaceable
              ? Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border.all(color: c.line2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Stack(children: [
                    const Positioned.fill(child: _Hatch()),
                    Padding(padding: const EdgeInsets.all(2), child: text),
                  ]),
                )
              : Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                    border: thisSubject ? Border.all(color: c.text.withValues(alpha: 0.5), width: 1.2) : null,
                  ),
                  child: text,
                ),
    );
  }
}

/// หน้าเดือน: ตัวเลขชั่วโมงว่างต่อวัน (เฉพาะช่องที่ยาวพอ) · 3 ระดับสี · แตะวัน → เปิดสัปดาห์นั้น
class _MonthFree extends StatelessWidget {
  const _MonthFree({
    required this.month,
    required this.days,
    required this.len,
    required this.selected,
    required this.onPick,
  });

  final DateTime month;
  final Map<DateTime, SlotDay> days;
  final int len;
  final DateTime? selected;
  final ValueChanged<DateTime> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (days.isEmpty) return const Center(child: CircularProgressIndicator());
    final first = DateTime(month.year, month.month);
    final lead = first.weekday - 1;
    final count = DateTime(month.year, month.month + 1, 0).day;
    final today = dayOnly(DateTime.now());
    return SingleChildScrollView(
      child: Column(children: [
        Row(children: [
          for (final w in thaiWeekdayShort)
            Expanded(child: Center(child: Text(w, style: TextStyle(fontSize: 11, color: c.muted)))),
        ]),
        const SizedBox(height: 4),
        GridView.count(
          crossAxisCount: 7,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 4,
          crossAxisSpacing: 4,
          childAspectRatio: 1.05,
          children: [
            for (var i = 0; i < lead; i++) const SizedBox(),
            for (var n = 1; n <= count; n++)
              Builder(builder: (context) {
                final d = DateTime(month.year, month.month, n);
                final past = d.isBefore(today);
                final hours = past ? 0.0 : (days[d]?.freeHours(len) ?? 0);
                final (bg, fg) = monthLevelColor(c, freeLevel(hours));
                return Opacity(
                  opacity: past ? 0.4 : 1,
                  child: Material(
                    color: bg,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                      side: d == selected ? BorderSide(color: c.accent, width: 2) : BorderSide.none,
                    ),
                    child: InkWell(
                      key: ValueKey('slotday-$n'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: past ? null : () => onPick(d),
                      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Text('$n', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: fg)),
                        FittedBox(
                          child: Text(
                            hours <= 0 ? '—' : '${hours == hours.roundToDouble() ? hours.toInt() : hours.toStringAsFixed(1)} ชม.',
                            style: TextStyle(fontSize: 10, color: fg),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              }),
          ],
        ),
      ]),
    );
  }
}
