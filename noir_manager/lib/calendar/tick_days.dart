import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'calendar_models.dart';
import 'calendar_ui.dart' show thaiWeekdayShort;

/// ตารางเดือนสำหรับติ๊กวัน (ทำซ้ำแบบ "เลือกวันเอง")
/// แตะวัน = ติ๊ก / เอาออก · วันที่เวลาชนกับงานอื่นมีจุด ! สีส้ม (ถามทีละวันตอนบันทึก)
class TickDaysCalendar extends StatefulWidget {
  const TickDaysCalendar({
    super.key,
    required this.initialMonth,
    required this.selected,
    required this.onToggle,
    this.clashDays,
  });

  final DateTime initialMonth;
  final Set<DateTime> selected;
  final ValueChanged<DateTime> onToggle;

  /// ส่งวันในตาราง → คืนวันที่เวลาชน (null = ไม่เช็ก)
  final Future<Set<DateTime>> Function(List<DateTime> days)? clashDays;

  @override
  State<TickDaysCalendar> createState() => _TickDaysCalendarState();
}

class _TickDaysCalendarState extends State<TickDaysCalendar> {
  late DateTime _month = DateTime(widget.initialMonth.year, widget.initialMonth.month);
  Set<DateTime> _clash = {};

  @override
  void initState() {
    super.initState();
    _loadClash();
  }

  Future<void> _loadClash() async {
    final f = widget.clashDays;
    if (f == null) return;
    final month = _month;
    final days = monthGridDays(month).where((d) => d.month == month.month).toList();
    final clash = await f(days);
    if (!mounted || month != _month) return;
    setState(() => _clash = clash);
  }

  void _shift(int n) {
    setState(() {
      _month = addMonths(_month, n);
      _clash = {};
    });
    _loadClash();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final today = dayOnly(DateTime.now());
    final days = monthGridDays(_month);
    final picked = widget.selected.where((d) => d.year == _month.year && d.month == _month.month).length;
    return Column(key: const Key('tick-days'), mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        IconButton(tooltip: 'เดือนก่อน', onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
        Expanded(
          child: Center(
            child: Text(thaiMonthYear(_month), style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          ),
        ),
        IconButton(tooltip: 'เดือนถัดไป', onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
      ]),
      Row(children: [
        for (final w in thaiWeekdayShort)
          Expanded(child: Center(child: Text(w, style: TextStyle(fontSize: 11, color: c.muted)))),
      ]),
      const SizedBox(height: 4),
      for (var r = 0; r < days.length ~/ 7; r++)
        Row(children: [
          for (final d in days.sublist(r * 7, r * 7 + 7))
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: _day(c, d, today),
              ),
            ),
        ]),
      const SizedBox(height: 6),
      Text(
        'แตะวัน = ติ๊ก / เอาออก · ! = เวลาชนกับงานอื่น (ถามทีละวันตอนบันทึก) · เดือนนี้เลือก $picked วัน',
        style: TextStyle(fontSize: 11, color: c.muted),
      ),
    ]);
  }

  Widget _day(NoirColors c, DateTime d, DateTime today) {
    final out = d.month != _month.month;
    final on = widget.selected.contains(d);
    final clash = _clash.contains(d);
    return Opacity(
      opacity: out ? 0.3 : 1,
      child: Material(
        color: on ? c.accent : c.surface2,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          key: ValueKey('tick-${d.month}-${d.day}'),
          borderRadius: BorderRadius.circular(9),
          onTap: out ? null : () => setState(() => widget.onToggle(d)),
          child: SizedBox(
            height: 34,
            child: Stack(children: [
              Center(
                child: Text('${d.day}',
                    style: TextStyle(
                      fontWeight: on || d == today ? FontWeight.w700 : FontWeight.w400,
                      color: on ? c.onAccent : (d == today ? c.accent : c.text),
                    )),
              ),
              if (clash)
                Positioned(
                  right: 4,
                  top: 1,
                  child: Text('!', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: on ? c.onAccent : c.warn)),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
