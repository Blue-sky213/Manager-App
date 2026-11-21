/// ตั้งค่า › ข้อมูล › ล้างข้อมูลแล้วเริ่มใหม่ (รอบ 10C)
/// สำรองก่อนเสมอ + ต้องพิมพ์ "ลบทั้งหมด" · ปุ่มใส่แผน / สารบัญ เอาออกรอบ 21 (ใช้นำเข้าไฟล์แทน รอบ 22)
library;

import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../data/backup.dart';
import '../data/noir_plan.dart' show resetForFreshStart;
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';

const resetWord = 'ลบทั้งหมด';

class FreshStartSection extends StatefulWidget {
  const FreshStartSection({super.key, this.backup});
  final BackupService? backup;

  @override
  State<FreshStartSection> createState() => _FreshStartSectionState();
}

class _FreshStartSectionState extends State<FreshStartSection> {
  bool _busy = false;

  Future<void> _reset() async {
    final typed = TextEditingController();
    var showErr = false;
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final c = ctx.noir;
        return MiniForm(
          title: 'ล้างข้อมูลแล้วเริ่มใหม่',
          primaryLabel: 'สำรอง + ลบ',
          onPrimary: () {
            if (typed.text.trim() != resetWord) return setLocal(() => showErr = true);
            Navigator.pop(ctx, true);
          },
          onSecondary: () => Navigator.pop(ctx, false),
          children: [
            Text('ลบ: กิจกรรม/งานในปฏิทินทั้งหมด (รวมคาบเรียน) · วิชา + แผน 4 ปี · เทอม · วันหยุด',
                style: TextStyle(fontSize: 13, color: c.bad)),
            const SizedBox(height: 4),
            Text('ไม่ลบ: สติกเกอร์ · เช็กอิน · หมวด · เงิน · โปรเจกต์ · สกิล · ตั้งค่า · สำรองข้อมูลให้ก่อนอัตโนมัติ (กู้คืนได้)',
                style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 10),
            MiniBigField(key: const Key('fresh-confirm'), controller: typed, hint: 'พิมพ์ "$resetWord"', fontSize: 18),
            if (showErr) Text('พิมพ์ "$resetWord" ให้ตรงก่อน', style: TextStyle(fontSize: 12, color: c.bad)),
          ],
        );
      }),
    );
    if (ok != true || !mounted) return;
    final cal = CalendarScope.of(context);
    final study = StudyScope.of(context);
    setState(() => _busy = true);
    try {
      // สำรองก่อนเสมอ · สำรองไม่ได้ = ไม่ลบ
      await widget.backup?.backupNow(label: 'before_reset');
      final r = await resetForFreshStart(cal, study);
      if (mounted) {
        showToast(context, 'ลบแล้ว: กิจกรรม ${r.activities} · วิชา ${r.subjects} · เทอม ${r.terms} · วันหยุด ${r.holidays}',
            kind: ToastKind.success);
      }
    } catch (e) {
      if (mounted) showToast(context, 'ล้างไม่สำเร็จ (ยังไม่ได้ลบอะไร ถ้าสำรองไม่ผ่าน): $e', kind: ToastKind.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MiniRow(
          key: const Key('fresh-reset'),
          icon: Icons.delete_sweep_outlined,
          label: 'ล้างข้อมูลแล้วเริ่มใหม่',
          valueText: 'สำรองให้ก่อน',
          last: true,
          onTap: _busy ? null : _reset,
        ),
      ]);
}
