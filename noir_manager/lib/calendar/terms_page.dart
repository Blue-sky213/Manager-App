import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'calendar_listener.dart';
import 'calendar_models.dart';
import 'holiday_flow.dart';
import '../widgets/toast.dart';

Future<void> openTermsPage(BuildContext context) => Navigator.of(context)
    .push(MaterialPageRoute(builder: (_) => const TermsPage()));

/// วันที่แบบมีปี พ.ศ. เช่น "จันทร์ 9 พ.ย. 2569"
String thaiDateWithYear(DateTime d) => '${thaiShortDate(d)} ${buddhistYear(d)}';

/// หน้า "ภาคเรียน & วันหยุด": ตั้งวันเปิด–ปิดเทอม + วันหยุด
/// (ใช้ต่อกับระบบวันหยุด, "ครั้งที่ n/N", ระยะห่างก่อนสอบ)
class TermsPage extends StatefulWidget {
  const TermsPage({super.key});

  @override
  State<TermsPage> createState() => _TermsPageState();
}

class _TermsPageState extends State<TermsPage> with CalendarListener<TermsPage> {
  List<Term> _terms = [];
  List<Holiday> _holidays = [];

  @override
  Future<void> reload() async {
    final terms = await calendar!.terms();
    final holidays = await calendar!.holidays();
    if (!mounted) return;
    setState(() {
      _terms = terms;
      _holidays = holidays;
    });
  }

  Future<DateTime?> _pickDate(DateTime initial, String help) => showDatePicker(
        context: context,
        initialDate: initial,
        firstDate: DateTime(2020),
        lastDate: DateTime(2040),
        helpText: help,
      );

  Future<void> _editTerm([Term? old]) async {
    var year = old?.year ?? 1;
    var termNo = old?.termNo ?? 1;
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => MiniForm(
          title: old == null ? 'เพิ่มภาคเรียน' : 'แก้ภาคเรียน',
          primaryLabel: 'เลือกวัน',
          onPrimary: () => Navigator.pop(ctx, true),
          children: [
            const MiniLabel('ปีที่'),
            MiniSegments<int>(
              value: year,
              items: [for (var y = 1; y <= 4; y++) (y, '$y')],
              onChanged: (y) => setLocal(() => year = y),
            ),
            const MiniLabel('เทอม'),
            MiniSegments<int>(
              value: termNo,
              items: const [(1, '1'), (2, '2'), (3, 'ฤดูร้อน')],
              onChanged: (t) => setLocal(() => termNo = t),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final start = await _pickDate(old?.start ?? dayOnly(DateTime.now()), 'วันเปิดเทอม');
    if (start == null || !mounted) return;
    final end = await _pickDate(
        old != null && old.end.isAfter(start) ? old.end : start.add(const Duration(days: 7 * 16)),
        'วันสุดท้ายของเทอม');
    if (end == null || !mounted) return;
    if (end.isBefore(start)) {
      showToast(context, 'วันสุดท้ายต้องไม่อยู่ก่อนวันเปิดเทอม');
      return;
    }
    // เปลี่ยนปี/เทอมของรายการเดิม → ลบตัวเก่าก่อน (ไม่งั้นจะเหลือ 2 รายการ)
    if (old != null && (old.year != year || old.termNo != termNo)) {
      await calendar!.deleteTerm(old.id);
    }
    await calendar!.saveTerm(year, termNo, start, end);
  }

  /// วันเดียว (แตะวันเดียวแล้วกดบันทึก) หรือช่วง เช่น สงกรานต์ 13–15 เม.ย.
  /// บันทึกแล้วเปิดกล่องเลื่อน 4 ทางให้งานที่ตรงวันหยุดทันที
  Future<void> _addHoliday() async {
    final today = dayOnly(DateTime.now());
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2040),
      initialDateRange: DateTimeRange(start: today, end: today),
      helpText: 'วันหยุด (วันเดียวหรือช่วง)',
    );
    if (range == null || !mounted) return;
    final name = await askText(context,
        title: 'ชื่อวันหยุด', label: 'ชื่อ', hint: 'เช่น วันพ่อแห่งชาติ', confirmLabel: 'บันทึก');
    if (name == null || name.trim().isEmpty || !mounted) return;
    final repo = calendar!;
    for (var d = dayOnly(range.start);
        !d.isAfter(dayOnly(range.end));
        d = DateTime(d.year, d.month, d.day + 1)) {
      await repo.setHoliday(d, name.trim());
    }
    if (!mounted) return;
    await holidayFlow(context, repo, range.start, range.end, name.trim());
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final head = TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text);
    final muted = TextStyle(color: c.muted, fontSize: 13);
    final weeks = {
      for (final t in _terms) t.id: (t.end.difference(t.start).inDays ~/ 7) + 1,
    };

    return Scaffold(
      appBar: AppBar(title: const Text('ภาคเรียน & วันหยุด')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(children: [
            Expanded(child: Text('ภาคเรียน', style: head)),
            FilledButton.tonalIcon(
              onPressed: _editTerm,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มเทอม'),
            ),
          ]),
          const SizedBox(height: 4),
          Text('ใช้นับ "ครั้งที่ n/N" ของคาบเรียน และหาวันหยุดที่ตรงกับคาบ', style: muted),
          const SizedBox(height: 8),
          if (_terms.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('ยังไม่มีเทอม · กด "เพิ่มเทอม" แล้วเลือกวันเปิด–ปิด', style: muted),
            ),
          for (final t in _terms)
            Card(
              child: ListTile(
                leading: Icon(
                  t.contains(DateTime.now()) ? Icons.radio_button_checked : Icons.school_outlined,
                  color: t.contains(DateTime.now()) ? c.accent : c.muted,
                ),
                title: Text(t.label),
                subtitle: Text(
                    '${thaiDateWithYear(t.start)} – ${thaiDateWithYear(t.end)} · ${weeks[t.id]} สัปดาห์'),
                onTap: () => _editTerm(t),
                trailing: IconButton(
                  tooltip: 'ลบเทอม',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () async {
                    if (await confirmDelete(context, t.label)) await calendar!.deleteTerm(t.id);
                  },
                ),
              ),
            ),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: Text('วันหยุด', style: head)),
            FilledButton.tonalIcon(
              onPressed: _addHoliday,
              icon: const Icon(Icons.add),
              label: const Text('เพิ่มวันหยุด'),
            ),
          ]),
          const SizedBox(height: 4),
          Text('เพิ่มวันหยุด → เลือกทางเลื่อนงานที่ตรงวันนั้นได้ทันที (เลื่อนรอบถัดไป · นัดวันอื่น · รอนัด · ยกเลิก)', style: muted),
          const SizedBox(height: 8),
          if (_holidays.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('ยังไม่มีวันหยุด', style: muted),
            ),
          for (final h in _holidays)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.beach_access_outlined, color: c.accent),
              title: Text(h.name),
              subtitle: Text(thaiDateWithYear(h.day)),
              trailing: IconButton(
                tooltip: 'ลบวันหยุด',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => calendar!.removeHoliday(h.day),
              ),
            ),
        ],
      ),
    );
  }
}
