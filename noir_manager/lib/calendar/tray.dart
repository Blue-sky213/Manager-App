/// ถาด "กำลังทำอยู่" (รอบ 15): โปรเจกต์ที่ทำอยู่ + งานรอวันใหม่ + ของที่ปักหมุด
/// ลากลงวัน หรือแตะ → แผ่นยืนยัน (ติ๊กวันเพิ่มได้ · เวลาเดิมจากครั้งล่าสุด · เตือนเวลาชนแต่ไม่บล็อก)
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import '../work/project_models.dart';
import 'calendar_listener.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart' show durationText, pickRange, thaiWeekdayShort;

enum TraySource { project, inbox, pin }

class TrayItem {
  const TrayItem({
    required this.title,
    required this.emoji,
    required this.source,
    this.occurrenceId,
    this.categoryId,
    this.startMinute,
    this.durationMin,
    this.sessions = 0,
    this.lastDay,
  });

  final String title;
  final String emoji;
  final TraySource source;

  /// งานรอวันใหม่ (inbox) → ย้ายครั้งนี้ลงวันแรกที่ติ๊ก
  final int? occurrenceId;
  final int? categoryId;

  /// เวลา/ความยาวจากครั้งล่าสุด · null = ยังไม่เคยลง
  final int? startMinute;
  final int? durationMin;

  /// ลงปฏิทินมาแล้วกี่ครั้ง (ช่วง 90 วันล่าสุด)
  final int sessions;
  final DateTime? lastDay;

  String get key => '${source.name}:${occurrenceId ?? title}';
}

const trayPinsKey = 'tray_pins';

/// ยังไม่เคยลง → เริ่ม 19:00 ยาว 1 ชม. (แก้ในแผ่นยืนยันได้)
const trayDefaultStart = 19 * 60;
const trayDefaultDuration = 60;

String _norm(String s) => s.trim().toLowerCase();

/// รวมถาด (pure): โปรเจกต์ "พร้อมเริ่ม / กำลังทำ" → งานรอวันใหม่ → ปักหมุด · ชื่อซ้ำโชว์ครั้งเดียว
List<TrayItem> buildTray({
  required List<Project> projects,
  required List<Occurrence> inbox,
  required List<String> pins,
  required Map<DateTime, List<Occurrence>> history,
  required DateTime now,
}) {
  // ครั้งล่าสุดของแต่ละชื่อ (ไม่นับที่ยกเลิก / เลื่อนออกไป)
  final last = <String, Occurrence>{};
  final count = <String, int>{};
  for (final list in history.values) {
    for (final o in list) {
      if (const {OccurrenceStatus.cancelled, OccurrenceStatus.moved, OccurrenceStatus.inbox}.contains(o.status)) continue;
      final k = _norm(o.title);
      count[k] = (count[k] ?? 0) + 1;
      final prev = last[k];
      final t = o.startAt ?? o.day;
      final pt = prev == null ? null : (prev.startAt ?? prev.day);
      // ชอบครั้งที่ผ่านมาแล้ว (เวลาเดิมจริง) มากกว่าครั้งที่ลงล่วงหน้า
      bool better() {
        if (pt == null) return true;
        final past = !t.isAfter(now), prevPast = !pt.isAfter(now);
        if (past != prevPast) return past;
        return past ? t.isAfter(pt) : t.isBefore(pt);
      }

      if (better()) last[k] = o;
    }
  }

  TrayItem fromTitle(String title, String emoji, TraySource src, {int? occId, int? cat}) {
    final o = last[_norm(title)];
    final timed = o != null && o.timed;
    return TrayItem(
      title: title,
      emoji: emoji,
      source: src,
      occurrenceId: occId,
      categoryId: cat ?? o?.categoryId,
      startMinute: timed ? o.startAt!.hour * 60 + o.startAt!.minute : null,
      durationMin: timed ? o.endAt!.difference(o.startAt!).inMinutes : null,
      sessions: count[_norm(title)] ?? 0,
      lastDay: o?.day,
    );
  }

  final out = <TrayItem>[];
  final seen = <String>{};
  void add(TrayItem t) {
    if (seen.add(_norm(t.title)) || t.source == TraySource.inbox) out.add(t);
  }

  for (final p in projects) {
    if (p.status != ProjectStatus.confirmed && p.status != ProjectStatus.doing) continue;
    add(fromTitle(p.name, projectType(p.type).$2, TraySource.project));
  }
  for (final o in inbox) {
    final base = fromTitle(o.title, '📥', TraySource.inbox, occId: o.id, cat: o.categoryId);
    // งานรอวันใหม่ใช้เวลาเดิมของตัวเองก่อน
    add(o.timed
        ? TrayItem(
            title: base.title,
            emoji: base.emoji,
            source: base.source,
            occurrenceId: o.id,
            categoryId: o.categoryId,
            startMinute: o.startAt!.hour * 60 + o.startAt!.minute,
            durationMin: o.endAt!.difference(o.startAt!).inMinutes,
            sessions: base.sessions,
            lastDay: base.lastDay,
          )
        : base);
  }
  for (final p in pins) {
    add(fromTitle(p, '📌', TraySource.pin));
  }
  return out;
}

List<String> decodePins(String? raw) {
  if (raw == null || raw.isEmpty) return [];
  try {
    return [for (final s in jsonDecode(raw) as List) s as String];
  } catch (_) {
    return [];
  }
}

/// วันที่เวลาช่วงนี้ชนกับงานอื่น → ชื่องานที่ชน (เตือนเฉย ๆ ไม่บล็อก)
Map<DateTime, List<String>> trayClashes(
    Map<DateTime, List<Occurrence>> byDay, Iterable<DateTime> days, int start, int duration) {
  final out = <DateTime, List<String>>{};
  for (final d in days) {
    final s = DateTime(d.year, d.month, d.day).add(Duration(minutes: start));
    final e = s.add(Duration(minutes: duration));
    final hits = [
      for (final o in byDay[d] ?? const <Occurrence>[])
        if (o.timed && o.active && o.startAt!.isBefore(e) && o.endAt!.isAfter(s)) o.title,
    ];
    if (hits.isNotEmpty) out[d] = hits;
  }
  return out;
}

/// ลงปฏิทินจริง → คืนฟังก์ชัน "เลิกทำ"
/// งานรอวันใหม่: วันแรก = ย้ายครั้งเดิม · วันที่เหลือ = งานใหม่ชื่อเดียวกัน
/// อื่น ๆ: งานใหม่ 1 ชุด (หลายวัน = ทำซ้ำแบบเลือกวันเอง) · เลิกทำ = ลบชุดนั้น
Future<Future<void> Function()> placeTrayItem(
    CalendarRepository repo, TrayItem item, Set<DateTime> days, int start, int duration) async {
  final sorted = days.map(dayOnly).toSet().toList()..sort();
  assert(sorted.isNotEmpty);
  int? movedId;
  var rest = sorted;
  if (item.source == TraySource.inbox && item.occurrenceId != null) {
    final d = sorted.first;
    final s = d.add(Duration(minutes: start));
    movedId = await repo.moveOccurrence(item.occurrenceId!, d, start: s, end: s.add(Duration(minutes: duration)));
    rest = sorted.sublist(1);
  }
  int? actId;
  if (rest.isNotEmpty) {
    actId = await repo.addActivity(NewActivity(
      name: item.title,
      categoryId: item.categoryId,
      importance: 2,
      timed: true,
      day: rest.first,
      startMinute: start,
      durationMin: duration,
      repeat: rest.length > 1 ? RepeatKind.dates : RepeatKind.none,
      dates: rest.length > 1 ? [for (final d in rest) ScheduledDate(d)] : const [],
    ));
  }
  return () async {
    if (actId != null) await repo.deleteActivity(actId);
    if (movedId != null) await repo.sendToInbox(movedId);
  };
}

// ---------- แผงถาด ----------

/// แผงถาด: [horizontal] = แถบเลื่อนข้าง (มือถือ / จอกลาง) · ไม่งั้นเป็นการ์ดแนวตั้ง (ข้างปฏิทิน)
class TrayPanel extends StatefulWidget {
  const TrayPanel({super.key, required this.selectedDay, this.horizontal = false});

  /// แตะการ์ด = เปิดแผ่นยืนยันที่วันนี้
  final DateTime selectedDay;
  final bool horizontal;

  @override
  State<TrayPanel> createState() => _TrayPanelState();
}

class _TrayPanelState extends State<TrayPanel> with CalendarListener<TrayPanel> {
  // อยู่ในหน้าปฏิทิน: ซ่อนอยู่ = ไม่โหลด 104 วันทุกครั้งที่ข้อมูลเปลี่ยน
  @override
  String? get hiddenTab => 'ปฏิทิน';

  List<TrayItem> _items = const [];
  List<String> _pins = const [];
  bool _loaded = false;
  ChangeNotifier? _work;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final w = calendar?.workRepo;
    if (w != null && w != _work) {
      _work?.removeListener(reload);
      _work = w..addListener(reload);
    }
  }

  @override
  void dispose() {
    _work?.removeListener(reload);
    super.dispose();
  }

  @override
  Future<void> reload() async {
    final repo = calendar;
    if (repo == null) return;
    final now = DateTime.now();
    final today = dayOnly(now);
    final projects = await repo.workRepo.projects();
    final inbox = await repo.inbox();
    final pins = decodePins(await repo.getSetting(trayPinsKey));
    final history = await repo.occurrencesBetween(today.subtract(const Duration(days: 90)), today.add(const Duration(days: 14)));
    if (!mounted) return;
    setState(() {
      _pins = pins;
      _items = buildTray(projects: projects, inbox: inbox, pins: pins, history: history, now: now);
      _loaded = true;
    });
  }

  Future<void> _savePins(List<String> pins) async {
    await calendar!.setSetting(trayPinsKey, jsonEncode(pins));
    await reload();
  }

  Future<void> _addPin() async {
    final ctl = TextEditingController();
    final name = await showMiniForm<String>(
      context,
      (ctx) => MiniForm(
        title: 'ปักหมุดลงถาด',
        primaryLabel: 'ปักหมุด',
        onPrimary: () => Navigator.pop(ctx, ctl.text.trim()),
        children: [
          MiniBigField(
            key: const Key('tray-pin-name'),
            controller: ctl,
            hint: 'เช่น ไลฟ์ RE4 · อ่านหนังสือ',
            autofocus: true,
            onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty || !mounted) return;
    if (_pins.any((p) => _norm(p) == _norm(name))) return showToast(context, 'มีในถาดแล้ว');
    await _savePins([..._pins, name]);
  }

  Future<void> _unpin(TrayItem t) => _savePins([for (final p in _pins) if (_norm(p) != _norm(t.title)) p]);

  void _open(TrayItem t) => openTraySheet(context, t, day: widget.selectedDay);

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (!_loaded) return const SizedBox.shrink();
    final addBtn = IconButton(
      key: const Key('tray-add-pin'),
      tooltip: 'ปักหมุดของที่ทำบ่อย',
      visualDensity: VisualDensity.compact,
      onPressed: _addPin,
      icon: Icon(Icons.push_pin_outlined, size: 18, color: c.muted),
    );
    if (widget.horizontal) {
      return SizedBox(
        key: const Key('tray-strip'),
        height: 44,
        child: Row(children: [
          Text('ถาด', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(width: 6),
          Expanded(
            child: _items.isEmpty
                ? Text('ยังว่าง · ปักหมุดของที่ทำบ่อยได้', style: TextStyle(fontSize: 12, color: c.muted))
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _items.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 6),
                    itemBuilder: (_, i) => Center(child: _chip(_items[i])),
                  ),
          ),
          addBtn,
        ]),
      );
    }
    return Card(
      key: const Key('tray-panel'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 6, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('กำลังทำอยู่', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
            addBtn,
          ]),
          Text('ลากลงวัน หรือแตะเพื่อเลือกวัน', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 8),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text('ยังว่าง · โปรเจกต์ "กำลังทำ" งานที่เลื่อนรอวันใหม่ และของที่ปักหมุด จะมาอยู่ตรงนี้',
                  style: TextStyle(fontSize: 12.5, color: c.muted)),
            ),
          for (final t in _items) Padding(padding: const EdgeInsets.only(bottom: 6, right: 6), child: _tile(t)),
        ]),
      ),
    );
  }

  String _sub(TrayItem t) {
    final parts = <String>[
      if (t.source == TraySource.inbox) 'รอวันใหม่',
      if (t.startMinute != null) '${fmtMinute(t.startMinute!)} · ${durationText(t.durationMin ?? trayDefaultDuration)}',
      if (t.source != TraySource.inbox) t.sessions == 0 ? 'ยังไม่เคยลง' : 'ครั้งที่ ${t.sessions + 1}',
    ];
    return parts.join(' · ');
  }

  Widget _tile(TrayItem t) {
    final c = context.noir;
    final body = Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        key: ValueKey('tray-${t.key}'),
        borderRadius: BorderRadius.circular(10),
        onTap: () => _open(t),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
          child: Row(children: [
            Icon(Icons.drag_indicator, size: 16, color: c.muted),
            const SizedBox(width: 4),
            Text(t.emoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                Text(_sub(t), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.5, color: c.muted)),
              ]),
            ),
            if (t.source == TraySource.pin)
              IconButton(
                tooltip: 'เอาออกจากถาด',
                visualDensity: VisualDensity.compact,
                onPressed: () => _unpin(t),
                icon: Icon(Icons.close, size: 16, color: c.muted),
              ),
          ]),
        ),
      ),
    );
    return Draggable<TrayItem>(
      data: t,
      feedback: _feedback(t),
      childWhenDragging: Opacity(opacity: 0.4, child: body),
      child: body,
    );
  }

  Widget _chip(TrayItem t) {
    final c = context.noir;
    return Material(
      color: c.surface2,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        key: ValueKey('tray-${t.key}'),
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(t),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          child: Text('${t.emoji} ${t.title}', style: TextStyle(fontSize: 13, color: c.text)),
        ),
      ),
    );
  }

  Widget _feedback(TrayItem t) {
    final c = context.noir;
    return Material(
      color: c.accent,
      elevation: 6,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text('${t.emoji} ${t.title}', style: TextStyle(color: c.onAccent, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

// ---------- ช่องรับการลาก ----------

/// ห่อช่องวันให้รับการ์ดจากถาด · ลากผ่าน = กรอบสีหลัก
/// [minuteAt] = แปลงตำแหน่ง y ในช่อง → นาที (มุมมองสัปดาห์แบบตารางเวลา) · null = ใช้เวลาครั้งล่าสุด
class TrayDropTarget extends StatelessWidget {
  const TrayDropTarget({super.key, required this.day, required this.onDrop, required this.child, this.minuteAt});

  final DateTime day;
  final void Function(TrayItem item, DateTime day, int? minute) onDrop;
  final int Function(double localY)? minuteAt;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return DragTarget<TrayItem>(
      onAcceptWithDetails: (d) {
        int? minute;
        final f = minuteAt;
        final box = context.findRenderObject() as RenderBox?;
        if (f != null && box != null) minute = f(box.globalToLocal(d.offset).dy + 16);
        onDrop(d.data, day, minute);
      },
      builder: (context, cand, _) => cand.isEmpty
          ? child
          : DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: Border.all(color: c.accent, width: 2),
                borderRadius: BorderRadius.circular(6),
              ),
              child: child,
            ),
    );
  }
}

// ---------- แผ่นยืนยัน ----------

/// แผ่นยืนยัน: เวลา (จากครั้งล่าสุด) · ติ๊กวัน (คอม 2 สัปดาห์ · มือถือ 7 วัน) · เตือนเวลาชน · ยืนยัน → เลิกทำได้
Future<void> openTraySheet(BuildContext context, TrayItem item, {required DateTime day, int? startMinute}) async {
  final repo = CalendarScope.of(context);
  final result = await showMiniForm<(Set<DateTime>, int, int)>(
    context,
    (ctx) => _TraySheet(repo: repo, item: item, day: dayOnly(day), startMinute: startMinute),
  );
  if (result == null || !context.mounted) return;
  final (days, start, dur) = result;
  final undo = await placeTrayItem(repo, item, days, start, dur);
  if (!context.mounted) return;
  showToast(
    context,
    '✓ ลง ${item.title} ${days.length} วัน',
    kind: ToastKind.success,
    action: 'เลิกทำ',
    onAction: () => undo(),
  );
}

class _TraySheet extends StatefulWidget {
  const _TraySheet({required this.repo, required this.item, required this.day, this.startMinute});

  final CalendarRepository repo;
  final TrayItem item;
  final DateTime day;
  final int? startMinute;

  @override
  State<_TraySheet> createState() => _TraySheetState();
}

class _TraySheetState extends State<_TraySheet> {
  late int _start = widget.startMinute ?? widget.item.startMinute ?? trayDefaultStart;
  late int _dur = widget.item.durationMin ?? trayDefaultDuration;
  late final Set<DateTime> _days = {widget.day};
  late DateTime _from = widget.day.subtract(Duration(days: widget.day.weekday - 1));
  Map<DateTime, List<Occurrence>> _byDay = {};

  int get _weeks => isNarrow(context) ? 1 : 2;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final from = _from;
    final map = await widget.repo.occurrencesBetween(from, from.add(const Duration(days: 20)));
    for (final d in _days) {
      if (!map.containsKey(d)) map[d] = await widget.repo.occurrencesOn(d);
    }
    if (!mounted) return;
    setState(() => _byDay = {..._byDay, ...map});
  }

  void _shift(int weeks) {
    setState(() => _from = _from.add(Duration(days: 7 * weeks)));
    _load();
  }

  Future<void> _pickTime() async {
    final r = await pickRange(context, _start, _dur);
    if (r == null || !mounted) return;
    setState(() {
      _start = r.$1;
      _dur = r.$2;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final t = widget.item;
    final today = dayOnly(DateTime.now());
    final clashes = trayClashes(_byDay, _days, _start, _dur);
    final fromLast = widget.startMinute == null && t.startMinute != null;
    final sorted = _days.toList()..sort();
    return MiniForm(
      title: '${t.emoji} ${t.title}${t.source == TraySource.inbox ? ' · รอวันใหม่' : ' · ครั้งที่ ${t.sessions + 1}'}',
      primaryLabel: _days.isEmpty ? 'เลือกวันก่อน' : 'ยืนยัน ${_days.length} วัน',
      onPrimary: _days.isEmpty ? null : () => Navigator.pop(context, (_days, _start, _dur)),
      children: [
        MiniRow(
          key: const Key('tray-time'),
          icon: Icons.schedule,
          label: fromLast ? 'เวลา (เหมือนครั้งล่าสุด)' : 'เวลา',
          valueText: '${fmtMinute(_start)}–${fmtMinute((_start + _dur) % (24 * 60))} · ${durationText(_dur)}',
          onTap: _pickTime,
        ),
        const SizedBox(height: 8),
        Row(children: [
          IconButton(tooltip: 'สัปดาห์ก่อน', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Center(
              child: Text('ติ๊กวันที่จะทำ (เพิ่มได้หลายวัน)', style: TextStyle(fontSize: 12.5, color: c.muted)),
            ),
          ),
          IconButton(tooltip: 'สัปดาห์ถัดไป', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
        ]),
        Row(children: [
          for (final w in thaiWeekdayShort)
            Expanded(child: Center(child: Text(w, style: TextStyle(fontSize: 11, color: c.muted)))),
        ]),
        const SizedBox(height: 4),
        for (var w = 0; w < _weeks; w++)
          Row(children: [
            for (var i = 0; i < 7; i++)
              Expanded(child: _dayCell(_from.add(Duration(days: w * 7 + i)), today, clashes)),
          ]),
        const SizedBox(height: 8),
        if (sorted.isNotEmpty)
          Text('เลือก: ${sorted.map((d) => '${thaiWeekdayShort[d.weekday - 1]} ${d.day}').join(' · ')}',
              style: TextStyle(fontSize: 12.5, color: c.text)),
        if (clashes.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              '⚠ เวลาชน: ${clashes.entries.map((e) => '${e.key.day} ${thaiMonthsShort[e.key.month - 1]} (${e.value.join(', ')})').join(' · ')}'
              ' · ยังลงได้ เลือกเองว่าจะเลื่อนไหม',
              key: const Key('tray-clash'),
              style: TextStyle(fontSize: 12.5, color: c.warn),
            ),
          ),
      ],
    );
  }

  Widget _dayCell(DateTime d, DateTime today, Map<DateTime, List<String>> clashes) {
    final c = context.noir;
    final on = _days.contains(d);
    final clash = on && clashes.containsKey(d);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: on ? c.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          key: ValueKey('tray-day-${d.month}-${d.day}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => setState(() => on ? _days.remove(d) : _days.add(d)),
          child: Container(
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: d == today && !on ? Border.all(color: c.accent) : null,
            ),
            child: Text(
              clash ? '${d.day}!' : '${d.day}',
              style: TextStyle(
                fontWeight: on ? FontWeight.w600 : FontWeight.w400,
                color: on ? c.onAccent : (d.isBefore(today) ? c.muted : c.text),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
