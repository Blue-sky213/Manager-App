import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calendar/achievements.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/lookback.dart';
import '../calendar/stickers.dart' show DaySticker;
import 'lookback_card.dart';
import '../data/study_scope.dart';
import '../study/tutor_plan.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_segments.dart';
import '../widgets/page_scaffold.dart';

/// หน้า "สถิติ": วงกลมภาพรวม · กราฟรายวัน 4 สัปดาห์ · แถบ % แยกกิจกรรม / วิชา · Streak · เหรียญ
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

/// ช่วงที่ดู
enum _Range { week, month, m3, m6, m9, m12 }

const _rangeLabel = {
  _Range.week: 'สัปดาห์',
  _Range.month: 'เดือน',
  _Range.m3: '3 ด.',
  _Range.m6: '6 ด.',
  _Range.m9: '9 ด.',
  _Range.m12: '1 ปี',
};

class _StatsPageState extends State<StatsPage> with CalendarListener<StatsPage> {
  _Range _rangeSel = _Range.week;
  Map<DateTime, List<Occurrence>> _days = {};
  Map<int, String> _catNames = {};
  Map<int, String> _subjectNames = {};
  StreakInfo? _streak;
  List<MedalTrack> _medals = [];
  bool _loaded = false;

  // สถิติย้อนหลัง (O): เช็กอินเช้า · สติกเกอร์ (พลาด / เสร็จย้อนหลัง / อารมณ์) · หมวด (ไอคอน)
  Map<DateTime, Checkin> _checkins = {};
  Map<DateTime, List<DaySticker>> _stickers = {};
  Map<int, ActivityCategory> _cats = {};

  DateTime get _today => dayOnly(DateTime.now());

  @override
  Future<void> reload() async {
    final repo = calendar!;
    final study = StudyScope.of(context);
    final today = _today;
    // 1 ปีย้อนหลัง (+ เผื่อเทียบช่วงก่อน) · ใช้ทั้งกราฟ · Streak · เหรียญ
    final days = <DateTime, List<Occurrence>>{};
    for (var i = 0; i < 372; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      days[d] = await repo.occurrencesOn(d);
    }
    // หมวดที่ตั้ง "นับในสถิติเป็น" → ใช้ชื่อกลุ่มนั้นแทนชื่อหมวด (v17)
    final groupNames = {for (final (k, n) in statsGroups) k: n};
    final cats = {
      for (final c in await repo.categories()) c.id: (c.statsGroup == null || c.statsGroup == 'other') ? c.name : groupNames[c.statsGroup]!,
    };
    final subjects = await study.subjects();
    var understood = 0;
    for (final s in subjects) {
      final topics = [for (final ch in await study.chapters(s.id)) ...ch.subtopics];
      if (topics.isNotEmpty && topics.every((t) => (t.latestScore ?? 0) >= 80)) understood++;
    }
    final streak = streakOf(days, today);
    final from = today.subtract(const Duration(days: 371));
    final checkins = {for (final c in await repo.checkins(from, today.add(const Duration(days: 1)))) dayOnly(c.day): c};
    final stuck = <DateTime, List<DaySticker>>{};
    for (final d in await repo.daySticker(from, today)) {
      (stuck[d.day] ??= []).add(d);
    }
    final fullCats = {for (final c in await repo.categories()) c.id: c};
    if (!mounted) return;
    setState(() {
      _days = days;
      _catNames = cats;
      _subjectNames = {for (final s in subjects) s.id: s.name};
      _streak = streak;
      _medals = medalTracks(days, today, understoodSubjects: understood);
      _checkins = checkins;
      _stickers = stuck;
      _cats = fullCats;
      _loaded = true;
    });
  }

  /// % รายเดือนในช่วง (เดือนแรกนับเฉพาะวันที่อยู่ในช่วง)
  List<(DateTime, double?)> _monthly(DateTime from, DateTime to) {
    final out = <(DateTime, double?)>[];
    for (var m = DateTime(from.year, from.month); !m.isAfter(to); m = DateTime(m.year, m.month + 1)) {
      final end = DateTime(m.year, m.month + 1, 0);
      out.add((m, percentDone(_range(m.isBefore(from) ? from : m, end.isAfter(to) ? to : end))));
    }
    return out;
  }

  /// งานในช่วง [from, to] (รวมทั้งสองวัน)
  List<Occurrence> _range(DateTime from, DateTime to) => [
        for (final e in _days.entries)
          if (!e.key.isBefore(from) && !e.key.isAfter(to)) ...e.value,
      ];

  DateTime _from(DateTime today) => switch (_rangeSel) {
        _Range.week => mondayOf(today),
        _Range.month => today.subtract(const Duration(days: 29)),
        _Range.m3 => today.subtract(const Duration(days: 90)),
        _Range.m6 => today.subtract(const Duration(days: 181)),
        _Range.m9 => today.subtract(const Duration(days: 272)),
        _Range.m12 => today.subtract(const Duration(days: 364)),
      };

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final today = _today;
    // ช่วงนี้ vs ช่วงก่อน (สัปดาห์: จันทร์นี้ → วันนี้ · เดือน: 28 วันล่าสุด)
    if (!_loaded) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    final from = _from(today);
    final len = today.difference(from).inDays + 1;
    final long = len > 40;
    final now = _range(from, today);
    final prevTo = from.subtract(const Duration(days: 1));
    final prevFrom = prevTo.subtract(Duration(days: _rangeSel == _Range.week ? 6 : len - 1));
    final before = _range(prevFrom, prevTo);
    final p = percentDone(now);
    // ช่วงก่อนไม่มีข้อมูลครบ (12 เดือน) → ไม่เทียบ
    final pPrev = _rangeSel == _Range.m12 ? null : percentDone(before);
    final (done, total) = dayProgress(now);
    final groups = groupPercents(now, before, (o) => activityGroup(o, _catNames));
    final bySubject = groupPercents(
      now.where((o) => o.subjectId != null).toList(),
      before.where((o) => o.subjectId != null).toList(),
      (o) => _subjectNames[o.subjectId] ?? 'วิชาอื่น',
    );
    final series = [
      for (var i = 27; i >= 0; i--)
        percentDone(_days[DateTime(today.year, today.month, today.day - i)] ?? const []),
    ];

    Widget card(Widget child) => Card(child: Padding(padding: const EdgeInsets.all(16), child: child));
    Text label(String t) => Text(t, style: TextStyle(fontSize: 13, color: c.muted));

    return PageScaffold(
      overline: 'Stats',
      title: 'สถิติ',
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: MiniSegments<_Range>(
              value: _rangeSel,
              items: [for (final r in _Range.values) (r, _rangeLabel[r]!)],
              onChanged: (r) => setState(() => _rangeSel = r),
            ),
          ),
        ),
        const SizedBox(height: 12),
        // ---- วงกลมภาพรวม ----
        card(Row(children: [
          SizedBox(
            width: 104,
            height: 104,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox(
                width: 104,
                height: 104,
                child: CircularProgressIndicator(
                  value: (p ?? 0) / 100,
                  strokeWidth: 10,
                  strokeCap: StrokeCap.round,
                  backgroundColor: c.surface2,
                  color: _levelColor(c, p),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(p == null ? '—' : '${p.round()}%',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.text)),
                Text('ทำตามแผน', style: TextStyle(fontSize: 11, color: c.muted)),
              ]),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p == null ? 'ยังไม่มีงานในช่วงนี้' : levelMessage(p),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 4),
              Text('ทำแล้ว $done / $total งาน', style: TextStyle(fontSize: 13, color: c.muted)),
              if (p != null && pPrev != null)
                Text(
                  '${p >= pPrev ? '▲' : '▼'} ${(p - pPrev).abs().round()}% จากช่วงก่อนหน้า',
                  style: TextStyle(fontSize: 13, color: p >= pPrev ? c.good : c.warn),
                ),
              const SizedBox(height: 4),
              Text('🔥 Streak ${_streak?.current ?? 0} วัน · ดีที่สุด ${_streak?.best ?? 0}',
                  style: TextStyle(fontSize: 13, color: c.text)),
            ]),
          ),
        ])),
        const SizedBox(height: 12),
        // ---- O · สถิติย้อนหลัง: พลาดเพราะอะไร ----
        LookbackCard(
          lookback: analyzeLookback(
            days: {for (final e in _days.entries) if (!e.key.isBefore(from)) e.key: e.value},
            checkins: _checkins,
            stickers: _stickers,
            today: today,
          ),
          categories: _cats,
        ),
        const SizedBox(height: 12),
        // ---- กราฟรวม: ช่วงสั้น = รายวัน 28 วัน · ช่วงยาว = รายเดือน + ตารางสีรายวัน ----
        if (!long)
          card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ทำตามแผนรายวัน', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
            label('28 วัน · แท่งเขียว = ครบทั้งวัน · เส้น = เฉลี่ย 7 วัน'),
            const SizedBox(height: 10),
            SizedBox(height: 120, child: CustomPaint(painter: _TrendPainter(series, c))),
            const SizedBox(height: 4),
            Row(children: [
              label(thaiShortDate(today.subtract(const Duration(days: 27)))),
              const Spacer(),
              label('วันนี้'),
            ]),
          ]))
        else ...[
          card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ทำตามแผนรายเดือน', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
            label('ฟ้า ≥ 80% · เหลือง 50–79% · ส้ม < 50%'),
            const SizedBox(height: 10),
            _MonthBars(months: _monthly(from, today)),
          ])),
          const SizedBox(height: 12),
          card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('ทุกวันในช่วงนี้ · % ทำตามแผน', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
            label('เลื่อนข้างดูย้อนหลัง · แตะช่อง = ดูวันนั้น'),
            const SizedBox(height: 10),
            YearHeatmap(from: from, to: today, days: _days),
          ])),
        ],
        // ---- แยกตามกิจกรรม / วิชา ----
        card(_Bars(title: 'แยกตามกิจกรรม', rows: groups, hint: '┃ = เฉลี่ยช่วงก่อน')),
        if (bySubject.isNotEmpty) ...[
          const SizedBox(height: 12),
          card(_Bars(title: 'แยกตามวิชา (เรียน + ติว)', rows: bySubject)),
        ],
        const SizedBox(height: 12),
        // ---- เหรียญ 3 ขั้น ----
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('เหรียญ', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          label('ทองแดง → เงิน → ทอง · ต้องทำต่อเนื่องจริงถึงได้'),
          const SizedBox(height: 10),
          for (final m in _medals) _MedalRow(m),
        ])),
      ],
    );
  }
}

/// สีตามระดับ: ≥ 80 ฟ้า · 50–79 เหลือง · < 50 ส้ม (ไม่ใช้แดง ไม่ตำหนิ)
Color _levelColor(NoirColors c, double? p) =>
    p == null ? c.line2 : (p >= 80 ? c.accent : (p >= 50 ? c.warn : Color.lerp(c.warn, c.bad, 0.5)!));

/// แถบ % ต่อกลุ่ม + ขีดค่าเฉลี่ยช่วงก่อน
class _Bars extends StatelessWidget {
  const _Bars({required this.title, required this.rows, this.hint});
  final String title;
  final List<(String, double, double?)> rows;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
      if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: c.muted)),
      const SizedBox(height: 10),
      if (rows.isEmpty) Text('ยังไม่มีงานในช่วงนี้', style: TextStyle(fontSize: 13, color: c.muted)),
      for (final (name, v, avg) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(
              width: 96,
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.text)),
            ),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                return SizedBox(
                  height: 12,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(6))),
                    Container(
                      width: box.maxWidth * v / 100,
                      decoration: BoxDecoration(color: _levelColor(c, v), borderRadius: BorderRadius.circular(6)),
                    ),
                    if (avg != null)
                      Positioned(
                        left: (box.maxWidth * avg / 100 - 1).clamp(0, box.maxWidth - 2),
                        top: -3,
                        bottom: -3,
                        child: Container(width: 2, color: c.text.withValues(alpha: 0.55)),
                      ),
                  ]),
                );
              }),
            ),
            SizedBox(
              width: 48,
              child: Text('${v.round()}%',
                  textAlign: TextAlign.right,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
            ),
          ]),
        ),
    ]);
  }
}

/// กราฟแท่งรายวัน (% ทำตามแผน) + เส้นค่าเฉลี่ย 7 วัน · วันที่ไม่มีงาน = ไม่มีแท่ง
class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.c);
  final List<double?> values;
  final NoirColors c;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = c.line
      ..strokeWidth = 1;
    for (final y in [0, 50, 100]) {
      final yy = size.height - y / 100 * size.height;
      canvas.drawLine(Offset(0, yy), Offset(size.width, yy), grid);
    }
    final n = values.length;
    final bw = size.width / n;
    for (var i = 0; i < n; i++) {
      final v = values[i];
      if (v == null) continue;
      final h = math.max(2.0, v / 100 * size.height);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(i * bw + 1.5, size.height - h, bw - 3, h), const Radius.circular(2)),
        Paint()..color = v >= 100 ? c.good : c.accent.withValues(alpha: 0.45),
      );
    }
    final path = Path();
    var started = false;
    for (var i = 6; i < n; i++) {
      final win = values.sublist(i - 6, i + 1).whereType<double>().toList();
      if (win.isEmpty) continue;
      final avg = win.reduce((a, b) => a + b) / win.length;
      final pt = Offset(i * bw + bw / 2, size.height - avg / 100 * size.height);
      if (started) {
        path.lineTo(pt.dx, pt.dy);
      } else {
        path.moveTo(pt.dx, pt.dy);
        started = true;
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = c.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) => true;
}

/// แท่งรายเดือน (สีตามระดับ) + ชื่อเดือนย่อ
class _MonthBars extends StatelessWidget {
  const _MonthBars({required this.months});
  final List<(DateTime, double?)> months;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return SizedBox(
      height: 150,
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final (m, p) in months)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(p == null ? '' : '${p.round()}', style: TextStyle(fontSize: 10, color: c.muted)),
                const SizedBox(height: 2),
                Container(
                  height: 100 * (p ?? 0) / 100,
                  decoration: BoxDecoration(color: _levelColor(c, p), borderRadius: BorderRadius.circular(4)),
                ),
                const SizedBox(height: 4),
                Text(thaiMonthsShort[m.month - 1],
                    maxLines: 1, overflow: TextOverflow.clip, style: TextStyle(fontSize: 10, color: c.muted)),
              ]),
            ),
          ),
      ]),
    );
  }
}

/// ตารางสีรายวัน (คอลัมน์ = สัปดาห์ · แถว = จันทร์ → อาทิตย์) · ชื่อเดือนด้านบน · วันในสัปดาห์ด้านซ้าย (ไม่เลื่อนตาม)
/// เปิดมาที่ช่วงล่าสุด · แตะช่อง = แถบบอกวันนั้นทำไปกี่งาน
class YearHeatmap extends StatelessWidget {
  const YearHeatmap({super.key, required this.from, required this.to, required this.days});
  final DateTime from;
  final DateTime to;
  final Map<DateTime, List<Occurrence>> days;

  static const _cell = 13.0;
  static const _gap = 3.0;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final start = mondayOf(from);
    final weeks = to.difference(start).inDays ~/ 7 + 1;
    Color colorOf(double? p) => p == null
        ? c.surface2
        : p >= 100
            ? c.good
            : p >= 80
                ? Color.alphaBlend(c.good.withValues(alpha: 0.6), c.surface)
                : p >= 50
                    ? Color.alphaBlend(c.good.withValues(alpha: 0.32), c.surface)
                    : Color.alphaBlend(c.good.withValues(alpha: 0.12), c.surface);

    final labels = Column(children: [
      const SizedBox(height: 16),
      for (final (i, w) in const ['จ', '', 'พ', '', 'ศ', '', 'อา'].indexed)
        SizedBox(
          height: _cell + (i < 6 ? _gap : 0),
          width: 22,
          child: Text(w, style: TextStyle(fontSize: 10, color: c.muted)),
        ),
    ]);

    String? monthAt(int w) {
      final d = start.add(Duration(days: w * 7));
      final prev = start.add(Duration(days: (w - 1) * 7));
      return w == 0 || d.month != prev.month ? thaiMonthsShort[d.month - 1] : null;
    }

    final grid = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(
        height: 16,
        child: Stack(clipBehavior: Clip.none, children: [
          for (var w = 0; w < weeks; w++)
            if (monthAt(w) case final m?)
              Positioned(
                left: w * (_cell + _gap),
                child: Text(m, style: TextStyle(fontSize: 10, color: c.muted)),
              ),
          SizedBox(width: weeks * (_cell + _gap)),
        ]),
      ),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        for (var w = 0; w < weeks; w++)
          Padding(
            padding: const EdgeInsets.only(right: _gap),
            child: Column(children: [
              for (var i = 0; i < 7; i++)
                Builder(builder: (context) {
                  final d = start.add(Duration(days: w * 7 + i));
                  final inRange = !d.isBefore(from) && !d.isAfter(to);
                  final items = days[d] ?? const <Occurrence>[];
                  final (done, total) = dayProgress(items);
                  return Padding(
                    padding: EdgeInsets.only(bottom: i < 6 ? _gap : 0),
                    child: GestureDetector(
                      onTap: !inRange
                          ? null
                          : () => ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
                                content: Text(total == 0
                                    ? '${thaiShortDate(d)} · ไม่มีงาน'
                                    : '${thaiShortDate(d)} · ทำแล้ว $done/$total'),
                                duration: const Duration(seconds: 2),
                              )),
                      child: Container(
                        width: _cell,
                        height: _cell,
                        decoration: BoxDecoration(
                          color: inRange ? colorOf(percentDone(items)) : Colors.transparent,
                          borderRadius: BorderRadius.circular(3),
                          border: d == to ? Border.all(color: c.text, width: 1.5) : null,
                        ),
                      ),
                    ),
                  );
                }),
            ]),
          ),
      ]),
    ]);

    Widget key(Color col) => Container(
        width: 11, height: 11, margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(color: col, borderRadius: BorderRadius.circular(2)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        labels,
        Expanded(child: SingleChildScrollView(scrollDirection: Axis.horizontal, reverse: true, child: grid)),
      ]),
      const SizedBox(height: 8),
      Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 4, runSpacing: 4, children: [
        Text('ไม่มีงาน', style: TextStyle(fontSize: 11, color: c.muted)),
        key(colorOf(null)),
        const SizedBox(width: 8),
        Text('น้อย', style: TextStyle(fontSize: 11, color: c.muted)),
        key(colorOf(30)),
        key(colorOf(60)),
        key(colorOf(85)),
        key(colorOf(100)),
        Text('ครบ · กรอบ = วันนี้', style: TextStyle(fontSize: 11, color: c.muted)),
      ]),
    ]);
  }
}

/// เหรียญ 1 แถว: วงขั้น (ทองแดง / เงิน / ทอง) · แถบไปขั้นถัดไป
class _MedalRow extends StatelessWidget {
  const _MedalRow(this.m);
  final MedalTrack m;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    const tiers = ['—', 'ทองแดง', 'เงิน', 'ทอง'];
    const colors = [null, Color(0xFFC98A5A), Color(0xFFB8C0C8), Color(0xFFE3B52C)];
    final next = m.next;
    final col = colors[m.level];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: col ?? c.surface2,
          foregroundColor: col == null ? c.muted : const Color(0xFF1B1B1B),
          child: Text(const ['—', 'ทด', 'เงิน', 'ทอง'][m.level],
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                child: Text('${m.name}${m.level > 0 ? ' · ${tiers[m.level]}' : ''}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
              ),
              Text(next == null ? 'ครบทุกขั้น' : '${next.$1} / ${next.$2} ${m.unit}',
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: next == null ? 1 : (next.$1 / next.$2).clamp(0, 1).toDouble(),
                minHeight: 6,
                backgroundColor: c.surface2,
                color: next == null ? colors[3] : c.accent,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              next == null ? m.desc : '${m.desc} · ขั้นถัดไป ${tiers[m.level + 1]}',
              style: TextStyle(fontSize: 11, color: c.muted),
            ),
          ]),
        ),
      ]),
    );
  }
}
