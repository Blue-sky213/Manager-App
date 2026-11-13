import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import '../widgets/mini_form.dart';

/// 🔒 ล็อกงานที่เริ่มไปแล้ว: กรอกผล (ทำแล้ว · บันทึกเรียน) ได้ตามปกติ
/// แต่การแก้ย้อนหลัง (เลื่อน · ยกเลิก · แก้เวลา · แก้ไข · ลบ) ต้องยืนยันก่อน
/// ถ้ามี "คำมั่น" ของงานนั้น กล่องยืนยันยกคำของผู้ใช้เองขึ้นมาถาม

/// ตัวเลือกที่ถือว่า "แก้ย้อนหลัง"
const lockGuarded = {'move', 'shift', 'cancel', 'time', 'edit', 'delete'};

/// ตั้งค่า: เปิด/ปิดการล็อกทั้งแอป (ค่าเริ่มต้น = เปิด)
const lockSettingKey = 'lock_started';

/// คำมั่นของงาน 1 งาน (เก็บในตาราง setting ไม่ต้องเพิ่มตาราง)
String commitmentKey(int activityId) => 'commit:$activityId';

/// รายชื่องานที่มีคำมั่น (คั่นด้วย ,) → ใช้วาด 🔒 โดยไม่ต้องถาม DB ทีละงาน
const commitIdsKey = 'commit_ids';

/// สถานะล็อกที่หน้าจอใช้วาดสัญลักษณ์ (โหลดตอนเปิดแอป + ทุกครั้งที่เปลี่ยน)
class LockState {
  const LockState({this.enabled = true, this.committed = const {}, this.lockCategories = const {}});
  final bool enabled;
  final Set<int> committed;

  /// หมวดที่ตั้ง "ล็อกเมื่อเริ่ม" (ล็อกแม้ปิดล็อกรวม)
  final Set<int> lockCategories;

  bool lockedFor(Occurrence o) => enabled || lockCategories.contains(o.categoryId);
}

LockState lockState = const LockState();

Future<void> refreshLockState(CalendarRepository repo) async {
  final enabled = (await repo.getSetting(lockSettingKey)) != 'off';
  final ids = ((await repo.getSetting(commitIdsKey)) ?? '').split(',').map(int.tryParse).whereType<int>().toSet();
  final cats = {for (final c in await repo.categories()) if (c.lockOnStart) c.id};
  lockState = LockState(enabled: enabled, committed: ids, lockCategories: cats);
  repo.refresh();
}

/// วาด 🔒 ไหม: มีคำมั่น (ตลอด) · หรือเริ่มแล้วแต่ยังไม่กรอกผล (ล็อกอยู่)
bool showLockBadge(Occurrence o, {DateTime? now}) {
  if (!lockState.lockedFor(o)) return false;
  if (lockState.enabled && lockState.committed.contains(o.activityId)) return true;
  return o.status == OccurrenceStatus.planned && isStarted(o, now ?? DateTime.now());
}

Future<void> _setCommitment(CalendarRepository repo, int activityId, String text) async {
  await repo.setSetting(commitmentKey(activityId), text);
  final ids = {...lockState.committed};
  if (text.trim().isEmpty) {
    ids.remove(activityId);
  } else {
    ids.add(activityId);
  }
  await repo.setSetting(commitIdsKey, ids.join(','));
  await refreshLockState(repo);
}

/// เริ่มไปแล้วหรือยัง: มีเวลา = ถึงเวลาเริ่ม · ทั้งวัน = ถึงวันนั้น
bool isStarted(Occurrence o, DateTime now) {
  if (o.status == OccurrenceStatus.inbox) return false;
  final start = o.startAt ?? dayOnly(o.day);
  return !start.isAfter(now);
}

/// ถามก่อนแก้งานที่เริ่มแล้ว · true = ไปต่อได้
Future<bool> confirmUnlock(BuildContext context, CalendarRepository repo, Occurrence o, {DateTime? now}) async {
  final cats = {for (final c in await repo.categories()) if (c.lockOnStart) c.id};
  if ((await repo.getSetting(lockSettingKey)) == 'off' && !cats.contains(o.categoryId)) return true;
  if (!isStarted(o, now ?? DateTime.now())) return true;
  final note = await repo.getSetting(commitmentKey(o.activityId));
  if (!context.mounted) return false;
  final c = context.noir;
  final hasNote = note != null && note.trim().isNotEmpty;
  final res = await showMiniForm<String>(
    context,
    (ctx) => MiniForm(
      title: '🔒 งานนี้เริ่มไปแล้ว',
      menu: [if (hasNote) miniMenu('เลิกตั้งใจข้อนี้', () => Navigator.pop(ctx, 'drop'), danger: true)],
      secondaryLabel: 'แก้ครั้งนี้',
      onSecondary: () => Navigator.pop(ctx, 'edit'),
      primaryLabel: hasNote ? 'ไม่แก้ ทำต่อ' : 'ไม่แก้',
      onPrimary: () => Navigator.pop(ctx),
      children: [
        if (hasNote) ...[
          Text('คุณตั้งใจไว้ว่า', style: TextStyle(color: c.muted)),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.amberBg, borderRadius: BorderRadius.circular(10)),
            child: Text('"${note.trim()}"',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.amberText)),
          ),
          const SizedBox(height: 12),
          Text('คุณต้องการแก้ ถึงแม้ว่าความตั้งใจนี้อาจต้องสะดุด อย่างงั้นหรอ?', style: TextStyle(color: c.text)),
        ] else
          Text('แก้ย้อนหลังจะทำให้บันทึกไม่ตรงกับที่เกิดขึ้นจริง และสถิติคลาดไป · แก้จริงไหม?',
              style: TextStyle(color: c.text)),
      ],
    ),
  );
  if (res == 'drop') await _setCommitment(repo, o.activityId, '');
  return res == 'edit' || res == 'drop';
}

/// ตั้ง / แก้ / ลบ คำมั่นของงาน (คลิกขวา → คำมั่น)
Future<void> editCommitment(BuildContext context, CalendarRepository repo, Occurrence o) async {
  final current = await repo.getSetting(commitmentKey(o.activityId)) ?? '';
  if (!context.mounted) return;
  final ctl = TextEditingController(text: current);
  final res = await showMiniForm<String>(
    context,
    (ctx) => MiniForm(
      title: '🔒 คำมั่นของงานนี้ · ถูกยกขึ้นมาถามเมื่อจะแก้งานที่เริ่มแล้ว',
      menu: [if (current.isNotEmpty) miniMenu('ลบคำมั่น', () => Navigator.pop(ctx, ''), danger: true)],
      primaryLabel: 'บันทึก',
      onPrimary: () => Navigator.pop(ctx, ctl.text.trim()),
      children: [
        MiniBigField(controller: ctl, hint: 'ตั้งใจไว้ว่า… เช่น ทำต่อเนื่องไม่เว้น', fontSize: 18),
      ],
    ),
  );
  if (res != null) await _setCommitment(repo, o.activityId, res);
}
