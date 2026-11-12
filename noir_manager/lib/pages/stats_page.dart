import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calendar/achievements.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../data/study_scope.dart';
import '../study/tutor_plan.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/page_scaffold.dart';

/// หน้า "สถิติ": วงกลมภาพรวม · กราฟรายวัน 4 สัปดาห์ · แถบ % แยกกิจกรรม / วิชา · Streak · เหรียญ
class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

/// เหรียญ 1 อัน · [done] = ได้แล้ว (ยังไม่ได้ = จาง)
class _Badge {
  const _Badge(this.mark, this.title, this.detail, {this.done = true});
  final String mark;
  final String title;
  final String detail;
  final bool done;
}

class _StatsPageState extends State<StatsPage> with CalendarListener<StatsPage> {
  bool _month = false;
  Map<DateTime, List<Occurrence>> _days = {};
  Map<int, String> _catNames = {};
  Map<int, String> _subjectNames = {};
  StreakInfo? _streak;
  List<_Badge> _badges = [];

  DateTime get _today => dayOnly(DateTime.now());

  @override
  Future<void> reload() async {
    final repo = calendar!;
    final study = StudyScope.of(context);
    final today = _today;
    // 63 วันย้อนหลัง: กราฟ 28 วัน + ช่วงก่อนหน้าไว้เทียบค่าเฉลี่ย + Streak
    final days = <DateTime, List<Occurrence>>{};
    for (var i = 0; i < 63; i++) {
      final d = DateTime(today.year, today.month, today.day - i);
      days[d] = await repo.occurrencesOn(d);
    }
    final cats = {for (final c in await repo.categories()) c.id: c.name};
    final subjects = await study.subjects();
    final pass = int.tryParse(await study.getSetting(tutorPassKey) ?? '') ?? defaultTutorPass;
    final streak = streakOf(days, today);
    final badges = <_Badge>[];
    if (streak.completeDays.isNotEmpty) {
      badges.add(_Badge('✓', 'ครบทั้งวัน', thaiShortDate(streak.completeDays.first)));
    }
    for (final goal in [7, 30]) {
      badges.add(_Badge('$goal', 'Streak $goal วัน',
          streak.best >= goal ? 'ทำได้แล้ว' : 'อีก ${goal - streak.current} วัน',
          done: streak.best >= goal));
    }
    for (final s in subjects) {
      final logs = await study.classLogs(s.id);
      if (logs.isEmpty) continue;
      final finished = logs.where((l) => l.finished).length;
      if (finished > 0) badges.add(_Badge('บท', 'จบ $finished บท', s.name));
      final scope = tutorScope(await study.chapters(s.id), logs);
      if (scopePassed(scope, pass)) badges.add(_Badge('$pass', 'ทวนผ่าน $pass%', s.name));
    }
    if (!mounted) return;
    setState(() {
      _days = days;
      _catNames = cats;
      _subjectNames = {for (final s in subjects) s.id: s.name};
      _streak = streak;
      _badges = badges;
    });
  }

  /// งานในช่วง [from, to] (รวมทั้งสองวัน)
  List<Occurrence> _range(DateTime from, DateTime to) => [
        for (final e in _days.entries)
          if (!e.key.isBefore(from) && !e.key.isAfter(to)) ...e.value,
      ];

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final today = _today;
    // ช่วงนี้ vs ช่วงก่อน (สัปดาห์: จันทร์นี้ → วันนี้ · เดือน: 28 วันล่าสุด)
    final from = _month ? today.subtract(const Duration(days: 27)) : mondayOf(today);
    final now = _range(from, today);
    final prevTo = from.subtract(const Duration(days: 1));
    final before = _range(prevTo.subtract(const Duration(days: 27)), prevTo);
    final p = percentDone(now);
    final pPrev = percentDone(_range(from.subtract(Duration(days: _month ? 28 : 7)), prevTo));
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
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('สัปดาห์นี้')),
              ButtonSegment(value: true, label: Text('28 วัน')),
            ],
            selected: {_month},
            onSelectionChanged: (v) => setState(() => _month = v.first),
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
                  '${p >= pPrev ? '▲' : '▼'} ${(p - pPrev).abs().round()}% จาก${_month ? ' 28 วันก่อน' : 'สัปดาห์ก่อน'}',
                  style: TextStyle(fontSize: 13, color: p >= pPrev ? c.good : c.warn),
                ),
              const SizedBox(height: 4),
              Text('🔥 Streak ${_streak?.current ?? 0} วัน · ดีที่สุด ${_streak?.best ?? 0}',
                  style: TextStyle(fontSize: 13, color: c.text)),
            ]),
          ),
        ])),
        const SizedBox(height: 12),
        // ---- กราฟรวมรายวัน ----
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('ทำตามแผนรายวัน', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
            label('28 วัน · แท่งเขียว = ครบทั้งวัน · เส้น = เฉลี่ย 7 วัน'),
          ]),
          const SizedBox(height: 10),
          SizedBox(height: 120, child: CustomPaint(painter: _TrendPainter(series, c))),
          const SizedBox(height: 4),
          Row(children: [
            label(thaiShortDate(today.subtract(const Duration(days: 27)))),
            const Spacer(),
            label('วันนี้'),
          ]),
        ])),
        const SizedBox(height: 12),
        // ---- แยกตามกิจกรรม / วิชา ----
        card(_Bars(title: 'แยกตามกิจกรรม', rows: groups, hint: '┃ = เฉลี่ยช่วงก่อน')),
        if (bySubject.isNotEmpty) ...[
          const SizedBox(height: 12),
          card(_Bars(title: 'แยกตามวิชา (เรียน + ติว)', rows: bySubject)),
        ],
        const SizedBox(height: 12),
        // ---- เหรียญ ----
        card(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('เหรียญ', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 10),
          Wrap(spacing: 14, runSpacing: 12, children: [
            for (final b in _badges)
              Opacity(
                opacity: b.done ? 1 : 0.4,
                child: SizedBox(
                  width: 84,
                  child: Column(children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: b.done ? c.greenBg : c.surface2,
                      foregroundColor: b.done ? c.greenText : c.muted,
                      child: Text(b.mark, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(height: 4),
                    Text(b.title,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: c.text, fontWeight: FontWeight.w600)),
                    Text(b.detail,
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: c.muted)),
                  ]),
                ),
              ),
          ]),
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
      Row(children: [
        Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
        if (hint != null) Text(hint!, style: TextStyle(fontSize: 12, color: c.muted)),
      ]),
      const SizedBox(height: 10),
      if (rows.isEmpty) Text('ยังไม่มีงานในช่วงนี้', style: TextStyle(fontSize: 13, color: c.muted)),
      for (final (name, v, avg) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(children: [
            SizedBox(
              width: 120,
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
