import 'package:flutter/material.dart';

import '../calendar/achievements.dart' show dayProgress;
import '../calendar/calendar_flows.dart';
import '../calendar/terms_page.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/stickers.dart' show DaySticker, stickersByDay, holidaysByDay, placedByDay, highlightOf;
import '../calendar/clash_page.dart';
import '../calendar/day_agenda.dart';
import '../calendar/day_judge.dart' show judgeDays, importantPending;
import '../calendar/notebook_view.dart';
import '../calendar/sticker_book.dart';
import '../calendar/sticker_ui.dart' show DayStickerCard, stickWithLimit;
import '../calendar/week_views.dart';
import '../data/study_repository.dart';
import '../data/study_scope.dart';
import '../shell/app_nav.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_dropdown.dart';
import '../widgets/toast.dart';

export '../calendar/calendar_models.dart' show addMonths, monthGridDays;

/// มุมมองปฏิทิน 4 แบบ
enum CalView { day, week, month, year }

/// มุมมองสัปดาห์ 3 แบบ (นัวร์เลือกได้ จำไว้ใน setting `week_style`)
enum WeekStyle { timeline, list, cards }

/// หน้า "ปฏิทิน": สลับดู วัน / สัปดาห์ / เดือน / ปี → เลือกวัน → ดู/เพิ่ม/เลื่อน/ยกเลิกงาน
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with CalendarListener<CalendarPage> {
  @override
  String? get hiddenTab => 'ปฏิทิน';

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
    await judgeDays(repo); // ผ่านวันแล้วงานสำคัญไม่ครบ → สติกเกอร์ "พลาด" (กันรันถี่ในตัว)
    final day = _selected;
    final view = _view;
    final vis = _visibleDays;
    // ทั้งเดือนในรอบเดียว (เดิม 42 วัน = 42 รอบเขียน DB)
    final byDay = vis.isEmpty ? <DateTime, List<Occurrence>>{} : await repo.occurrencesBetween(vis.first, vis.last);
    final items = byDay[day] ?? await repo.occurrencesOn(day);
    final lifeBase = await repo.lifeBase();
    final cats = await repo.categories();
    final holidays = await repo.holidays();
    final style = await _settings?.getSetting('week_style');
    final days = _visibleDays.toList();
    final stuck = days.isEmpty ? const <DaySticker>[] : await repo.daySticker(days.first, days.last);
    if (!mounted || day != _selected || view != _view) return; // ผู้ใช้กดเปลี่ยนระหว่างโหลด
    setState(() {
      _items = items;
      _byDay = byDay;
      placedByDay = {};
      for (final d in stuck) {
        (placedByDay[d.day] ??= []).add(d);
      }
      // ⭐ ไฮไลต์มาก่อน (หัววันในสัปดาห์โชว์ชิ้นแรก)
      stickersByDay = {
        for (final e in placedByDay.entries)
          e.key: [highlightOf(e.value)!.sticker, ...e.value.where((d) => d != highlightOf(e.value)).map((d) => d.sticker)],
      };
      _lifeBase = lifeBase;
      _categories = {for (final c in cats) c.id: c};
      _holidays = {for (final h in holidays) dayKey(h.day): h.name};
      holidaysByDay = {for (final h in holidays) DateTime(h.day.year, h.day.month, h.day.day): h.name};
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
            // เดือน = หน้าสมุด (สติกเกอร์ใหญ่ · 🎓n ✎n · ⭐ 📝) · แตะวัน = รายการงานของวันนั้น + เพิ่มงาน
            CalView.month => wide
                ? [
                    _navRow(),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: _notebook(drag: true)),
                        const SizedBox(width: 24),
                        // ขวา: สมุดสติกเกอร์ (ลากไปแปะ) + งานของวันที่เลือก
                        Expanded(
                          flex: 2,
                          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                            StickerBook(onTapSticker: (s) {
                              if (importantPending(_byDay[_selected] ?? const [])) {
                                showToast(context, '🔒 ทำงานสำคัญของวันนั้นให้ครบก่อน แล้วค่อยแปะ');
                                return;
                              }
                              stickWithLimit(context, calendar!, _selected, s);
                            }),
                            const SizedBox(height: 12),
                            // สติกเกอร์ของวันที่เลือก: คลิกขวา = ⭐ ไฮไลต์ · โน้ต · ลอกออก
                            DayStickerCard(day: _selected),
                            const SizedBox(height: 12),
                            _agenda(today),
                          ]),
                        ),
                      ],
                    ),
                  ]
                : [
                    _navRow(),
                    const SizedBox(height: 24),
                    _notebook(),
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

  Widget _notebook({bool drag = false}) => NotebookMonth(
        month: _selected,
        days: monthGridDays(_selected),
        byDay: _byDay,
        stickers: stickersByDay,
        holidays: _holidays,
        selected: _selected,
        onTapDay: (d) => _go(day: d),
        onOpenDay: (d) => _go(day: d, view: CalView.day),
        onOpenWeek: (monday) => _go(day: monday, view: CalView.week),
        placed: placedByDay,
        categories: _categories,
        onDropSticker: !drag ? null : (d, st, x, y) => stickWithLimit(context, calendar!, d, st, x: x, y: y),
        // งานสำคัญยังไม่ครบ → ยังแปะไม่ได้ (ทำครบแล้วปลดล็อก)
        dropLocked: (d) => importantPending(_byDay[d] ?? const []) ? 'ทำงานสำคัญให้ครบก่อน' : null,
      );

  /// ◀ ชื่อช่วง ▶ (แตะชื่อ = ซูมออก) · มุมมองเดือน: ลูกศรบอกชื่อเดือนก่อน / ถัดไป
  Widget _navRow() {
    if (_view == CalView.month) {
      final prev = addMonths(_selected, -1), next = addMonths(_selected, 1);
      return Row(children: [
        TextButton.icon(
          onPressed: () => _step(-1),
          icon: const Icon(Icons.chevron_left),
          label: Text(thaiMonthsShort[prev.month - 1]),
        ),
        Expanded(
          child: TextButton(
            onPressed: _zoomOut,
            style: TextButton.styleFrom(foregroundColor: context.noir.text),
            child: Text(_title, textAlign: TextAlign.center, style: const TextStyle(fontWeight: FontWeight.w600)),
          ),
        ),
        TextButton(
          onPressed: () => _step(1),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(thaiMonthsShort[next.month - 1]),
            const Icon(Icons.chevron_right),
          ]),
        ),
      ]);
    }
    return _navRowBasic();
  }

  Widget _navRowBasic() => Row(
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
    void onOcc(Occurrence o) => openOccurrence(context, calendar!, o);
    void onDay(DateTime d) => _go(day: d, view: CalView.day);

    // จอแคบ (มือถือ): แถบ 7 วันด้านบน + ไทม์ไลน์ของวันที่เลือก (เวลาซ้าย กิจกรรมต่อท้าย) · ปัดซ้าย/ขวา = เปลี่ยนวัน
    if (narrow) {
      void step(int dir) {
        final d = _selected.add(Duration(days: dir));
        if (_weekDays.contains(d)) {
          setState(() => _selected = d);
        } else {
          _go(day: d);
        }
      }

      return [
        _navRow(),
        const SizedBox(height: 4),
        WeekDayStrip(
          days: _weekDays,
          byDay: _byDay,
          selected: _selected,
          today: today,
          onPick: (d) => setState(() => _selected = d),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragEnd: (e) {
            final v = e.primaryVelocity ?? 0;
            if (v.abs() > 200) step(v < 0 ? 1 : -1);
          },
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  '${thaiShortDate(_selected)} · ทำแล้ว ${dayProgress(_byDay[_selected] ?? const []).$1}/'
                  '${dayProgress(_byDay[_selected] ?? const []).$2}',
                  style: TextStyle(color: c.muted, fontSize: 13),
                ),
                _actions(today),
              ],
            ),
            const SizedBox(height: 8),
            DayAgenda(
              items: _byDay[_selected] ?? const [],
              categories: _categories,
              lifeBase: _lifeBase[_selected.weekday - 1],
              onTap: onOcc,
            ),
          ]),
        ),
      ];
    }
    final style = _weekStyle;

    return [
      _navRow(),
      const SizedBox(height: 8),
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [_actions(today)],
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
