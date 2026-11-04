import 'package:flutter/material.dart';

import '../calendar/calendar_flows.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart';
import '../calendar/day_agenda.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';

/// มุมมองปฏิทิน 4 แบบ
enum CalView { day, week, month, year }

/// เลื่อนไป/กลับ [step] เดือน แต่คงวันที่ไว้ (31 ม.ค. + 1 เดือน → 28/29 ก.พ.)
DateTime addMonths(DateTime d, int step) {
  final first = DateTime(d.year, d.month + step);
  final last = DateTime(first.year, first.month + 1, 0).day;
  return DateTime(first.year, first.month, d.day > last ? last : d.day);
}

/// วันทั้งหมดในตารางเดือน: เริ่มวันจันทร์ จบวันอาทิตย์ (5–6 แถว)
List<DateTime> monthGridDays(DateTime month) {
  final first = DateTime(month.year, month.month);
  final start = first.subtract(Duration(days: first.weekday - 1));
  final last = DateTime(month.year, month.month + 1, 0);
  final end = last.add(Duration(days: 7 - last.weekday));
  return [
    for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1)) d,
  ];
}

/// หน้า "ปฏิทิน": สลับดู วัน / สัปดาห์ / เดือน / ปี → เลือกวัน → ดู/เพิ่ม/เลื่อน/ยกเลิกงาน
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with CalendarListener<CalendarPage> {
  bool _loading = true;
  CalView _view = CalView.week;
  DateTime _selected = dayOnly(DateTime.now());
  List<Occurrence> _items = [];

  /// งานของแต่ละวันที่เห็นบนจอ (ใช้วาดจุดสีในสัปดาห์/เดือน)
  Map<DateTime, List<Occurrence>> _byDay = {};
  List<LifeBaseDay> _lifeBase = defaultLifeBase();
  Map<int, ActivityCategory> _categories = {};

  DateTime get _monday => _selected.subtract(Duration(days: _selected.weekday - 1));

  /// วันที่ต้องโหลดจุดสี ตามมุมมองตอนนี้
  List<DateTime> get _visibleDays => switch (_view) {
        CalView.week => [for (var i = 0; i < 7; i++) _monday.add(Duration(days: i))],
        CalView.month => monthGridDays(_selected),
        _ => const [],
      };

  @override
  Future<void> reload() async {
    final repo = calendar!;
    final day = _selected;
    final view = _view;
    final byDay = <DateTime, List<Occurrence>>{};
    for (final d in _visibleDays) {
      byDay[d] = await repo.occurrencesOn(d);
    }
    final items = byDay[day] ?? await repo.occurrencesOn(day);
    final lifeBase = await repo.lifeBase();
    final cats = await repo.categories();
    if (!mounted || day != _selected || view != _view) return; // ผู้ใช้กดเปลี่ยนระหว่างโหลด
    setState(() {
      _items = items;
      _byDay = byDay;
      _lifeBase = lifeBase;
      _categories = {for (final c in cats) c.id: c};
      _loading = false;
    });
  }

  void _go({DateTime? day, CalView? view}) {
    setState(() {
      if (day != null) _selected = dayOnly(day);
      if (view != null) _view = view;
    });
    reload();
  }

  /// ◀ ▶ เลื่อนตามมุมมอง
  void _step(int dir) => _go(
        day: switch (_view) {
          CalView.day => _selected.add(Duration(days: dir)),
          CalView.week => _selected.add(Duration(days: 7 * dir)),
          CalView.month => addMonths(_selected, dir),
          CalView.year => addMonths(_selected, 12 * dir),
        },
      );

  String get _title {
    switch (_view) {
      case CalView.day:
        return '${thaiShortDate(_selected)} ${buddhistYear(_selected)}';
      case CalView.week:
        final sun = _monday.add(const Duration(days: 6));
        return '${thaiShortDate(_monday)} – ${thaiShortDate(sun)}';
      case CalView.month:
        return thaiMonthYear(_selected);
      case CalView.year:
        return 'พ.ศ. ${buddhistYear(_selected)}';
    }
  }

  (String, String) get _stepTips => switch (_view) {
        CalView.day => ('วันก่อน', 'วันถัดไป'),
        CalView.week => ('สัปดาห์ก่อน', 'สัปดาห์ถัดไป'),
        CalView.month => ('เดือนก่อน', 'เดือนถัดไป'),
        CalView.year => ('ปีก่อน', 'ปีถัดไป'),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final repo = calendar!;
    final today = dayOnly(DateTime.now());

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        Text('Calendar Core', style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 4),
        Text('ปฏิทิน',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 16),

        // สลับมุมมอง
        SegmentedButton<CalView>(
          segments: const [
            ButtonSegment(value: CalView.day, label: Text('วัน')),
            ButtonSegment(value: CalView.week, label: Text('สัปดาห์')),
            ButtonSegment(value: CalView.month, label: Text('เดือน')),
            ButtonSegment(value: CalView.year, label: Text('ปี')),
          ],
          selected: {_view},
          showSelectedIcon: false,
          onSelectionChanged: (s) => _go(view: s.first),
        ),
        const SizedBox(height: 12),

        // ◀ ชื่อช่วง ▶
        Row(
          children: [
            IconButton(
              tooltip: _stepTips.$1,
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _step(-1),
            ),
            Expanded(
              child: Text(
                _title,
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
              ),
            ),
            IconButton(
              tooltip: _stepTips.$2,
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _step(1),
            ),
          ],
        ),
        const SizedBox(height: 8),

        if (_view == CalView.week) _weekRow(today),
        if (_view == CalView.month) _monthGrid(today),
        if (_view == CalView.year) _yearGrid(today),

        if (_view != CalView.year) ...[
          const SizedBox(height: 16),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              Text(thaiShortDate(_selected),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
              Wrap(
                spacing: 8,
                children: [
                  if (_selected != today)
                    OutlinedButton(
                      onPressed: () => _go(day: today),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        foregroundColor: c.text,
                        side: BorderSide(color: c.line2),
                      ),
                      child: const Text('กลับวันนี้'),
                    ),
                  FilledButton.icon(
                    onPressed: () => addActivityFlow(context, repo, _selected),
                    icon: const Icon(Icons.add),
                    label: const Text('เพิ่มงาน'),
                    style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          DayAgenda(
            items: _items,
            categories: _categories,
            lifeBase: _lifeBase[_selected.weekday - 1],
            onTap: (o) => openOccurrenceActions(context, repo, o),
          ),
        ] else ...[
          const SizedBox(height: 12),
          Text('แตะเดือนเพื่อเปิดดูแบบเดือน',
              textAlign: TextAlign.center, style: TextStyle(color: c.muted)),
        ],
      ],
    );
  }

  /// สีของงานในวันนั้น (ไม่นับที่ยกเลิก/เลื่อนออก)
  List<Color> _dots(DateTime d) {
    final c = context.noir;
    return [
      for (final o in _byDay[d] ?? const <Occurrence>[])
        if (o.active) categoryColors(c, _categories[o.categoryId]?.colorKey).$2,
    ];
  }

  Widget _weekRow(DateTime today) => Row(
        children: [
          for (var i = 0; i < 7; i++)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _DayCell(
                  day: _monday.add(Duration(days: i)),
                  topLabel: thaiWeekdayShort[i],
                  selected: _monday.add(Duration(days: i)) == _selected,
                  isToday: _monday.add(Duration(days: i)) == today,
                  dimmed: false,
                  dots: _dots(_monday.add(Duration(days: i))),
                  onTap: () => _go(day: _monday.add(Duration(days: i))),
                ),
              ),
            ),
        ],
      );

  Widget _monthGrid(DateTime today) {
    final c = context.noir;
    final days = monthGridDays(_selected);
    return Column(
      children: [
        Row(
          children: [
            for (final w in thaiWeekdayShort)
              Expanded(
                child: Text(w,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 12, color: c.muted)),
              ),
          ],
        ),
        const SizedBox(height: 4),
        for (var r = 0; r < days.length ~/ 7; r++)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                for (final d in days.sublist(r * 7, r * 7 + 7))
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: _DayCell(
                        day: d,
                        selected: d == _selected,
                        isToday: d == today,
                        dimmed: d.month != _selected.month,
                        dots: _dots(d),
                        onTap: () => _go(day: d),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _yearGrid(DateTime today) {
    final c = context.noir;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 600 ? 4 : 3;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var m = 1; m <= 12; m++)
            SizedBox(
              width: (box.maxWidth - 8 * (cols - 1)) / cols,
              height: 64,
              child: Builder(builder: (context) {
                final isNow = today.year == _selected.year && today.month == m;
                final picked = _selected.month == m;
                return Material(
                  color: picked ? c.accent : c.surface,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _go(
                      view: CalView.month,
                      day: isNow ? today : DateTime(_selected.year, m),
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: isNow && !picked ? c.accent : c.line),
                      ),
                      child: Text(
                        thaiMonthsLong[m - 1],
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: picked ? c.onAccent : c.text,
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
        ],
      );
    });
  }
}

/// ช่องวัน 1 ช่อง (ใช้ทั้งแถวสัปดาห์และตารางเดือน) + จุดสีตามหมวดงาน
class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.dimmed,
    required this.dots,
    required this.onTap,
    this.topLabel,
  });

  final DateTime day;
  final String? topLabel;
  final bool selected;
  final bool isToday;
  final bool dimmed;
  final List<Color> dots;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final fg = selected ? c.onAccent : (dimmed ? c.muted : c.text);
    return Material(
      color: selected ? c.accent : c.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: topLabel == null ? 52 : 66,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isToday && !selected ? c.accent : c.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (topLabel != null)
                Text(topLabel!,
                    style: TextStyle(fontSize: 12, color: selected ? fg : c.muted)),
              Text('${day.day}',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: fg)),
              const SizedBox(height: 3),
              SizedBox(
                height: 6,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (final color in dots.take(4))
                      Container(
                        width: 6,
                        height: 6,
                        margin: const EdgeInsets.symmetric(horizontal: 1),
                        decoration: BoxDecoration(
                          color: selected ? c.onAccent : color,
                          shape: BoxShape.circle,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
