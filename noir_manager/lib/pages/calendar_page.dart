import 'package:flutter/material.dart';

import '../calendar/calendar_flows.dart';
import '../calendar/terms_page.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart';
import '../calendar/clash_page.dart';
import '../calendar/day_agenda.dart';
import '../calendar/week_views.dart';
import '../data/study_repository.dart';
import '../data/study_scope.dart';
import '../shell/app_nav.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_dropdown.dart';

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

/// มุมมองสัปดาห์ 3 แบบ (นัวร์เลือกได้ จำไว้ใน setting `week_style`)
enum WeekStyle { timeline, list, cards }

/// หน้า "ปฏิทิน": สลับดู วัน / สัปดาห์ / เดือน / ปี → เลือกวัน → ดู/เพิ่ม/เลื่อน/ยกเลิกงาน
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with CalendarListener<CalendarPage> {
  bool _loading = true;
  CalView _view = CalView.week;
  WeekStyle _weekStyle = WeekStyle.timeline;
  StudyRepository? _settings;

  /// ในมุมมองปี: แตะหัว "พ.ศ." → เลือกปีจากตาราง 16 ปี (แบบปฏิทิน Windows)
  bool _pickYear = false;
  DateTime _selected = dayOnly(DateTime.now());
  List<Occurrence> _items = [];

  /// งานของแต่ละวันที่เห็นบนจอ (ใช้วาดสัปดาห์ / จุดสีในเดือน)
  Map<DateTime, List<Occurrence>> _byDay = {};
  List<LifeBaseDay> _lifeBase = defaultLifeBase();

  /// dayKey → ชื่อวันหยุด
  Map<String, String> _holidays = {};
  Map<int, ActivityCategory> _categories = {};

  DateTime get _monday => _selected.subtract(Duration(days: _selected.weekday - 1));
  List<DateTime> get _weekDays =>
      [for (var i = 0; i < 7; i++) DateTime(_monday.year, _monday.month, _monday.day + i)];

  /// วันที่ต้องโหลด ตามมุมมองตอนนี้
  List<DateTime> get _visibleDays => switch (_view) {
        CalView.week => _weekDays,
        CalView.month => monthGridDays(_selected),
        _ => const [],
      };

  // แตะวันสอบในหน้าวิชา → มาที่วันนั้น (มุมมองวัน เห็นเวลาสอบชัด)
  void _onJump() {
    final d = calendarJump.day;
    if (d != null && mounted) _go(day: d, view: CalView.day);
  }

  @override
  void initState() {
    super.initState();
    calendarJump.addListener(_onJump);
  }

  @override
  void dispose() {
    calendarJump.removeListener(_onJump);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    _settings = StudyScope.of(context); // ต้องมีก่อน super เพราะ super จะเรียก reload()
    super.didChangeDependencies();
  }

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
    final holidays = await repo.holidays();
    final style = await _settings?.getSetting('week_style');
    if (!mounted || day != _selected || view != _view) return; // ผู้ใช้กดเปลี่ยนระหว่างโหลด
    setState(() {
      _items = items;
      _byDay = byDay;
      _lifeBase = lifeBase;
      _categories = {for (final c in cats) c.id: c};
      _holidays = {for (final h in holidays) dayKey(h.day): h.name};
      _weekStyle = WeekStyle.values
          .firstWhere((w) => w.name == style, orElse: () => _weekStyle);
      _loading = false;
    });
  }

  void _go({DateTime? day, CalView? view}) {
    setState(() {
      _pickYear = false;
      if (day != null) _selected = dayOnly(day);
      if (view != null) _view = view;
    });
    reload();
  }

  void _setWeekStyle(WeekStyle w) {
    setState(() => _weekStyle = w);
    _settings?.setSetting('week_style', w.name);
  }

  /// ◀ ▶ เลื่อนตามมุมมอง
  void _step(int dir) => _pickYear
      ? setState(() => _selected = addMonths(_selected, 10 * 12 * dir))
      : _go(
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
        if (_pickYear) {
          final from = _decadeStart;
          return 'พ.ศ. $from – ${from + 15}';
        }
        return 'พ.ศ. ${buddhistYear(_selected)}';
    }
  }

  /// ปี พ.ศ. แรกของตาราง 16 ปี (เริ่มที่ปีลงท้าย 0 เหมือน Windows: 2560–2575)
  int get _decadeStart => buddhistYear(_selected) ~/ 10 * 10;

  /// แตะหัวข้อ = ขยับขึ้นไปดูภาพกว้างขึ้น: วัน/สัปดาห์ → เดือน → ปี → ตารางปี
  void _zoomOut() {
    switch (_view) {
      case CalView.day:
      case CalView.week:
        _go(view: CalView.month);
      case CalView.month:
        _go(view: CalView.year);
      case CalView.year:
        setState(() => _pickYear = !_pickYear);
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
    final today = dayOnly(DateTime.now());

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      return ListView(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('ปฏิทิน',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: c.text)),
              ),
              // มุมมอง + รูปแบบสัปดาห์ เป็นดรอปดาวน์ แทนแถวปุ่ม → หัวหน้าโล่ง
              MiniDropdown<CalView>(
                value: _view,
                items: const [
                  (CalView.day, 'วัน'),
                  (CalView.week, 'สัปดาห์'),
                  (CalView.month, 'เดือน'),
                  (CalView.year, 'ปี'),
                ],
                onChanged: (v) => _go(view: v),
              ),
              if (_view == CalView.week && !(box.maxWidth < 720)) ...[
                const SizedBox(width: 8),
                MiniDropdown<WeekStyle>(
                  value: _weekStyle,
                  items: const [
                    (WeekStyle.timeline, 'ตารางเวลา'),
                    (WeekStyle.list, 'ลิสต์'),
                    (WeekStyle.cards, 'การ์ด'),
                  ],
                  onChanged: _setWeekStyle,
                ),
              ],
              const SizedBox(width: 4),
              // เครื่องมือรองเก็บไว้ใน ⋮
              PopupMenuButton<String>(
                tooltip: 'เพิ่มเติม',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) => v == 'clash' ? openClashPage(context) : openTermsPage(context),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'clash', child: Text('เช็กเวลาชน')),
                  PopupMenuItem(value: 'terms', child: Text('เทอมและวันหยุด')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...switch (_view) {
            CalView.day => [_navRow(), const SizedBox(height: 8), _agenda(today)],
            CalView.week => _weekBody(today, box.maxWidth),
            CalView.month => wide
                ? [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 360,
                          child: Column(children: [_navRow(), _monthGrid(today)]),
                        ),
                        const SizedBox(width: 24),
                        Expanded(child: _agenda(today)),
                      ],
                    ),
                  ]
                : [
                    _navRow(),
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 420),
                        child: _monthGrid(today),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _agenda(today),
                  ],
            CalView.year => [
                _navRow(),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: _pickYear ? _decadeGrid(today) : _yearGrid(today),
                ),
                const SizedBox(height: 12),
                Text(
                  _pickYear
                      ? 'แตะปีเพื่อเปิดปีนั้น'
                      : 'แตะเดือนเพื่อเปิดดูแบบเดือน · แตะ "พ.ศ." เพื่อเลือกปี',
                  style: TextStyle(color: c.muted),
                ),
              ],
          },
        ],
      );
    });
  }

  /// ◀ ชื่อช่วง ▶ (แตะชื่อ = ซูมออก)
  Widget _navRow() => Row(
        children: [
          IconButton(
            tooltip: _stepTips.$1,
            icon: const Icon(Icons.chevron_left),
            onPressed: () => _step(-1),
          ),
          Expanded(
            child: TextButton(
              onPressed: _zoomOut,
              style: TextButton.styleFrom(foregroundColor: context.noir.text),
              child: Text(_title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          IconButton(
            tooltip: _stepTips.$2,
            icon: const Icon(Icons.chevron_right),
            onPressed: () => _step(1),
          ),
        ],
      );

  /// หัววันที่เลือก + ปุ่ม แล้วตามด้วยตารางเวลาของวันนั้น
  Widget _agenda(DateTime today) {
    final c = context.noir;
    final repo = calendar!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
              Text(thaiShortDate(_selected),
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
              if (_holidays[dayKey(_selected)] case final name?)
                Chip(
                  avatar: Icon(Icons.beach_access_outlined, size: 16, color: c.amberText),
                  label: Text('วันหยุด · $name', style: TextStyle(color: c.amberText)),
                  backgroundColor: c.amberBg,
                  side: BorderSide.none,
                  visualDensity: VisualDensity.compact,
                ),
            ]),
            _actions(today),
          ],
        ),
        const SizedBox(height: 12),
        DayAgenda(
          items: _items,
          categories: _categories,
          lifeBase: _lifeBase[_selected.weekday - 1],
          onTap: (o) => openOccurrence(context, repo, o),
        ),
      ],
    );
  }

  Widget _actions(DateTime today) {
    final c = context.noir;
    final repo = calendar!;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
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
    );
  }

  // ---------- สัปดาห์ ----------

  List<Widget> _weekBody(DateTime today, double width) {
    final c = context.noir;
    final narrow = width < 720;
    // จอแคบ: A กับ C อ่านไม่ออก → ใช้ B อัตโนมัติ
    final style = narrow ? WeekStyle.list : _weekStyle;
    void onOcc(Occurrence o) => openOccurrence(context, calendar!, o);
    void onDay(DateTime d) => _go(day: d, view: CalView.day);

    return [
      _navRow(),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          if (narrow)
            Text('จอแคบ: แสดงแบบลิสต์', style: TextStyle(color: c.muted, fontSize: 13)),
          _actions(today),
        ],
      ),
      const SizedBox(height: 12),
      switch (style) {
        WeekStyle.timeline => WeekTimeline(
            days: _weekDays,
            byDay: _byDay,
            categories: _categories,
            lifeBase: _lifeBase,
            today: today,
            onTapOccurrence: onOcc,
            onTapDay: onDay,
          ),
        WeekStyle.list => WeekList(
            days: _weekDays,
            byDay: _byDay,
            categories: _categories,
            today: today,
            onTapOccurrence: onOcc,
            onTapDay: onDay,
          ),
        WeekStyle.cards => WeekCards(
            days: _weekDays,
            byDay: _byDay,
            categories: _categories,
            today: today,
            onTapOccurrence: onOcc,
            onTapDay: onDay,
          ),
      },
    ];
  }

  // ---------- เดือน (มินิมอล) ----------

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
          Row(
            children: [
              for (final d in days.sublist(r * 7, r * 7 + 7))
                Expanded(
                  child: _MiniDay(
                    day: d,
                    selected: d == _selected,
                    isToday: d == today,
                    dimmed: d.month != _selected.month,
                    dots: _dots(d),
                    marks: {for (final o in _byDay[d] ?? const <Occurrence>[]) ?markOf(o)},
                    onTap: () => _go(day: d),
                  ),
                ),
            ],
          ),
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

  // ---------- ปี ----------

  Widget _decadeGrid(DateTime today) {
    final from = _decadeStart;
    return _tileGrid([
      for (var y = from; y < from + 16; y++)
        (
          '$y',
          y == buddhistYear(_selected),
          y == buddhistYear(today),
          y >= from + 10, // ปีนอกช่วง 10 ปี = สีจาง เหมือน Windows
          () => setState(() {
                _pickYear = false;
                _selected = addMonths(_selected, (y - buddhistYear(_selected)) * 12);
              }),
        ),
    ]);
  }

  /// ตารางกล่อง 4 คอลัมน์ (จอแคบ 3) ใช้ทั้งตารางเดือนในปี และตารางปี
  Widget _tileGrid(List<(String, bool, bool, bool, VoidCallback)> tiles) {
    final c = context.noir;
    return LayoutBuilder(builder: (context, box) {
      final cols = box.maxWidth >= 480 ? 4 : 3;
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (label, picked, isNow, dim, onTap) in tiles)
            SizedBox(
              width: (box.maxWidth - 8 * (cols - 1)) / cols,
              height: 48,
              child: Material(
                color: picked ? c.accent : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: onTap,
                  child: Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: isNow && !picked ? Border.all(color: c.accent) : null,
                    ),
                    child: Text(
                      label,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: picked ? c.onAccent : (dim ? c.muted : c.text),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    });
  }

  Widget _yearGrid(DateTime today) => _tileGrid([
        for (var m = 1; m <= 12; m++)
          (
            thaiMonthsLong[m - 1],
            _selected.month == m,
            today.year == _selected.year && today.month == m,
            false,
            () => _go(
                  view: CalView.month,
                  day: today.year == _selected.year && today.month == m
                      ? today
                      : DateTime(_selected.year, m),
                ),
          ),
      ]);
}

/// ช่องวันแบบมินิมอล (ตารางเดือน): ตัวเลขในวงกลม + จุดสีเล็ก ๆ
class _MiniDay extends StatelessWidget {
  const _MiniDay({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.dimmed,
    required this.dots,
    this.marks = const {},
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final bool dimmed;
  final List<Color> dots;

  /// วันสอบ / วันส่งงาน → สัญลักษณ์แทนจุด เห็นได้ทันทีในตารางเดือน
  final Set<DayMark> marks;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: SizedBox(
        height: 48,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? c.accent : null,
                border: isToday && !selected ? Border.all(color: c.accent) : null,
              ),
              child: Text(
                '${day.day}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: isToday || selected ? FontWeight.w600 : FontWeight.w400,
                  color: selected ? c.onAccent : (dimmed ? c.muted.withValues(alpha: 0.5) : c.text),
                ),
              ),
            ),
            const SizedBox(height: 2),
            if (marks.isNotEmpty)
              SizedBox(
                height: 12,
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (marks.contains(DayMark.exam))
                    Icon(Icons.edit_note, size: 12, color: c.bad, semanticLabel: 'วันสอบ'),
                  if (marks.contains(DayMark.homework))
                    Icon(Icons.star, size: 11, color: c.warn, semanticLabel: 'วันส่งงาน'),
                ]),
              )
            else
            SizedBox(
              height: 4,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final color in dots.take(3))
                    Container(
                      width: 4,
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 1),
                      decoration: BoxDecoration(
                        color: dimmed ? color.withValues(alpha: 0.4) : color,
                        shape: BoxShape.circle,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
