/// หน้า "ตารางเวลาชน": รวมทุกคู่ที่เวลาทับกัน แล้วแก้วัน/เวลาได้ในที่เดียว
library;

import 'package:flutter/material.dart';

import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'calendar_flows.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';

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
      appBar: AppBar(title: const Text('ตารางเวลาชน')),
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

/// กล่องแก้ด่วน: วัน (หรือวันในสัปดาห์) · เวลาเริ่ม/จบ · ปุ่มเลื่อน ±30 นาที
Future<void> _quickEdit(BuildContext context, CalendarRepository repo, Occurrence o) async {
  final act = await repo.activity(o.activityId);
  final d = act.toDraft();
  if (!context.mounted) return;
  if (d.repeat == RepeatKind.dates) {
    // เลือกวันเอง: แก้ทีละวันในฟอร์มเต็ม
    await editActivityFlow(context, repo, act.id);
    return;
  }
  var start = minuteOf(o.startAt!);
  var minutes = o.endAt!.difference(o.startAt!).inMinutes;
  var weekdays = {...d.weekdays};
  var day = dayOnly(d.repeat == RepeatKind.none ? o.day : d.day);

  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        Widget nudge(String label, int delta) => ActionChip(
              label: Text(label),
              onPressed: () => setLocal(() => start = (start + delta) % (24 * 60)),
            );
        return AlertDialog(
          title: Text('ย้าย "${o.title}"'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (d.repeat == RepeatKind.weekly) ...[
                    const Text('วันในสัปดาห์'),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      for (var w = 1; w <= 7; w++)
                        FilterChip(
                          label: Text(thaiWeekdayShort[w - 1]),
                          selected: weekdays.contains(w),
                          onSelected: (on) => setLocal(() {
                            weekdays = on ? {...weekdays, w} : ({...weekdays}..remove(w));
                          }),
                        ),
                    ]),
                  ] else if (d.repeat == RepeatKind.none)
                    PickerTile(
                      icon: Icons.event,
                      label: 'วันที่',
                      value: thaiShortDate(day),
                      onTap: () async {
                        final p = await pickDay(ctx, day);
                        if (p != null) setLocal(() => day = dayOnly(p));
                      },
                    ),
                  const SizedBox(height: 8),
                  PickerTile(
                    icon: Icons.schedule,
                    label: 'เวลาเริ่มกิจกรรม',
                    value: fmtMinute(start),
                    onTap: () async {
                      final m = await pickMinute(ctx, start, title: 'เวลาเริ่มกิจกรรม');
                      if (m != null) setLocal(() => start = m);
                    },
                  ),
                  PickerTile(
                    icon: Icons.flag_outlined,
                    label: 'เวลาจบกิจกรรม',
                    value: fmtMinute(start + minutes),
                    onTap: () async {
                      final m = await pickMinute(ctx, (start + minutes) % (24 * 60),
                          title: 'เวลาจบกิจกรรม (เริ่ม ${fmtMinute(start)})');
                      if (m != null) setLocal(() => minutes = durationBetween(start, m));
                    },
                  ),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    nudge('−1 ชม.', -60),
                    nudge('−30 นาที', -30),
                    nudge('+30 นาที', 30),
                    nudge('+1 ชม.', 60),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    'ใหม่: ${rangeText(start, minutes)} · ${durationText(minutes)}'
                    '${d.repeat == RepeatKind.weekly ? ' · มีผลตั้งแต่วันนี้ ครั้งที่ทำแล้วไม่เปลี่ยน' : ''}',
                    style: TextStyle(fontSize: 13, color: ctx.noir.muted),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: d.repeat == RepeatKind.weekly && weekdays.isEmpty
                  ? null
                  : () => Navigator.pop(ctx, true),
              child: const Text('บันทึก'),
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
      day: d.repeat == RepeatKind.none ? day : d.day,
      startMinute: start,
      durationMin: minutes,
      repeat: d.repeat,
      weekdays: weekdays,
      endDate: d.endDate,
      presetId: d.presetId,
      dates: d.dates,
      subjectId: d.subjectId,
    ),
  );
}
