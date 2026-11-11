import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';

/// 🔒 ล็อกงานที่เริ่มไปแล้ว: กรอกผล (ทำแล้ว · บันทึกเรียน) ได้ตามปกติ
/// แต่การแก้ย้อนหลัง (เลื่อน · ยกเลิก · แก้เวลา · แก้ไข · ลบ) ต้องยืนยันก่อน
/// ถ้ามี "คำมั่น" ของงานนั้น กล่องยืนยันยกคำของผู้ใช้เองขึ้นมาถาม

/// ตัวเลือกที่ถือว่า "แก้ย้อนหลัง"
const lockGuarded = {'move', 'shift', 'cancel', 'time', 'edit', 'delete'};

/// ตั้งค่า: เปิด/ปิดการล็อกทั้งแอป (ค่าเริ่มต้น = เปิด)
const lockSettingKey = 'lock_started';

/// คำมั่นของงาน 1 งาน (เก็บในตาราง setting ไม่ต้องเพิ่มตาราง)
String commitmentKey(int activityId) => 'commit:$activityId';

/// รายการงานที่มีคำมั่น (คั่นด้วย ,) ไว้ให้หน้าปฏิทินรู้ว่าต้องติด 🔒 โดยไม่ต้องถามทีละงาน
const commitIdsKey = 'commit_ids';

/// สถานะล็อกที่หน้าจอใช้วาดสัญลักษณ์ (โหลดตอนเปิดแอป · อัปเดตทันทีเมื่อแก้)
class LockInfo {
  const LockInfo({this.enabled = true, this.committed = const {}});
  final bool enabled;
  final Set<int> committed;
}

final lockInfo = ValueNotifier<LockInfo>(const LockInfo());

Future<void> refreshLockInfo(CalendarRepository repo) async {
  final enabled = (await repo.getSetting(lockSettingKey)) != 'off';
  final ids = ((await repo.getSetting(commitIdsKey)) ?? '')
      .split(',')
      .map((e) => int.tryParse(e.trim()))
      .whereType<int>()
      .toSet();
  lockInfo.value = LockInfo(enabled: enabled, committed: ids);
}

/// บันทึกคำมั่น + อัปเดตรายการงานที่มีคำมั่น (ว่าง = ลบ)
Future<void> saveCommitment(CalendarRepository repo, int activityId, String note) async {
  final ids = {...lockInfo.value.committed};
  if (note.trim().isEmpty) {
    ids.remove(activityId);
  } else {
    ids.add(activityId);
  }
  lockInfo.value = LockInfo(enabled: lockInfo.value.enabled, committed: ids);
  await repo.setSetting(commitIdsKey, ids.join(','));
  await repo.setSetting(commitmentKey(activityId), note.trim());
}

/// ล็อกอยู่ไหม (ใช้วาดไอคอน 🔒): ล็อกเปิด + งานยังไม่กรอกผล + ถึงเวลาเริ่มแล้ว
bool isLockedNow(Occurrence o, DateTime now) =>
    lockInfo.value.enabled && o.status == OccurrenceStatus.planned && isStarted(o, now);

bool hasCommitment(Occurrence o) => lockInfo.value.committed.contains(o.activityId);

/// เริ่มไปแล้วหรือยัง: มีเวลา = ถึงเวลาเริ่ม · ทั้งวัน = ถึงวันนั้น
bool isStarted(Occurrence o, DateTime now) {
  if (o.status == OccurrenceStatus.inbox) return false;
  final start = o.startAt ?? dayOnly(o.day);
  return !start.isAfter(now);
}

/// ถามก่อนแก้งานที่เริ่มแล้ว · true = ไปต่อได้
Future<bool> confirmUnlock(BuildContext context, CalendarRepository repo, Occurrence o, {DateTime? now}) async {
  if ((await repo.getSetting(lockSettingKey)) == 'off') return true;
  if (!isStarted(o, now ?? DateTime.now())) return true;
  final note = await repo.getSetting(commitmentKey(o.activityId));
  if (!context.mounted) return false;
  final c = context.noir;
  final hasNote = note != null && note.trim().isNotEmpty;
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('🔒 งานนี้เริ่มไปแล้ว'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        ]),
      ),
      actions: [
        if (hasNote)
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'drop'),
            style: TextButton.styleFrom(foregroundColor: c.bad),
            child: const Text('เลิกตั้งใจข้อนี้'),
          ),
        TextButton(onPressed: () => Navigator.pop(ctx, 'edit'), child: const Text('แก้ครั้งนี้')),
        FilledButton(onPressed: () => Navigator.pop(ctx), child: Text(hasNote ? 'ไม่แก้ ทำต่อ' : 'ไม่แก้')),
      ],
    ),
  );
  if (res == 'drop') await saveCommitment(repo, o.activityId, '');
  return res == 'edit' || res == 'drop';
}

/// ตั้ง / แก้ / ลบ คำมั่นของงาน (คลิกขวา → คำมั่น)
Future<void> editCommitment(BuildContext context, CalendarRepository repo, Occurrence o) async {
  final current = await repo.getSetting(commitmentKey(o.activityId)) ?? '';
  if (!context.mounted) return;
  final ctl = TextEditingController(text: current);
  final res = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('🔒 คำมั่นของงานนี้'),
      content: SizedBox(
        width: 420,
        child: TextField(
          controller: ctl,
          autofocus: true,
          maxLines: 2,
          decoration: const InputDecoration(
            labelText: 'ตั้งใจไว้ว่า…',
            hintText: 'เช่น ผมต้องการทำต่อเนื่องโดยไม่เว้น',
            helperText: 'ใช้กับงานนี้ทุกครั้ง · ติด 🔒 หน้าชื่องาน · ถูกยกขึ้นมาถามเมื่อจะแก้',
          ),
        ),
      ),
      actions: [
        if (current.isNotEmpty) TextButton(onPressed: () => Navigator.pop(ctx, ''), child: const Text('ลบคำมั่น')),
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
        FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('บันทึก')),
      ],
    ),
  );
  if (res != null) await saveCommitment(repo, o.activityId, res);
}
