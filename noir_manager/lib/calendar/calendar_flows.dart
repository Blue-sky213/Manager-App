/// "ขั้นตอน" ที่ใช้ร่วมกันทั้งหน้าวันนี้และหน้าปฏิทิน
/// แต่ละฟังก์ชัน = เปิดกล่อง → ตรวจกฎ (เช่น เวลาทับ) → บันทึก → แจ้งผลสั้น ๆ
library;

import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../data/study_scope.dart';
import '../study/tutor_plan.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';
import 'holiday_flow.dart';

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

/// วันที่ต้องเช็กเวลาทับ: เลือกวันเอง = ทุกวันที่เลือก · แบบอื่น = ครั้งแรก
List<DateTime> _checkDays(Activity a) {
  if (a.repeat == RepeatKind.dates) {
    return [for (final d in a.dates.values) d.day]..sort();
  }
  final first = dayOnly(a.startDate);
  return occursOn(a, first) ? [first] : const [];
}

/// เช็กเวลาทับทุกวันที่เกี่ยว: true = ไปต่อ · false = กลับไปแก้ฟอร์ม · null = ยกเลิก
Future<bool?> _checkDraft(BuildContext context, CalendarRepository repo,
    NewActivity draft, {int? activityId}) async {
  if (!draft.timed) return true;
  final a = draft.toActivity(id: activityId ?? 0);
  for (final day in _checkDays(a)) {
    final t = timeFor(a, day);
    if (t == null || !context.mounted) continue;
    final start = atMinute(day, t.$1);
    final others = (await repo.occurrencesOn(day))
        .where((o) => activityId == null || o.activityId != activityId)
        .toList();
    final clashes = findOverlaps(others, start, start.add(Duration(minutes: t.$2)));
    if (clashes.isEmpty || !context.mounted) continue;
    final choice = await askOverlap(context, clashes);
    switch (choice) {
      case null:
        return null;
      case OverlapChoice.pickAgain:
        return false;
      case OverlapChoice.allow:
        break;
      case OverlapChoice.moveOthersToInbox:
        for (final o in clashes) {
          await repo.sendToInbox(o.id);
        }
    }
  }
  return true;
}

Future<NewActivity?> _openForm(
  BuildContext context,
  CalendarRepository repo, {
  required DateTime day,
  NewActivity? initial,
  bool editing = false,
}) async {
  final categories = await repo.categories();
  final presets = await repo.presets();
  if (!context.mounted) return null;
  return showActivityDialog(
    context,
    day: day,
    categories: categories,
    presets: presets,
    initial: initial,
    editing: editing,
    onSavePreset: repo.addPreset,
    onDeletePreset: repo.deletePreset,
  );
}

/// เพิ่มงานใหม่ (เริ่มที่วัน [day])
Future<void> addActivityFlow(
    BuildContext context, CalendarRepository repo, DateTime day) async {
  NewActivity? draft;
  while (context.mounted) {
    draft = await _openForm(context, repo, day: day, initial: draft);
    if (draft == null || !context.mounted) return;
    final ok = await _checkDraft(context, repo, draft);
    if (ok == null) return;
    if (!ok) continue; // เปิดฟอร์มเดิมให้แก้เวลา
    await repo.addActivity(draft);
    if (context.mounted) _toast(context, 'เพิ่ม "${draft.name}" แล้ว');
    return;
  }
}

/// แก้ไขงาน (ทั้งแถว): ครั้งที่ยังเป็นแผนตั้งแต่วันนี้จะเปลี่ยนตาม · ที่ทำแล้วไม่ถูกแตะ
Future<void> editActivityFlow(
    BuildContext context, CalendarRepository repo, int activityId) async {
  NewActivity? draft = (await repo.activity(activityId)).toDraft();
  while (context.mounted) {
    draft = await _openForm(context, repo,
        day: draft!.day, initial: draft, editing: true);
    if (draft == null || !context.mounted) return;
    final ok = await _checkDraft(context, repo, draft, activityId: activityId);
    if (ok == null) return;
    if (!ok) continue;
    await repo.updateActivity(activityId, draft);
    if (context.mounted) _toast(context, 'บันทึก "${draft.name}" แล้ว');
    return;
  }
}

/// แก้เวลาเฉพาะครั้งนี้ (วันอื่นของงานเดียวกันไม่เปลี่ยน)
Future<void> editOccurrenceTimeFlow(
    BuildContext context, CalendarRepository repo, Occurrence o) async {
  while (context.mounted) {
    final r = await showOccurrenceTimeDialog(context, o);
    if (r == null || !context.mounted) return;
    final start = atMinute(o.day, r.$1);
    final end = start.add(Duration(minutes: r.$2));
    final ok = await _resolveOverlap(context, repo, o.day, start, end,
        excludeId: o.id);
    if (ok == null) return;
    if (!ok) continue;
    await repo.updateOccurrenceTime(o.id, start, end);
    if (context.mounted) {
      _toast(context, '"${o.title}" ${thaiShortDate(o.day)} → ${fmtTime(start)}–${fmtTime(end)}');
    }
    return;
  }
}

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
    // เมนูยาวกว่าจอ (หน้าต่างเตี้ย) → ให้เลื่อนได้ แทนที่จะล้นขอบ
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
       child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(o.title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            subtitle: Text('$time${thaiShortDate(o.day)}'
                '${o.session == null ? '' : ' · ${o.session!.label}'}'
                ' · ความสำคัญ: ${importanceText(o.importance)}'
                '${o.actualEnd == null ? '' : '\nเลิกจริง ${fmtTime(o.actualEnd!)}'}'
                '${o.reason == null ? '' : '\nยกเลิกเพราะ: ${o.reason}'}'),
          ),
          const Divider(height: 1),
          if (o.status == OccurrenceStatus.planned) ...[
            _tile(ctx, 'done', Icons.check_circle_outline, 'ทำแล้ว'),
            if (o.timed)
              _tile(ctx, 'time', Icons.schedule, 'แก้เวลาเฉพาะวันนี้'),
            _tile(ctx, 'move', Icons.redo, 'เลื่อน'),
            if (o.repeats)
              _tile(ctx, 'shift', Icons.fast_forward, 'เลื่อนไปรอบถัดไป (เนื้อหาไหลไปครั้งหน้า)'),
            _tile(ctx, 'cancel', Icons.block, 'ยกเลิก (ต้องใส่เหตุผล)'),
          ],
          if (o.status == OccurrenceStatus.done && o.subjectId != null && o.timed)
            _tile(ctx, 'actual', Icons.timer_outlined,
                o.actualEnd == null ? 'บันทึกเวลาเลิกจริง' : 'แก้เวลาเลิกจริง'),
          if (o.status == OccurrenceStatus.done)
            _tile(ctx, 'undo', Icons.undo, 'ยังไม่ได้ทำ'),
          if (o.status == OccurrenceStatus.cancelled)
            _tile(ctx, 'undo', Icons.undo, 'คืนเป็นตามแผน'),
          if (o.status == OccurrenceStatus.inbox)
            _tile(ctx, 'schedule', Icons.event, 'เลือกวันแทน'),
          if (o.status == OccurrenceStatus.shifted)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('ครั้งนี้เลื่อนไปรอบถัดไปแล้ว · วันสุดท้ายขยายให้แล้ว'),
            ),
          if (o.status == OccurrenceStatus.moved)
            const ListTile(
              leading: Icon(Icons.info_outline),
              title: Text('ครั้งนี้ถูกเลื่อนไปแล้ว ดูที่วันใหม่'),
            ),
          _tile(ctx, 'edit', Icons.edit_outlined,
              o.repeats ? 'แก้ไขงาน (ทุกครั้งจากนี้ไป)' : 'แก้ไขงาน'),
          _tile(ctx, 'delete', Icons.delete_outline,
              o.repeats ? 'ลบงานซ้ำนี้ทั้งหมด' : 'ลบงานนี้'),
          const SizedBox(height: 8),
        ],
       ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;

  switch (action) {
    case 'done':
      await repo.setDone(o.id, true);
      // รอบติว → ถามว่าบทที่ติวจบหรือยัง (รอบหน้าจะได้ไล่บทถัดไป)
      if (o.kind == ActivityKind.tutor && o.subjectId != null && context.mounted) {
        await _askChapterProgress(context, o.subjectId!, o.id);
      }
      // คาบเรียน → ถามเวลาเลิกจริงต่อเลย (ทำสถิติ)
      else if (o.subjectId != null && o.timed && context.mounted) {
        final end = await askActualEnd(context, o);
        if (end != null) await repo.setActualTimes(o.id, end: end);
      }
    case 'actual':
      final end = await askActualEnd(context, o);
      if (end != null) await repo.setActualTimes(o.id, end: end);
    case 'undo':
      await repo.setDone(o.id, false);
    case 'time':
      await editOccurrenceTimeFlow(context, repo, o);
    case 'edit':
      await editActivityFlow(context, repo, o.activityId);
    case 'move':
      await rescheduleFlow(context, repo, o);
    case 'shift':
      await shiftFlow(context, repo, o);
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


/// หลังติวเสร็จ: บทที่ติวอยู่ "จบแล้ว" หรือ "ยังไม่จบ" → อัปเดตสถานะบท
Future<void> _askChapterProgress(BuildContext context, int subjectId, int occurrenceId) async {
  final study = StudyScope.of(context);
  final chapters = await study.chapters(subjectId);
  final ch = nextChapter(chapters);
  if (ch == null || !context.mounted) return;
  final done = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('ติวไปถึงไหนแล้ว?'),
      content: Text('${ch.name}\nจบบทแล้ว → รอบหน้าไล่บทถัดไป · ยังไม่จบ → รอบหน้าติวบทนี้ต่อ'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ข้าม')),
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยังไม่จบ')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('จบบทแล้ว')),
      ],
    ),
  );
  if (done == null) return;
  final status = done ? ChapterStatus.learned : ChapterStatus.learning;
  await study.setChapterStatus(ch.id, status);
  await study.logTutor(occurrenceId, ch.id, status); // เก็บไว้ทำสถิติ "บทนี้ติวไปกี่รอบ"

  if (context.mounted) {
    _toast(context, done ? '${ch.name} → ติวจบ · ทำแบบทดสอบแล้วใส่คะแนนได้เลย' : '${ch.name} → กำลังติว');
  }
}
