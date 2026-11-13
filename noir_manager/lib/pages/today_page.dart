import 'package:flutter/material.dart';

import '../calendar/sticker_ui.dart';
import '../calendar/calendar_flows.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/clash_page.dart';
import '../calendar/day_agenda.dart';
import '../calendar/day_cards.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';

/// หน้า "วันนี้": แผนรายวัน + ชั่วโมงนอนคืนนี้ + Updates
class TodayPage extends StatefulWidget {
  const TodayPage({super.key});

  @override
  State<TodayPage> createState() => _TodayPageState();
}

class _TodayPageState extends State<TodayPage> with CalendarListener<TodayPage> {
  bool _loading = true;
  DateTime _today = dayOnly(DateTime.now());
  List<Occurrence> _items = [];
  List<Occurrence> _inbox = [];
  List<LifeBaseDay> _lifeBase = defaultLifeBase();
  Map<int, ActivityCategory> _categories = {};

  @override
  Future<void> reload() async {
    final repo = calendar!;
    final today = dayOnly(DateTime.now());
    final items = await repo.occurrencesOn(today);
    final inbox = await repo.inbox();
    final lifeBase = await repo.lifeBase();
    final cats = await repo.categories();
    if (!mounted) return;
    setState(() {
      _today = today;
      _items = items;
      _inbox = inbox;
      _lifeBase = lifeBase;
      _categories = {for (final c in cats) c.id: c};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (_loading) return const Center(child: CircularProgressIndicator());

    final repo = calendar!;
    final todayLb = _lifeBase[_today.weekday - 1];
    final active = _items.where((o) => o.active).toList();
    final done = active.where((o) => o.status == OccurrenceStatus.done).length;
    final clashCount = clashingIds(_items).length;

    final agenda = DayAgenda(
      items: _items,
      categories: _categories,
      lifeBase: todayLb,
      onTap: (o) => openOccurrence(context, repo, o),
    );
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // โต้รุ่ง · พลาดเมื่อวาน · เช็กอินเช้า (โชว์เฉพาะที่ต้องตอบ)
        const NightCards(),
        DayStickerCard(day: _today),
        const SizedBox(height: 16),
        _SleepCard(
          tonight: todayLb,
          tomorrow: _lifeBase[_today.weekday % 7],
          onEdit: () => editLifeBaseFlow(context, repo),
        ),
        const SizedBox(height: 16),
        _InboxCard(
          items: _inbox,
          onPick: (o) => rescheduleFlow(context, repo, o, fromInbox: true),
        ),
      ],
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.end,
          spacing: 12,
          runSpacing: 12,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  active.isEmpty ? 'วันนี้' : 'วันนี้ · ทำแล้ว $done/${active.length}',
                  style: TextStyle(fontSize: 13, color: c.muted),
                ),
                const SizedBox(height: 4),
                Text(thaiShortDate(_today),
                    style: TextStyle(
                        fontSize: 28, fontWeight: FontWeight.w600, color: c.text)),
              ],
            ),
            FilledButton.icon(
              onPressed: () => addActivityFlow(context, repo, _today),
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มงาน'),
              style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
            ),
          ],
        ),
        const SizedBox(height: 20),
        // วันนี้มีงานเวลาทับกัน → แถบแดงพาไปหน้าแก้
        if (clashCount > 0) ...[
          Material(
            color: c.bad.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => openClashPage(context),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: c.bad),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text('วันนี้มีงานเวลาชน $clashCount งาน · แตะเพื่อแก้วัน/เวลา',
                          style: TextStyle(color: c.bad, fontWeight: FontWeight.w600)),
                    ),
                    Icon(Icons.chevron_right, color: c.bad),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // จอกว้าง: ตาราง + คอลัมน์ขวา (ตาม Mockup) · จอแคบ: เรียงลงล่าง
        LayoutBuilder(
          builder: (context, box) => box.maxWidth >= 860
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: agenda),
                    const SizedBox(width: 24),
                    SizedBox(width: 320, child: side),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [side, const SizedBox(height: 16), agenda],
                ),
        ),
      ],
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({
    required this.tonight,
    required this.tomorrow,
    required this.onEdit,
  });

  final LifeBaseDay tonight;
  final LifeBaseDay tomorrow;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final hours = sleepHours(tonight, tomorrow);
    final text = hours == hours.roundToDouble()
        ? hours.toStringAsFixed(0)
        : hours.toStringAsFixed(1);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ชั่วโมงนอนคืนนี้', style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 4),
            Text('$text ชม.',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w600, color: c.text)),
            Text(
              'นอน ${fmtMinute(tonight.bedMinute)} → ตื่น ${fmtMinute(tomorrow.wakeMinute)}',
              style: TextStyle(fontSize: 13, color: c.muted),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: onEdit,
              icon: const Icon(Icons.bedtime_outlined, size: 18),
              label: const Text('ตั้งเวลานอน / ตื่น'),
            ),
          ],
        ),
      ),
    );
  }
}

class _InboxCard extends StatelessWidget {
  const _InboxCard({required this.items, required this.onPick});

  final List<Occurrence> items;
  final ValueChanged<Occurrence> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Updates',
                      style: TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: items.isEmpty ? c.surface2 : c.amberBg,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${items.length} รายการ',
                      style: TextStyle(
                          fontSize: 13, color: items.isEmpty ? c.muted : c.amberText)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text('เลื่อนแล้ว แต่ยังไม่มีวันแทน',
                style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 12),
            if (items.isEmpty)
              Text('ไม่มีงานค้าง', style: TextStyle(color: c.muted)),
            for (final o in items) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(o.title, style: TextStyle(fontSize: 15, color: c.text)),
                    Text('เดิม: ${thaiShortDate(o.day)}',
                        style: TextStyle(fontSize: 12, color: c.muted)),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => onPick(o),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(44),
                        foregroundColor: c.text,
                        side: BorderSide(color: c.line2),
                      ),
                      child: const Text('เลือกวันแทน'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    );
  }
}
