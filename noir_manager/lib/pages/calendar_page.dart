import 'package:flutter/material.dart';

import '../calendar/calendar_flows.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart';
import '../calendar/day_agenda.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';

/// หน้า "ปฏิทิน": เลือกวันในสัปดาห์ → ดู/เพิ่ม/เลื่อน/ยกเลิกงานของวันนั้น
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> with CalendarListener<CalendarPage> {
  bool _loading = true;
  DateTime _selected = dayOnly(DateTime.now());
  List<Occurrence> _items = [];
  List<LifeBaseDay> _lifeBase = defaultLifeBase();
  Map<int, ActivityCategory> _categories = {};

  /// วันจันทร์ของสัปดาห์ที่เลือก
  DateTime get _monday =>
      _selected.subtract(Duration(days: _selected.weekday - 1));

  @override
  Future<void> reload() async {
    final repo = calendar!;
    final day = _selected;
    final items = await repo.occurrencesOn(day);
    final lifeBase = await repo.lifeBase();
    final cats = await repo.categories();
    if (!mounted || day != _selected) return; // ผู้ใช้กดเปลี่ยนวันระหว่างโหลด
    setState(() {
      _items = items;
      _lifeBase = lifeBase;
      _categories = {for (final c in cats) c.id: c};
      _loading = false;
    });
  }

  void _select(DateTime day) {
    setState(() => _selected = dayOnly(day));
    reload();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (_loading) return const Center(child: CircularProgressIndicator());
    final repo = calendar!;
    final today = dayOnly(DateTime.now());
    final monday = _monday;
    final sunday = monday.add(const Duration(days: 6));

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        Text('Calendar Core', style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 4),
        Text('ปฏิทิน',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 16),

        // แถบเลื่อนสัปดาห์
        Row(
          children: [
            IconButton(
              tooltip: 'สัปดาห์ก่อน',
              icon: const Icon(Icons.chevron_left),
              onPressed: () => _select(_selected.subtract(const Duration(days: 7))),
            ),
            Expanded(
              child: Text(
                '${thaiShortDate(monday)} – ${thaiShortDate(sunday)}',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
              ),
            ),
            IconButton(
              tooltip: 'สัปดาห์ถัดไป',
              icon: const Icon(Icons.chevron_right),
              onPressed: () => _select(_selected.add(const Duration(days: 7))),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 7 วันของสัปดาห์
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _DayChip(
                    day: monday.add(Duration(days: i)),
                    selected: monday.add(Duration(days: i)) == _selected,
                    isToday: monday.add(Duration(days: i)) == today,
                    onTap: () => _select(monday.add(Duration(days: i))),
                  ),
                ),
              ),
          ],
        ),
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
                    onPressed: () => _select(today),
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
      ],
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.day,
    required this.selected,
    required this.isToday,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final fg = selected ? c.onAccent : c.text;
    return Material(
      color: selected ? c.accent : c.surface,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isToday && !selected ? c.accent : c.line),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(thaiWeekdayShort[day.weekday - 1],
                  style: TextStyle(fontSize: 12, color: selected ? fg : c.muted)),
              Text('${day.day}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: fg)),
            ],
          ),
        ),
      ),
    );
  }
}
