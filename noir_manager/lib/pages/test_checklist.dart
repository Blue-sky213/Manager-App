/// เช็กลิสต์ทดสอบด้วยมือ (รอบ 9D): โจทย์ สร้าง · แก้ · ลบ · ขอบ ๆ ของทุกหน้า
/// นัวร์ติ๊กเองบน Windows · ข้อที่มีเทสอัตโนมัติใน CI บอกชื่อไฟล์เทสไว้ · ติ๊กเก็บใน setting (ไม่แตะข้อมูลอื่น)
library;

import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../theme/noir_colors.dart';

const testChecklistKey = 'test_checklist';

/// (id, หน้า, ชนิด, โจทย์, เทสอัตโนมัติ)
typedef TestCase = (String, String, String, String, String?);

const testCases = <TestCase>[
  ('today-c', 'วันนี้', 'สร้าง', 'เพิ่มงาน 1 ครั้ง → ขึ้นในวันนี้', 'widget_test'),
  ('today-e', 'วันนี้', 'แก้', 'แก้เวลา · ความสำคัญ → ลำดับเปลี่ยน', 'widget_test'),
  ('today-d', 'วันนี้', 'ลบ', 'ลบงาน แล้วกด "เลิกทำ" → กลับมา', null),
  ('today-x', 'วันนี้', 'ขอบ', 'กดทำแล้วหลังเที่ยงคืน · งานโต้รุ่ง ยังนับวันเดิม', 'round7c_test'),
  ('cal-c', 'ปฏิทิน', 'สร้าง', 'งานซ้ำรายสัปดาห์ · งานเลือกวันเอง', 'widget_test'),
  ('cal-e', 'ปฏิทิน', 'แก้', 'ย้ายทั้งแถว (ครั้งนี้และต่อจากนี้)', 'widget_test'),
  ('cal-d', 'ปฏิทิน', 'ลบ', 'ลบครั้งเดียว vs ลบทั้งแถว', 'widget_test'),
  ('cal-x', 'ปฏิทิน', 'ขอบ', 'เวลาชน · วันหยุด · งานไม่มีวันจบ', 'calendar_test'),
  ('learn-c', 'การเรียน', 'สร้าง', 'วิชา · บท · ใส่คะแนนหัวข้อ', 'widget_test'),
  ('learn-e', 'การเรียน', 'แก้', 'ใส่คะแนนผิด → แก้ → % เปลี่ยน', 'widget_test'),
  ('learn-d', 'การเรียน', 'ลบ', 'ลบวิชาที่มีคาบ → ถามก่อน · คาบหาย', null),
  ('learn-x', 'การเรียน', 'ขอบ', 'Advanced แดง 2 รอบ · เกรด ขาดสอบ = F', 'grading_test'),
  ('skill-c', 'สกิล', 'สร้าง', 'สาย → สกิล → ทักษะย่อย → เป้า', 'skill_tree_test'),
  ('skill-e', 'สกิล', 'แก้', 'ถึงเป้า → ยกระดับเป้า · ย้ายสกิลไปสายอื่น', 'skills_test'),
  ('skill-d', 'สกิล', 'ลบ', 'ลบสกิล → ทักษะย่อย/บันทึกหาย · ลบสาย → สกิลยังอยู่', 'skill_tree_test'),
  ('skill-x', 'สกิล', 'ขอบ', 'ข้ามด่านที่ล็อก (แค่เตือน) · ตั้งต้องผ่านก่อนวนกัน (ไม่ให้)', 'skill_tree_test'),
  ('work-c', 'งาน', 'สร้าง', 'โปรเจกต์ + งวด 30/40/30', 'projects_test'),
  ('work-e', 'งาน', 'แก้', 'ย้ายสถานะ (คลิกขวาการ์ด)', null),
  ('work-d', 'งาน', 'ลบ', 'ลบโปรเจกต์ → รายการเงินยังอยู่', 'projects_test'),
  ('work-x', 'งาน', 'ขอบ', 'ติ๊กรับงวดแล้วเอาออก → รายรับหาย · ติ๊กจากภาพรวม', 'overviews_test'),
  ('money-c', 'เงิน', 'สร้าง', 'จดรับ/จ่าย · เพิ่มค่าบริการ', 'money_test'),
  ('money-e', 'เงิน', 'แก้', 'ค่าบริการยอดเปลี่ยน → ป้ายส้ม', 'money_test'),
  ('money-d', 'เงิน', 'ลบ', 'ลบค่าบริการ → รายการที่จ่ายแล้วยังอยู่', 'demo_life_test'),
  ('money-x', 'เงิน', 'ขอบ', 'วันตัด 31 → ก.พ. · ส่งออก CSV เปิดใน Excel ภาษาไทยไม่เพี้ยน', 'money_test'),
  ('stats-x1', 'สถิติ', 'ขอบ', 'ไม่มีข้อมูล → ทุกแท็บไม่พัง', 'responsive_test'),
  ('stats-x2', 'สถิติ', 'ขอบ', 'ข้อมูลตัวอย่าง 1 ปี → ทุกแท็บเปิดเร็ว ไม่หน่วง', 'demo_life_test'),
  ('set-c', 'ตั้งค่า', 'สร้าง', 'หมวดใหม่ · ชุดสติกเกอร์', 'round7b_test'),
  ('set-e', 'ตั้งค่า', 'แก้', 'ซ่อนเมนู งาน / เงิน', 'money_test'),
  ('set-d', 'ตั้งค่า', 'ลบ', 'ลบหมวด → ย้ายงานไปหมวดอื่น', null),
  ('set-x', 'ตั้งค่า', 'ขอบ', 'สำรองข้อมูล → กู้คืน → ข้อมูลครบ', null),
];

class TestChecklistPage extends StatefulWidget {
  const TestChecklistPage({super.key});

  @override
  State<TestChecklistPage> createState() => _TestChecklistPageState();
}

class _TestChecklistPageState extends State<TestChecklistPage> {
  Set<String> _done = {};
  CalendarRepository? _cal;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cal = CalendarScope.of(context);
    if (cal != _cal) {
      _cal = cal;
      cal.getSetting(testChecklistKey).then((v) {
        if (mounted) setState(() => _done = {for (final x in (v ?? '').split(',')) if (x.isNotEmpty) x});
      });
    }
  }

  Future<void> _toggle(String id) async {
    setState(() => _done.contains(id) ? _done.remove(id) : _done.add(id));
    await _cal!.setSetting(testChecklistKey, _done.join(','));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final pages = <String>[];
    for (final t in testCases) {
      if (!pages.contains(t.$2)) pages.add(t.$2);
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('เช็กลิสต์ทดสอบ · ${_done.length}/${testCases.length}'),
        actions: [
          if (_done.isNotEmpty)
            TextButton(
              key: const Key('checklist-reset'),
              onPressed: () async {
                setState(() => _done = {});
                await _cal!.setSetting(testChecklistKey, '');
              },
              child: const Text('เริ่มใหม่'),
            ),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        Text('แนะนำ: เปิด "ใช้ข้อมูลตัวอย่างทั้งหมด" ก่อน จะได้ทดสอบตอนมีข้อมูลเยอะ · 🤖 = มีเทสอัตโนมัติใน CI แล้ว',
            style: TextStyle(fontSize: 12, color: c.muted)),
        for (final page in pages) ...[
          Padding(
            padding: const EdgeInsets.only(top: 14, bottom: 2),
            child: Text(page, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
          ),
          for (final (id, _, kind, text, auto) in testCases.where((t) => t.$2 == page))
            CheckboxListTile(
              key: ValueKey('check-$id'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _done.contains(id),
              onChanged: (_) => _toggle(id),
              title: Text('$kind · $text'),
              subtitle: auto == null ? null : Text('🤖 $auto', style: TextStyle(fontSize: 11, color: c.muted)),
            ),
        ],
      ]),
    );
  }
}
