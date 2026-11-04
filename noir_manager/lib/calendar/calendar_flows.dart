/// "ขั้นตอน" ที่ใช้ร่วมกันทั้งหน้าวันนี้และหน้าปฏิทิน
/// แต่ละฟังก์ชัน = เปิดกล่อง → ตรวจกฎ (เช่น เวลาทับ) → บันทึก → แจ้งผลสั้น ๆ
library;

import 'package:flutter/material.dart';

import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';

void _toast(BuildContext context, String text) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

/// ตรวจเวลาทับ: คืน true = ไปต่อได้ · false = ให้ผู้ใช้เลือกเวลาใหม่ · null = ยกเลิกทั้งหมด
Future<bool?> _resolveOverlap(
  BuildContext context,
  CalendarRepository repo,
  DateTime day,
  DateTime start,
  DateTime end, {
  int? excludeId,
}) async {
  final clashes =
      findOverlaps(await repo.occurrencesOn(day), start, end, excludeId: excludeId);
  if (clashes.isEmpty || !context.mounted) return true;
  final choice = await askOverlap(context, clashes);
  switch (choice) {
    case null:
      return null;
    case OverlapChoice.pickAgain:
      return false;
    case OverlapChoice.allow:
      return true;
    case OverlapChoice.moveOthersToInbox:
      for (final o in clashes) {
        await repo.sendToInbox(o.id);
      }
      return true;
  }
}

/// เพิ่มงานใหม่ (เริ่มที่วัน [day])
Future<void> addActivityFlow(
    BuildContext context, CalendarRepository repo, DateTime day) async {
  final categories = await repo.categories();
  NewActivity? draft;
  while (context.mounted) {
    draft = await showAddActivityDialog(context,
        day: day, categories: categories, initial: draft);
    if (draft == null || !context.mounted) return;

    if (draft.timed && occursOn(_probe(draft), draft.day)) {
      final start = atMinute(draft.day, draft.startMinute!);
      final ok = await _resolveOverlap(context, repo, draft.day, start,
          start.add(Duration(minutes: draft.durationMin!)));
      if (ok == null) return;
      if (!ok) continue; // เปิดกล่องเดิมให้เลือกเวลาใหม่
    }

    await repo.addActivity(draft);
    if (context.mounted) {
      _toast(context, 'เพิ่ม "${draft.name}" แล้ว');
    }
    return;
  }
}

/// สร้าง Activity ชั่วคราวจาก draft เพื่อเช็กว่าวันแรกมีงานจริงไหม (เช่น ทุกสัปดาห์ แต่วันแรกไม่ใช่วันที่เลือก)
Activity _probe(NewActivity d) => Activity(
      id: 0,
      name: d.name,
      categoryId: d.categoryId,
      importance: d.importance,
      timed: d.timed,
      startMinute: d.startMinute,
      durationMin: d.durationMin,
      repeat: d.repeat,
      weekdays: d.weekdays,
      startDate: d.day,
    );

/// เลื่อนงาน (หรือเลือกวันแทนให้งานใน Reminder Inbox)
Future<void> rescheduleFlow(
  BuildContext context,
  CalendarRepository repo,
  Occurrence o, {
  bool fromInbox = false,
}) async {
  while (context.mounted) {
    final r = await showRescheduleDialog(context, o, fromInbox: fromInbox);
    if (r == null || !context.mounted) return;

    if (r.toInbox) {
      await repo.sendToInbox(o.id);
      if (context.mounted) _toast(context, 'ย้าย "${o.title}" ไป Reminder Inbox แล้ว');
      return;
    }

    if (r.series) {
      final start = atMinute(o.day, r.startMinute!);
      final ok = await _resolveOverlap(context, repo, o.day, start,
          start.add(Duration(minutes: r.durationMin!)),
          excludeId: o.id);
      if (ok == null) return;
      if (!ok) continue;
      await repo.moveSeries(o.activityId, o.day, r.startMinute!, r.durationMin!);
      if (context.mounted) {
        _toast(context,
            'เปลี่ยน "${o.title}" เป็น ${fmtMinute(r.startMinute!)} ตั้งแต่ ${thaiShortDate(o.day)}');
      }
      return;
    }

    DateTime? start;
    DateTime? end;
    if (r.startMinute != null) {
      start = atMinute(r.day!, r.startMinute!);
      end = start.add(Duration(minutes: r.durationMin!));
      final ok = await _resolveOverlap(context, repo, r.day!, start, end,
          excludeId: o.id);
      if (ok == null) return;
      if (!ok) continue;
    }
    await repo.moveOccurrence(o.id, r.day!, start: start, end: end);
    if (context.mounted) {
      _toast(context,
          'เลื่อน "${o.title}" ไป ${thaiShortDate(r.day!)}${start == null ? '' : ' ${fmtTime(start)}'}');
    }
    return;
  }
}

/// แตะงาน 1 ครั้ง → แผ่นตัวเลือกด้านล่าง
Future<void> openOccurrenceActions(
    BuildContext context, CalendarRepository repo, Occurrence o) async {
  final time = o.timed ? '${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)} · ' : '';
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(o.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: Text('$time${thaiShortDate(o.day)} · ความสำคัญ: ${importanceText(o.importance)}'
                '${o.reason == null ? '' : '\nยกเลิกเพราะ: ${o.reason}'}'),
          ),
          const Divider(height: 1),
          if (o.status == OccurrenceStatus.planned) ...[
            _tile(ctx, 'done', Icons.check_circle_outline, 'ทำแล้ว'),
            _tile(ctx, 'move', Icons.redo, 'เลื่อน'),
            _tile(ctx, 'cancel', Icons.block, 'ยกเลิก (ต้องใส่เหตุผล)'),
          ],
          if (o.status == OccurrenceStatus.done)
            _tile(ctx, 'undo', Icons.undo, 'ยังไม่ได้ทำ'),
          if (o.status == OccurrenceStatus.cancelled)
            _tile(ctx, 'undo', Icons.undo, 'คืนเป็นตามแผน'),
          if (o.status == OccurrenceStatus.inbox)
            _tile(ctx, 'schedule', Icons.event, 'เลือกวันแทน'),
          if (o.status == OccurrenceStatus.moved)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('ครั้งนี้ถูกเลื่อนไปแล้ว ดูที่วันใหม่'),
            ),
          _tile(ctx, 'delete', Icons.delete_outline,
              o.repeats ? 'ลบงานซ้ำนี้ทั้งหมด' : 'ลบงานนี้'),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'done':
      await repo.setDone(o.id, true);
    case 'undo':
      await repo.setDone(o.id, false);
    case 'move':
      await rescheduleFlow(context, repo, o);
    case 'schedule':
      await rescheduleFlow(context, repo, o, fromInbox: true);
    case 'cancel':
      final reason = await askCancelReason(context, o);
      if (reason != null) await repo.cancel(o.id, reason);
    case 'delete':
      if (await confirmDelete(context, o.title)) {
        await repo.deleteActivity(o.activityId);
      }
  }
}

Widget _tile(BuildContext ctx, String value, IconData icon, String label) =>
    ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: () => Navigator.pop(ctx, value),
    );

/// แก้เวลานอน/ตื่น
Future<void> editLifeBaseFlow(BuildContext context, CalendarRepository repo) async {
  final current = await repo.lifeBase();
  if (!context.mounted) return;
  final updated = await showLifeBaseDialog(context, current);
  if (updated != null) await repo.setLifeBase(updated);
}
