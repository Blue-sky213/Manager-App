/// หน้า "เช็กเวลาชน": รวมทุกคู่ที่เวลาทับกัน แล้วแก้วัน/เวลาได้ในที่เดียว
library;

import 'package:flutter/material.dart';

import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'calendar_flows.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';
import 'free_slots.dart';

/// คู่งานที่ชนกัน (งานซ้ำที่ชนทุกสัปดาห์ รวมเป็นคู่เดียว)
class Clash {
  Clash(this.a, this.b);

  /// ตัวแทนครั้งแรกที่ชนของแต่ละฝั่ง
  final Occurrence a;
  final Occurrence b;
  final List<DateTime> days = [];

  String get key => clashKey(a.activityId, b.activityId);
}

String clashKey(int x, int y) => x < y ? '$x-$y' : '$y-$x';

/// หาทุกคู่ที่ชนกันในรายการรายวัน
List<Clash> findClashes(Map<DateTime, List<Occurrence>> byDay) {
  final pairs = <String, Clash>{};
  for (final day in byDay.keys.toList()..sort()) {
    final items = byDay[day]!
        .where((o) => o.status == OccurrenceStatus.planned && o.timed)
        .toList();
    for (var i = 0; i < items.length; i++) {
      for (var j = i + 1; j < items.length; j++) {
        final x = items[i], y = items[j];
        if (x.activityId == y.activityId) continue;
        if (!rangesOverlap(x.startAt!, x.endAt!, y.startAt!, y.endAt!)) continue;
        (pairs[clashKey(x.activityId, y.activityId)] ??= Clash(x, y)).days.add(day);
      }
    }
  }
  return pairs.values.toList()..sort((p, q) => p.days.first.compareTo(q.days.first));
}

Future<void> openClashPage(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const ClashPage()));

class ClashPage extends StatefulWidget {
  const ClashPage({super.key});

  @override
  State<ClashPage> createState() => _ClashPageState();
}

class _ClashPageState extends State<ClashPage> {
  static const _ignoredKey = 'clash_ignored';
  CalendarRepository? _repo;
  int _weeks = 4;
  bool _loading = true;
  bool _showIgnored = false;
  List<Clash> _clashes = [];
  Set<String> _ignored = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = CalendarScope.of(context);
    if (repo != _repo) {
      _repo?.removeListener(_load);
      _repo = repo..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final repo = _repo!;
    final settings = StudyScope.of(context);
    final start = dayOnly(DateTime.now());
    final weeks = _weeks;
    final byDay = <DateTime, List<Occurrence>>{};
    for (var i = 0; i < weeks * 7; i++) {
      final d = DateTime(start.year, start.month, start.day + i);
      byDay[d] = await repo.occurrencesOn(d);
    }
    final ignored = (await settings.getSetting(_ignoredKey) ?? '')
        .split(',')
        .where((k) => k.isNotEmpty)
        .toSet();
    if (!mounted || weeks != _weeks) return;
    setState(() {
      _clashes = findClashes(byDay);
      _ignored = ignored;
      _loading = false;
    });
  }

  Future<void> _setIgnored(Clash c, bool ignore) async {
    final next = {..._ignored};
    ignore ? next.add(c.key) : next.remove(c.key);
    setState(() => _ignored = next);
    await StudyScope.of(context).setSetting(_ignoredKey, next.join(','));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final open = _clashes.where((x) => !_ignored.contains(x.key)).toList();
    final ignored = _clashes.where((x) => _ignored.contains(x.key)).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('เช็กเวลาชน')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text('ดูล่วงหน้า', style: TextStyle(color: c.muted)),
                    for (final (w, label) in const [(1, '1 สัปดาห์'), (4, '4 สัปดาห์'), (13, 'ทั้งเทอม')])
                      ChoiceChip(
                        label: Text(label),
                        selected: _weeks == w,
                        onSelected: (_) {
                          setState(() {
                            _weeks = w;
                            _loading = true;
                          });
                          _load();
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                if (open.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Icon(Icons.check_circle_outline, size: 40, color: c.good),
                          const SizedBox(height: 8),
                          Text('ไม่มีเวลาชนในช่วงนี้',
                              style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                        ],
                      ),
                    ),
                  ),
                for (final x in open)
                  _ClashCard(clash: x, repo: _repo!, onIgnore: () => _setIgnored(x, true)),
                if (ignored.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () => setState(() => _showIgnored = !_showIgnored),
                    icon: Icon(_showIgnored ? Icons.expand_less : Icons.expand_more),
                    label: Text('ยอมทับไว้แล้ว ${ignored.length} คู่'),
                  ),
                  if (_showIgnored)
                    for (final x in ignored)
                      ListTile(
                        leading: const Icon(Icons.link),
                        title: Text('${x.a.title} ⟷ ${x.b.title}'),
                        trailing: TextButton(
                          onPressed: () => _setIgnored(x, false),
                          child: const Text('เตือนอีก'),
                        ),
                      ),
                ],
              ],
            ),
    );
  }
}

/// การ์ด 1 คู่ที่ชน: ช่วงที่ทับ + ปุ่มแก้ของแต่ละฝั่ง
class _ClashCard extends StatelessWidget {
  const _ClashCard({required this.clash, required this.repo, required this.onIgnore});

  final Clash clash;
  final CalendarRepository repo;
  final VoidCallback onIgnore;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final a = clash.a, b = clash.b;
    final from = a.startAt!.isAfter(b.startAt!) ? a.startAt! : b.startAt!;
    final to = a.endAt!.isBefore(b.endAt!) ? a.endAt! : b.endAt!;
    final days = clash.days;
    final when = days.length == 1
        ? thaiShortDate(days.first)
        : '${days.length} ครั้ง · ${thaiShortDate(days.first)} – ${thaiShortDate(days.last)}';

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: c.bad, width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: c.bad),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ทับกัน ${fmtTime(from)}–${fmtTime(to)} · $when',
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.bad),
                  ),
                ),
                TextButton(onPressed: onIgnore, child: const Text('ยอมทับ')),
              ],
            ),
            const SizedBox(height: 8),
            _Side(o: a, repo: repo),
            Divider(height: 16, color: c.line),
            _Side(o: b, repo: repo),
          ],
        ),
      ),
    );
  }
}

/// ฝั่งเดียวของคู่ที่ชน: ชื่อ · เวลา · ปุ่มแก้ด่วน
class _Side extends StatelessWidget {
  const _Side({required this.o, required this.repo});

  final Occurrence o;
  final CalendarRepository repo;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(o.title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
        Text(
          '${o.repeats ? 'ซ้ำ · ' : ''}${thaiWeekdayLong[o.day.weekday - 1]} '
          '${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)}',
          style: TextStyle(fontSize: 13, color: c.muted),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            FilledButton.tonalIcon(
              onPressed: () => _quickEdit(context, repo, o),
              icon: const Icon(Icons.edit_calendar_outlined, size: 18),
              label: Text(o.repeats ? 'ย้ายวัน/เวลา (ทุกครั้ง)' : 'ย้ายวัน/เวลา'),
            ),
            if (o.repeats)
              OutlinedButton(
                onPressed: () => editOccurrenceTimeFlow(context, repo, o),
                child: const Text('เฉพาะครั้งนี้'),
              ),
          ],
        ),
      ],
    );
  }
}

/// กล่อง "ย้ายวัน/เวลา" แบบ A + B:
/// A = ไทม์ไลน์ 7 วัน (เขียว = ว่างพอ · เทา = มีงาน · เส้นแดง = ตำแหน่งเดิม · น้ำเงิน = ที่เลือก)
/// B = ลิสต์ช่วงว่างแนะนำ เรียงจากใกล้เวลาเดิม · จอแคบเหลือแค่ลิสต์
Future<void> _quickEdit(BuildContext context, CalendarRepository repo, Occurrence o) async {
  final act = await repo.activity(o.activityId);
  final d = act.toDraft();
  if (!context.mounted) return;
  if (d.repeat == RepeatKind.dates || d.repeat == RepeatKind.daily) {
    // เลือกวันเอง / ทุกวัน: แก้ในฟอร์มเต็ม
    await editActivityFlow(context, repo, act.id);
    return;
  }
  final weekly = d.repeat == RepeatKind.weekly;
  final lifeBase = await repo.lifeBase();
  final today = dayOnly(DateTime.now());
  final monday = dayOnly(o.day).subtract(Duration(days: o.day.weekday - 1));

  // งานที่มีอยู่แล้วของแต่ละวัน (แถว = วันในสัปดาห์ 1–7) ไม่นับตัวที่กำลังย้าย
  // งานซ้ำ: รวม 4 สัปดาห์ข้างหน้า (ว่าง = ว่างทุกสัปดาห์) · ครั้งเดียว: สัปดาห์ของวันนั้น
  final busy = {for (var w = 1; w <= 7; w++) w: <Busy>[]};
  final days = weekly
      ? [for (var i = 0; i < 28; i++) DateTime(today.year, today.month, today.day + i)]
      : [for (var i = 0; i < 7; i++) DateTime(monday.year, monday.month, monday.day + i)];
  for (final day in days) {
    for (final x in await repo.occurrencesOn(day)) {
      if (x.activityId == o.activityId || !x.timed || !x.active) continue;
      final s = minuteOf(x.startAt!);
      final e = (s + x.endAt!.difference(x.startAt!).inMinutes).clamp(s, 24 * 60);
      final list = busy[day.weekday]!;
      if (!list.any((b) => b.start == s && b.end == e && b.title == x.title)) {
        list.add(Busy(s, e, x.title));
      }
    }
  }
  // ช่วงที่ใช้ได้ของแต่ละวัน = ตื่น → นอน (นอนหลังเที่ยงคืน = ถึง 24:00)
  (int, int) windowOf(int w) {
    final lb = lifeBase[w - 1];
    return (lb.wakeMinute, lb.bedMinute < 12 * 60 ? 24 * 60 : lb.bedMinute);
  }

  final gaps = {
    for (var w = 1; w <= 7; w++) w: freeGaps(busy[w]!, windowOf(w).$1, windowOf(w).$2),
  };
  final axisFrom = ([for (var w = 1; w <= 7; w++) windowOf(w).$1].reduce((a, b) => a < b ? a : b) ~/ 60) * 60;
  const axisTo = 24 * 60;

  final origRow = o.day.weekday;
  final origStart = minuteOf(o.startAt!);
  var row = origRow;
  var start = origStart;
  var minutes = o.endAt!.difference(o.startAt!).inMinutes;
  if (!context.mounted) return;

  String rowName(int w) => weekly
      ? thaiWeekdayShort[w - 1]
      : thaiShortDate(DateTime(monday.year, monday.month, monday.day + w - 1));

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final c = ctx.noir;
        final screen = MediaQuery.sizeOf(ctx).width;
        final wide = screen >= 720;
        final suggestions = suggestSlots(gaps, minutes, origStart, originalRow: origRow);
        final hits = clashesAt(busy[row]!, start, minutes);
        void pick(int w, int s) => setLocal(() {
              row = w;
              start = s;
            });

        Widget timelineRow(int w) => Row(
              children: [
                SizedBox(
                  width: 44,
                  child: Text(rowName(w),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: w == row ? FontWeight.w600 : FontWeight.w400,
                        color: w == row ? c.accent : c.muted,
                      )),
                ),
                Expanded(
                  child: LayoutBuilder(builder: (ctx, box) {
                    final ppm = box.maxWidth / (axisTo - axisFrom);
                    double x(int m) => (m - axisFrom) * ppm;
                    return SizedBox(
                      height: 32,
                      child: Stack(
                        children: [
                          for (final g in gaps[w]!)
                            Positioned(
                              left: x(g.start),
                              width: (g.length * ppm - 2).clamp(0.0, double.infinity),
                              top: 3,
                              bottom: 3,
                              child: GestureDetector(
                                onTapDown: g.length < minutes
                                    ? null
                                    : (t) {
                                        final at = g.start + (t.localPosition.dx / ppm).round();
                                        var s = ((at - minutes ~/ 2) ~/ 15) * 15;
                                        s = s.clamp(g.start, g.end - minutes);
                                        pick(w, s);
                                      },
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: g.length >= minutes ? c.greenBg : c.surface,
                                    borderRadius: BorderRadius.circular(5),
                                    border: Border.all(
                                        color: g.length >= minutes
                                            ? c.good.withValues(alpha: 0.5)
                                            : c.line),
                                  ),
                                ),
                              ),
                            ),
                          for (final b in busy[w]!)
                            Positioned(
                              left: x(b.start),
                              width: ((b.end - b.start) * ppm - 2).clamp(0.0, double.infinity),
                              top: 3,
                              bottom: 3,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4),
                                alignment: Alignment.centerLeft,
                                decoration: BoxDecoration(
                                  color: c.line2,
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                child: Text(b.title.replaceFirst('เรียน · ', ''),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(fontSize: 10, color: c.muted)),
                              ),
                            ),
                          if (w == origRow && !(w == row && start == origStart))
                            Positioned(
                              left: x(origStart),
                              width: minutes * ppm,
                              top: 5,
                              bottom: 5,
                              child: IgnorePointer(
                                child: Container(
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: c.bad, width: 1.5),
                                  ),
                                ),
                              ),
                            ),
                          if (w == row)
                            Positioned(
                              left: x(start),
                              width: minutes * ppm,
                              top: 1,
                              bottom: 1,
                              child: IgnorePointer(
                                child: Container(
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: hits.isEmpty ? c.accent : c.bad,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                  child: Text(rangeText(start, minutes),
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: c.onAccent)),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }),
                ),
              ],
            );

        return AlertDialog(
          title: Text('ย้าย "${o.title}"', maxLines: 2, overflow: TextOverflow.ellipsis),
          content: SizedBox(
            width: wide ? 900 : 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'ยาว ${durationText(minutes)} · เดิม ${rowName(origRow)} ${rangeText(origStart, minutes)}'
                    '${weekly ? ' · ดูช่วงว่างจาก 4 สัปดาห์ข้างหน้า' : ''}',
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                  // ----- A: ไทม์ไลน์ 7 วัน (จอกว้าง) -----
                  if (wide) ...[
                    const SizedBox(height: 12),
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      _legend(c.greenBg, 'ว่าง ใส่ได้ (แตะเพื่อวาง)', border: c.good),
                      _legend(c.surface, 'ว่างแต่สั้นไป', border: c.line),
                      _legend(c.line2, 'มีงานแล้ว'),
                      _legend(Colors.transparent, 'ตำแหน่งเดิม', border: c.bad),
                      _legend(c.accent, 'ที่เลือก'),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Row(children: [
                            const SizedBox(width: 44),
                            Expanded(
                              child: LayoutBuilder(builder: (ctx, box) {
                                final ppm = box.maxWidth / (axisTo - axisFrom);
                                return SizedBox(
                                  height: 14,
                                  child: Stack(children: [
                                    for (var h = axisFrom ~/ 60; h <= 23; h += 3)
                                      Positioned(
                                        left: (h * 60 - axisFrom) * ppm,
                                        child: Text(h.toString().padLeft(2, '0'),
                                            style: TextStyle(fontSize: 10, color: c.muted)),
                                      ),
                                  ]),
                                );
                              }),
                            ),
                          ]),
                          for (var w = 1; w <= 7; w++) timelineRow(w),
                        ],
                      ),
                    ),
                  ],
                  // ----- B: ลิสต์ช่วงว่างแนะนำ -----
                  const SizedBox(height: 12),
                  Text('ช่วงว่างแนะนำ', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                  const SizedBox(height: 6),
                  if (suggestions.isEmpty)
                    Text('ไม่มีช่วงว่างที่ยาวพอ ลองลดเวลา หรือเลือกเวลาเอง',
                        style: TextStyle(color: c.bad)),
                  for (final sg in suggestions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Material(
                        color: sg.row == row && sg.start == start ? c.navBg : c.surface,
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => pick(sg.row, sg.start),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: weekly ? 36 : 110,
                                  child: Text(rowName(sg.row),
                                      style: const TextStyle(fontWeight: FontWeight.w600)),
                                ),
                                Expanded(
                                  child: Text.rich(TextSpan(children: [
                                    TextSpan(
                                        text: rangeText(sg.start, minutes),
                                        style: const TextStyle(fontWeight: FontWeight.w600)),
                                    TextSpan(
                                      text: '${sg.start == origStart ? ' · เวลาเดิม' : ''}'
                                          ' · ว่าง ${fmtMinute(sg.gap.start)}–${fmtMinute(sg.gap.end)}',
                                      style: TextStyle(fontSize: 12, color: c.muted),
                                    ),
                                  ])),
                                ),
                                if (sg == suggestions.first)
                                  Text('แนะนำ', style: TextStyle(fontSize: 12, color: c.good)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                  // ----- ปรับละเอียด -----
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      OutlinedButton(
                        onPressed: () async {
                          final m = await pickMinute(ctx, start, title: 'เวลาเริ่มกิจกรรม');
                          if (m != null) setLocal(() => start = m);
                        },
                        child: Text('เริ่ม ${fmtMinute(start)}'),
                      ),
                      OutlinedButton(
                        onPressed: () async {
                          final m = await pickMinute(ctx, (start + minutes) % (24 * 60),
                              title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(start)})');
                          if (m != null) setLocal(() => minutes = durationBetween(start, m));
                        },
                        child: Text('จบ ${fmtMinute(start + minutes)}'),
                      ),
                      ActionChip(
                          label: const Text('−30 นาที'),
                          onPressed: () => setLocal(() => start = (start - 30) % (24 * 60))),
                      ActionChip(
                          label: const Text('+30 นาที'),
                          onPressed: () => setLocal(() => start = (start + 30) % (24 * 60))),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hits.isEmpty
                        ? '${rowName(row)} ${rangeText(start, minutes)} · ไม่ชนกับงานไหน'
                        : '⚠ ${rowName(row)} ${rangeText(start, minutes)} ชนกับ '
                            '${hits.map((b) => b.title.replaceFirst('เรียน · ', '')).join(', ')}',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: hits.isEmpty ? c.good : c.bad),
                  ),
                  if (weekly && d.weekdays.length > 1)
                    Text('เวลาใหม่ใช้กับทุกวันของงานนี้ (${d.weekdays.length} วัน/สัปดาห์)',
                        style: TextStyle(fontSize: 12, color: c.muted)),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('ย้ายไป ${rowName(row)} ${rangeText(start, minutes)}'),
            ),
          ],
        );
      },
    ),
  );
  if (ok != true) return;
  await repo.updateActivity(
    act.id,
    NewActivity(
      name: d.name,
      categoryId: d.categoryId,
      importance: d.importance,
      timed: true,
      day: weekly ? d.day : DateTime(monday.year, monday.month, monday.day + row - 1),
      startMinute: start,
      durationMin: minutes,
      repeat: d.repeat,
      weekdays: weekly ? ({...d.weekdays}..remove(origRow)..add(row)) : d.weekdays,
      endDate: d.endDate,
      presetId: d.presetId,
      dates: d.dates,
      subjectId: d.subjectId,
      kind: d.kind,
      classInfo: d.classInfo,
    ),
  );
}

Widget _legend(Color fill, String text, {Color? border}) => Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 10,
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(3),
              border: border == null ? null : Border.all(color: border),
            ),
          ),
          const SizedBox(width: 6),
          Text(text, style: TextStyle(fontSize: 12, color: context.noir.muted)),
        ],
      ),
    );
