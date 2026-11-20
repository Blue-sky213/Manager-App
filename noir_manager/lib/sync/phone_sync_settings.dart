/// ตั้งค่า › เชื่อมมือถือ (รอบ 14): เปิด/ปิด · โฟลเดอร์ iCloud · สถานะ · ประวัติคำสั่งจากมือถือ · คู่มือ
library;

import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'phone_sync.dart';

/// ขั้นติดตั้งบน iPhone (โชว์ในแอป · ไม่ต้องเปิดเว็บ)
const phoneSetupSteps = [
  'PC: ติดตั้ง "iCloud for Windows" (Microsoft Store) → ล็อกอิน Apple ID เดียวกับ iPhone → เปิด iCloud Drive',
  'iPhone: ติดตั้งแอป "Scriptable" (ฟรี · App Store) แล้วเปิดแอป 1 ครั้ง (iCloud จะสร้างโฟลเดอร์ Scriptable)',
  'PC: เปิด "เชื่อมมือถือ" ด้านบน → สถานะต้องขึ้น "พบโฟลเดอร์" · สคริปต์ NoirManager จะโผล่ใน Scriptable เอง',
  'iPhone: เปิด Scriptable › NoirManager (ครั้งแรกอาจรอ iCloud 1–2 นาที)',
  'iPhone: กดค้างหน้าจอหลัก › + › Scriptable › เลือกขนาด › แตะวิดเจ็ต › Script = NoirManager · ล็อกสกรีนทำแบบเดียวกัน',
];

String _ago(DateTime? t) {
  if (t == null) return '–';
  final m = DateTime.now().difference(t).inMinutes;
  if (m < 1) return 'เมื่อกี้';
  if (m < 60) return '$m นาทีก่อน';
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

class PhoneSyncSection extends StatefulWidget {
  const PhoneSyncSection({super.key, this.service});

  /// null = โหมดข้อมูลตัวอย่าง / เทส → ปิดใช้ (กันเขียนข้อมูลตัวอย่างทับไฟล์จริง)
  final PhoneSyncService? service;

  @override
  State<PhoneSyncSection> createState() => _PhoneSyncSectionState();
}

class _PhoneSyncSectionState extends State<PhoneSyncSection> {
  late final _dir = TextEditingController(text: widget.service?.status.value.dir ?? defaultPhoneSyncDir() ?? '');

  Future<void> _toggle(bool on) async {
    final s = widget.service!;
    final dir = _dir.text.trim();
    if (on && dir.isEmpty) return showToast(context, 'ใส่โฟลเดอร์ก่อน', kind: ToastKind.warn);
    if (on && !Directory(dir).parent.existsSync()) {
      showToast(context, 'ยังไม่พบโฟลเดอร์ Scriptable ใน iCloud · ทำขั้น 1–2 ก่อน', kind: ToastKind.warn);
      return;
    }
    await s.configure(on: on, dir: dir);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final s = widget.service;
    if (s == null) {
      return Text('ใช้ได้กับข้อมูลจริงบน PC เท่านั้น (ตอนนี้เปิดโหมดข้อมูลตัวอย่าง / มือถือ)',
          style: TextStyle(fontSize: 13, color: c.muted));
    }
    return ValueListenableBuilder(
      valueListenable: s.status,
      builder: (context, st, _) {
        final found = st.dir != null && Directory(st.dir!).parent.existsSync();
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          MiniRow(
            icon: Icons.phone_iphone,
            label: 'เชื่อม iPhone ผ่าน iCloud',
            trailing: Switch(key: const Key('phone-sync-on'), value: st.on, onChanged: _toggle),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: TextField(
              key: const Key('phone-sync-dir'),
              controller: _dir,
              enabled: !st.on,
              style: const TextStyle(fontSize: 12.5),
              decoration: const InputDecoration(labelText: 'โฟลเดอร์ (ปิดก่อนแล้วค่อยแก้)', isDense: true),
            ),
          ),
          MiniRow(
            icon: found ? Icons.check_circle_outline : Icons.error_outline,
            label: found ? 'พบโฟลเดอร์ Scriptable ใน iCloud' : 'ยังไม่พบโฟลเดอร์ Scriptable',
            valueText: st.error != null ? 'ผิดพลาด' : null,
          ),
          if (st.on) ...[
            MiniRow(icon: Icons.upload_outlined, label: 'ส่งข้อมูลไปมือถือล่าสุด', valueText: _ago(st.lastWrite)),
            MiniRow(
              icon: Icons.download_outlined,
              label: 'คำสั่งจากมือถือ (ตั้งแต่เปิดแอป)',
              valueText: '${st.applied}',
              onTap: () => s.runNow(),
            ),
          ],
          if (st.error != null) Text(st.error!, style: TextStyle(fontSize: 12, color: c.bad)),
          if (st.recent.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('ล่าสุดจากมือถือ', style: TextStyle(fontSize: 12, color: c.muted)),
            for (final m in st.recent.take(6))
              Text(m, style: TextStyle(fontSize: 12.5, color: m.startsWith('⚠') ? c.warn : c.text)),
          ],
          const SizedBox(height: 10),
          ExpansionTile(
            key: const Key('phone-sync-guide'),
            tilePadding: EdgeInsets.zero,
            title: Text('วิธีติดตั้งบน iPhone (5 ขั้น)', style: TextStyle(fontSize: 14, color: c.text)),
            children: [
              for (final (i, t) in phoneSetupSteps.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(width: 22, child: Text('${i + 1}.', style: TextStyle(color: c.muted))),
                    Expanded(child: Text(t, style: TextStyle(fontSize: 13, color: c.text))),
                  ]),
                ),
              Text('แก้บนมือถือได้: ติ๊กทำแล้ว · เลื่อนงาน · เพิ่มงาน · เช็กอิน · บันทึกรอบสกิล · ให้คะแนนหัวข้อ\n'
                  'PC ต้องเปิดแอปอยู่ สิ่งที่แก้บนมือถือถึงจะเข้า (ปิดไว้ = รอคิว ไม่หาย)',
                  style: TextStyle(fontSize: 12, color: c.muted)),
            ],
          ),
        ]);
      },
    );
  }
}
