/// ตั้งค่า › เริ่มใหม่ + แผนของนัวร์ (รอบ 10C)
/// ล้าง = สำรองก่อนเสมอ + ต้องพิมพ์ "ลบทั้งหมด" · ใส่แผน = กดซ้ำได้ ไม่ซ้อน
library;

import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../data/backup.dart';
import '../data/noir_plan.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../widgets/dialogs.dart';
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
          title: 'ล้างแล้วเริ่มใหม่',
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

  Future<void> _plan() async {
    final ok = await confirmMini(context,
        title: 'ใส่แผนของนัวร์',
        message: 'งาน mecsteam · IELTS · DaVinci · Canva · ไลฟ์ · อ่านหนังสือ (6 เดือน) + สกิล + เว็บ mecsteam.com · ของที่มีชื่อเดียวกันอยู่แล้วจะข้าม',
        okLabel: 'ใส่แผน');
    if (!ok || !mounted) return;
    final cal = CalendarScope.of(context);
    setState(() => _busy = true);
    try {
      final r = await applyNoirPlan(cal, DateTime.now());
      if (mounted) {
        showToast(context, 'ใส่แล้ว: งานซ้ำ ${r.activities} · สกิล ${r.skills} · ขั้นงานเว็บ ${r.tasks}', kind: ToastKind.success);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MiniRow(
          key: const Key('fresh-plan'),
          icon: Icons.event_note_outlined,
          label: 'ใส่แผนของนัวร์ (6 เดือน)',
          onTap: _busy ? null : _plan,
        ),
        MiniRow(
          key: const Key('fresh-reset'),
          icon: Icons.delete_sweep_outlined,
          label: 'ล้างแล้วเริ่มใหม่ (สำรองก่อน)',
          last: true,
          onTap: _busy ? null : _reset,
        ),
      ]);
}
