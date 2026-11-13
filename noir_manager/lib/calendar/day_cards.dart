/// การ์ดหน้าวันนี้ (รอบ 7 · M / O): โต้รุ่ง · พลาดเมื่อคืน · เช็กอินตอนเช้า
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'calendar_listener.dart';
import 'calendar_models.dart';
import 'calendar_ui.dart';
import 'day_judge.dart';
import 'sticker_ui.dart' show StickerGlyph;
import 'stickers.dart';

/// เหตุผลที่พลาด (แตะเร็ว · ไม่บังคับ)
const missReasons = ['ง่วง', 'งานด่วน', 'ประเมินเวลาน้อยไป', 'ลืม', 'อื่น ๆ'];

/// การ์ดเดียวรวม 3 เรื่องของ "คืนที่ผ่านมา / คืนนี้" · แสดงเฉพาะเรื่องที่ต้องตอบ
class NightCards extends StatefulWidget {
  const NightCards({super.key, this.now});

  /// เวลาปัจจุบัน (เทสส่งเข้ามาได้)
  final DateTime? now;

  @override
  State<NightCards> createState() => _NightCardsState();
}

class _NightCardsState extends State<NightCards> with CalendarListener<NightCards> {
  DateTime get _now => widget.now ?? DateTime.now();
  bool _loaded = false;

  // โต้รุ่ง: วันที่ยังเปิดอยู่ · งานสำคัญที่ค้าง
  DateTime? _openDay;
  List<Occurrence> _pending = const [];
  bool _askedNight = false;

  // พลาดเมื่อวาน (ถูกแปะอัตโนมัติ)
  DaySticker? _missed;
  List<Occurrence> _missedItems = const [];

  // เช็กอินเช้านี้
  Checkin? _checkin;
  late List<LifeBaseDay> _lifeBase;
  bool _editingCheckin = false;
  late DateTime _slept;
  late DateTime _woke;
  int _energy = 3;

  @override
  Future<void> reload() async {
    final repo = calendar!;
    await judgeDays(repo, now: _now);
    final lb = await repo.lifeBase();
    final now = _now;
    final open = openDay(now, lb);
    final openItems = await repo.occurrencesOn(open);
    final asked = (await repo.getSetting(extendKey(open))) != null || (await repo.getSetting(closedKey(open))) == 'on';
    final today = dayOnly(now);
    final yesterday = today.subtract(const Duration(days: 1));
    final ys = (await repo.daySticker(yesterday, yesterday)).where((s) => s.auto == 'missed').firstOrNull;
    final yItems = ys == null ? const <Occurrence>[] : importantOf(await repo.occurrencesOn(yesterday));
    final ci = await repo.checkin(today);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      _lifeBase = lb;
      _openDay = open;
      _pending = importantOf(openItems).where((o) => o.status == OccurrenceStatus.planned).toList();
      _askedNight = asked;
      _missed = ys;
      _missedItems = yItems.where((o) => o.status == OccurrenceStatus.planned).toList();
      _checkin = ci;
      if (!_editingCheckin) {
        // ค่าเริ่มต้น = ตาราง Life Base (นอนเมื่อคืน → ตื่นเช้านี้)
        final y = lb[yesterday.weekday - 1], t = lb[today.weekday - 1];
        _slept = ci?.sleptAt ??
            (y.bedMinute < 12 * 60 ? atMinute(today, y.bedMinute) : atMinute(yesterday, y.bedMinute));
        _woke = ci?.wokeAt ?? atMinute(today, t.wakeMinute);
        _energy = ci?.energy ?? 3;
      }
    });
  }

  Future<void> _extend() async {
    final d = _openDay!;
    final noon = DateTime(d.year, d.month, d.day + 1, 12);
    await calendar!.setSetting(extendKey(d), noon.toIso8601String());
    calendar!.refresh();
  }

  Future<void> _stillWorking() async {
    await calendar!.setSetting(extendKey(_openDay!), defaultCutoff(_openDay!, _lifeBase).toIso8601String());
    calendar!.refresh();
  }

  Future<void> _closeDay() async {
    final repo = calendar!;
    await repo.setSetting(closedKey(_openDay!), 'on');
    await judgeDays(repo, now: _now, force: true);
    repo.refresh();
  }

  Future<void> _reason(String r) async {
    final repo = calendar!;
    final today = dayOnly(_now);
    final ci = _checkin ?? Checkin(day: today);
    await repo.saveCheckin(ci.copyWith(missReason: r));
  }

  Future<void> _moveMissed({required bool toInbox}) async {
    final repo = calendar!;
    final today = dayOnly(_now);
    for (final o in _missedItems) {
      if (toInbox) {
        await repo.sendToInbox(o.id);
      } else {
        await repo.moveOccurrence(o.id, today,
            start: o.startAt == null ? null : atMinute(today, minuteOf(o.startAt!)),
            end: o.endAt == null ? null : atMinute(today, minuteOf(o.startAt!)).add(o.endAt!.difference(o.startAt!)));
      }
    }
  }

  Future<void> _saveCheckin() async {
    final repo = calendar!;
    final today = dayOnly(_now);
    await repo.saveCheckin(Checkin(
      day: today,
      sleptAt: _slept,
      wokeAt: _woke,
      energy: _energy,
      missReason: _checkin?.missReason,
    ));
    setState(() => _editingCheckin = false);
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final c = context.noir;
    final now = _now;
    final cards = <Widget>[];

    // 1) โต้รุ่ง: เลยเวลานอนแล้ว · งานสำคัญยังค้าง · ยังไม่ได้ตอบ
    if (_pending.isNotEmpty && !_askedNight && pastBedtime(now, _openDay!, _lifeBase)) {
      cards.add(_card(c,
          key: const Key('night-card'),
          border: c.warn,
          children: [
            Text('🌙 เลยเวลานอนแล้ว · ยังทำอยู่ไหม?', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 4),
            Text('ค้าง: ${_pending.map((o) => o.title).join(', ')} · ตัดสินตอน ${fmtTime(defaultCutoff(_openDay!, _lifeBase))}',
                style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.tonal(onPressed: _stillWorking, child: const Text('ยังทำอยู่')),
              OutlinedButton(onPressed: _extend, child: const Text('ต่อถึงเที่ยงพรุ่งนี้')),
              TextButton(onPressed: _closeDay, child: const Text('ปิดวันนี้')),
            ]),
          ]));
    }

    // 2) เมื่อคืนพลาด → เหตุผล (ไม่บังคับ) + ย้ายงาน
    if (_missed != null && _missedItems.isNotEmpty) {
      cards.add(_card(c,
          key: const Key('missed-card'),
          border: c.bad,
          children: [
            Row(children: [
              StickerGlyph(_missed!.sticker, size: 36),
              const SizedBox(width: 10),
              Expanded(
                child: Text('เมื่อวานพลาด: ${_missedItems.map((o) => o.title).join(', ')}',
                    style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
              ),
            ]),
            const SizedBox(height: 8),
            Text('เพราะอะไร? (ไม่ตอบก็ได้ · ใช้ดูสถิติย้อนหลัง)', style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final r in missReasons)
                ChoiceChip(
                  showCheckmark: false,
                  visualDensity: VisualDensity.compact,
                  label: Text(r),
                  selected: _checkin?.missReason == r,
                  onSelected: (_) => _reason(r),
                ),
            ]),
            const SizedBox(height: 8),
            Wrap(spacing: 8, children: [
              FilledButton.tonal(onPressed: () => _moveMissed(toInbox: false), child: const Text('ย้ายไปทำวันนี้')),
              TextButton(onPressed: () => _moveMissed(toInbox: true), child: const Text('ไป Updates')),
            ]),
          ]));
    }

    // 3) เช็กอินเช้า: นอนจริง · ตื่น · พลัง
    final ci = _checkin;
    final done = ci?.sleptAt != null && !_editingCheckin;
    cards.add(_card(c,
        key: const Key('checkin-card'),
        children: done
            ? [
                Row(children: [
                  Expanded(
                    child: Text(
                      'เช็กอิน · นอน ${fmtTime(ci!.sleptAt!)} → ตื่น ${fmtTime(ci.wokeAt!)} · ${ci.sleepHours!.toStringAsFixed(1)} ชม. · พลัง ${ci.energy}/5',
                      style: TextStyle(fontSize: 13, color: c.muted),
                    ),
                  ),
                  TextButton(onPressed: () => setState(() => _editingCheckin = true), child: const Text('แก้')),
                ]),
              ]
            : [
                Text('เช้านี้ · เมื่อคืนนอนจริงเท่าไหร่?', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      key: const Key('checkin-slept'),
                      icon: const Icon(Icons.bedtime_outlined, size: 18),
                      label: Text('นอน ${fmtTime(_slept)}'),
                      onPressed: () async {
                        final m = await pickMinute(context, minuteOf(_slept), title: 'เมื่อคืนนอนกี่โมง');
                        if (m == null) return;
                        final today = dayOnly(_now);
                        setState(() {
                          _editingCheckin = true;
                          _slept = m < 12 * 60 ? atMinute(today, m) : atMinute(today.subtract(const Duration(days: 1)), m);
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                      label: Text('ตื่น ${fmtTime(_woke)}'),
                      onPressed: () async {
                        final m = await pickMinute(context, minuteOf(_woke), title: 'ตื่นกี่โมง');
                        if (m == null) return;
                        setState(() {
                          _editingCheckin = true;
                          _woke = atMinute(dayOnly(_now), m);
                        });
                      },
                    ),
                  ),
                ]),
                const SizedBox(height: 8),
                Text('พลังตอนนี้', style: TextStyle(fontSize: 12, color: c.muted)),
                const SizedBox(height: 4),
                MiniSegments<int>(
                  key: const Key('checkin-energy'),
                  value: _energy,
                  items: const [(1, '😴 1'), (2, '2'), (3, '🙂 3'), (4, '4'), (5, '⚡ 5')],
                  onChanged: (v) => setState(() {
                    _editingCheckin = true;
                    _energy = v;
                  }),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton(key: const Key('checkin-save'), onPressed: _saveCheckin, child: const Text('บันทึกเช็กอิน')),
                ),
              ]));

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final w in cards) ...[w, const SizedBox(height: 12)],
    ]);
  }

  Widget _card(NoirColors c, {Key? key, Color? border, required List<Widget> children}) => Card(
        key: key,
        shape: border == null
            ? null
            : RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: border, width: 1.5)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
        ),
      );
}


/// ตั้งค่า › สติกเกอร์อัตโนมัติ: เปิด/ปิด · เลือกสติกเกอร์ "พลาดงาน" / "เสร็จย้อนหลัง" · เปลี่ยนสติกเกอร์ หรือแค่ป้าย
class AutoStickerSettings extends StatefulWidget {
  const AutoStickerSettings({super.key});

  @override
  State<AutoStickerSettings> createState() => _AutoStickerSettingsState();
}

class _AutoStickerSettingsState extends State<AutoStickerSettings> with CalendarListener<AutoStickerSettings> {
  bool _on = true;
  Sticker? _missed;
  Sticker? _late;
  bool _swap = true;
  List<StickerPack> _packs = const [];

  @override
  Future<void> reload() async {
    final repo = calendar!;
    final on = (await repo.getSetting(autoStickerKey)) != 'off';
    final m = await missedSticker(repo);
    final l = await lateSticker(repo);
    final swap = (await repo.getSetting(lateModeKey)) != 'tag';
    final packs = (await repo.stickerPacks()).where((p) => p.stickers.isNotEmpty).toList();
    if (!mounted) return;
    setState(() {
      _on = on;
      _missed = m;
      _late = l;
      _swap = swap;
      _packs = packs;
    });
  }

  Future<void> _pick(String key, String title) async {
    final repo = calendar!;
    final s = await showMiniForm<Sticker>(
      context,
      (ctx) => MiniForm(title: title, children: [
        for (final p in _packs) ...[
          MiniLabel(p.name),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in p.stickers)
              Tooltip(
                message: s.name,
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.pop(ctx, s),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: ctx.noir.surface2, borderRadius: BorderRadius.circular(10)),
                    child: Center(child: StickerGlyph(s, size: 38)),
                  ),
                ),
              ),
          ]),
        ],
      ]),
    );
    if (s != null) {
      await repo.setSetting(key, '${s.id}');
      repo.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final repo = calendar;
    Widget glyph(Sticker? s) => s == null ? Text('—', style: TextStyle(color: c.muted)) : StickerGlyph(s, size: 32);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      MiniSwitchRow(
        key: const Key('auto-sticker'),
        label: 'ผ่านวันแล้วงานสำคัญไม่ครบ → แปะให้อัตโนมัติ',
        detail: 'ตัดสินตอนเวลาตื่นเช้าวันถัดไป',
        value: _on,
        onChanged: (v) async {
          await repo?.setSetting(autoStickerKey, v ? 'on' : 'off');
          repo?.refresh();
        },
      ),
      if (_on) ...[
        MiniRow(
          key: const Key('auto-missed'),
          label: 'พลาดงาน',
          value: Align(alignment: Alignment.centerRight, child: glyph(_missed)),
          onTap: () => _pick(missedStickerKey, 'สติกเกอร์ "พลาดงาน"'),
        ),
        MiniRow(
          key: const Key('auto-late'),
          label: 'เสร็จย้อนหลัง',
          value: Align(alignment: Alignment.centerRight, child: glyph(_late)),
          onTap: () => _pick(lateStickerKey, 'สติกเกอร์ "เสร็จย้อนหลัง"'),
        ),
        const MiniLabel('ทำเสร็จทีหลัง'),
        MiniSegments<bool>(
          value: _swap,
          items: const [(true, 'เปลี่ยนสติกเกอร์'), (false, 'แค่ขึ้นป้าย')],
          onChanged: (v) async {
            await repo?.setSetting(lateModeKey, v ? 'swap' : 'tag');
            repo?.refresh();
          },
        ),
      ],
    ]);
  }
}
