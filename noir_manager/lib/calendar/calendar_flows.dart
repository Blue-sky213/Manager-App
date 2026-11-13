/// "ขั้นตอน" ที่ใช้ร่วมกันทั้งหน้าวันนี้และหน้าปฏิทิน
/// แต่ละฟังก์ชัน = เปิดกล่อง → ตรวจกฎ (เช่น เวลาทับ) → บันทึก → แจ้งผลสั้น ๆ
library;

import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../data/study_scope.dart';
import '../shell/app_nav.dart';
import 'category_ui.dart' show createCategoryFlow;
import 'lock_flow.dart';
import '../study/class_log.dart';
import '../study/tutor_plan.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import 'achievements.dart';
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
  // เลือกวันเอง: ถามทีละวันไปแล้วใน _resolveDates
  if (!draft.timed || draft.repeat == RepeatKind.dates) return true;
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

/// งานของวันอื่น ๆ ที่ทับช่วงเวลา (ไม่นับงานตัวเอง)
Future<List<Occurrence>> _clashesOn(CalendarRepository repo, DateTime day, int start, int dur, int? activityId) async {
  final others =
      (await repo.occurrencesOn(day)).where((o) => activityId == null || o.activityId != activityId).toList();
  final s = atMinute(day, start);
  return findOverlaps(others, s, s.add(Duration(minutes: dur)));
}

/// เลือกวันเอง + ล็อกเวลา: รวมวันที่ชนแล้วถามทีละวันในกล่องเดียว
/// คืน (ok, draft ใหม่) · ok: true = ไปต่อ · false = กลับไปแก้ฟอร์ม · null = ยกเลิก
Future<(bool?, NewActivity)> _resolveDates(
    BuildContext context, CalendarRepository repo, NewActivity draft, {int? activityId}) async {
  if (!draft.timed || draft.repeat != RepeatKind.dates) return (true, draft);
  final a = draft.toActivity(id: activityId ?? 0);
  final clashes = <(DateTime, List<Occurrence>)>[];
  for (final d in draft.dates) {
    final day = dayOnly(d.day);
    final t = timeFor(a, day);
    if (t == null) continue;
    final found = await _clashesOn(repo, day, t.$1, t.$2, activityId);
    if (found.isNotEmpty) clashes.add((day, found));
  }
  if (clashes.isEmpty || !context.mounted) return (true, draft);
  final ans = await askDayClashes(context, clashes, draft.dates.length);
  if (ans == null) return (null, draft);
  if (ans.back) return (false, draft);
  final skip = <DateTime>{};
  for (final (day, found) in clashes) {
    switch (ans.picks[day]!) {
      case DayClashChoice.skip:
        skip.add(day);
      case DayClashChoice.allow:
        break;
      case DayClashChoice.moveOthers:
        for (final o in found) {
          await repo.sendToInbox(o.id);
        }
    }
  }
  return (true, draft.withDates([for (final d in draft.dates) if (!skip.contains(dayOnly(d.day))) d]));
}

/// ฟอร์มเปิดพร้อมตัวเช็กวันชน (ใช้ในตารางติ๊กวัน)
Future<Set<DateTime>> Function(List<DateTime>, int, int) _clashChecker(CalendarRepository repo, int? activityId) =>
    (days, start, dur) async => {
          for (final d in days)
            if ((await _clashesOn(repo, d, start, dur, activityId)).isNotEmpty) d,
        };

Future<NewActivity?> _openForm(
  BuildContext context,
  CalendarRepository repo, {
  required DateTime day,
  NewActivity? initial,
  bool editing = false,
  int? activityId,
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
    onUpdatePreset: repo.updatePreset,
    onDeletePreset: repo.deletePreset,
    clashDays: _clashChecker(repo, activityId),
    onCreateCategory: (ctx) => createCategoryFlow(ctx, repo),
  );
}

/// เพิ่มงานใหม่ (เริ่มที่วัน [day])
Future<void> addActivityFlow(
    BuildContext context, CalendarRepository repo, DateTime day) async {
  NewActivity? draft;
  while (context.mounted) {
    draft = await _openForm(context, repo, day: day, initial: draft);
    if (draft == null || !context.mounted) return;
    final (datesOk, trimmed) = await _resolveDates(context, repo, draft);
    if (datesOk == null) return;
    if (!datesOk) continue;
    if (trimmed.repeat == RepeatKind.dates && trimmed.dates.isEmpty) {
      if (context.mounted) _toast(context, 'ข้ามทุกวัน · ไม่ได้เพิ่ม "${draft.name}"');
      return;
    }
    draft = trimmed;
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
        day: draft!.day, initial: draft, editing: true, activityId: activityId);
    if (draft == null || !context.mounted) return;
    final (datesOk, trimmed) = await _resolveDates(context, repo, draft, activityId: activityId);
    if (datesOk == null) return;
    if (!datesOk) continue;
    if (trimmed.repeat == RepeatKind.dates && trimmed.dates.isEmpty) {
      if (context.mounted) _toast(context, 'ข้ามทุกวัน · ไม่ได้บันทึก');
      return;
    }
    draft = trimmed;
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

/// เลื่อนงาน (หรือเลือกวันแทนให้งานใน Updates)
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
      if (context.mounted) _toast(context, 'ย้าย "${o.title}" ไป Updates แล้ว');
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

/// คลิกซ้าย = "กรอกผล" ของงานครั้งนี้: ทำแล้ว (คาบเรียน = บันทึกเรียนในตัว) · เลื่อน · ยกเลิก (วันหยุด/ติดธุระ)
List<ContextItem<String>> resultItems(Occurrence o) => [
      if (o.status == OccurrenceStatus.planned) ctxItem('done', Icons.check_circle_outline, 'ทำแล้ว'),
      // คาบเรียน: "ทำแล้ว" เปิดแผ่นบันทึกเรียนในตัว → ทำแล้วจึงมี "แก้บันทึก" (รวมเวลาเลิกจริง)
      if (o.kind == ActivityKind.classSession && o.subjectId != null && o.status == OccurrenceStatus.done)
        ctxItem('classlog', Icons.menu_book_outlined, 'แก้บันทึกเรียน · เวลาเลิก'),
      if (o.status == OccurrenceStatus.done && o.subjectId != null && o.timed && o.kind != ActivityKind.classSession)
        ctxItem('actual', Icons.timer_outlined, o.actualEnd == null ? 'บันทึกเวลาเลิกจริง' : 'แก้เวลาเลิกจริง'),
      // งานยืดหยุ่น: วันนี้ไม่มีงานจริง → ว่าง (ไม่ใช่ยกเลิก · ไม่นับพลาด)
      if (o.flexible && o.timed && o.status == OccurrenceStatus.planned)
        ctxItem('free', Icons.pause_circle_outline, o.hasFree ? 'แก้ช่วงว่าง / ยกเลิกว่าง' : 'วันนี้ว่าง (ไม่มีงานจริง)'),
      if (o.status == OccurrenceStatus.planned) ...[
        ctxItem('move', Icons.redo, 'เลื่อน'),
        if (o.repeats) ctxItem('shift', Icons.fast_forward, 'เลื่อนไปรอบถัดไป (เนื้อหาไหลไปครั้งหน้า)'),
        ctxItem('cancel', Icons.block, 'ยกเลิก · วันหยุด / ติดธุระ (ใส่เหตุผล)'),
      ],
      if (o.status == OccurrenceStatus.done) ctxItem('undo', Icons.undo, 'ยังไม่ได้ทำ'),
      if (o.status == OccurrenceStatus.cancelled) ctxItem('undo', Icons.undo, 'คืนเป็นตามแผน'),
      if (o.status == OccurrenceStatus.inbox) ctxItem('schedule', Icons.event, 'เลือกวันแทน'),
    ];

/// คลิกขวา = "แก้ / ตรวจสอบ": รายละเอียด · เกี่ยวกับวิชา · แก้เวลา · แก้ไขงาน · ลบ
List<ContextItem<String>> modifyItems(Occurrence o) => [
      ctxItem('details', Icons.info_outline, 'ดูรายละเอียด'),
      if (o.subjectId != null) ctxItem('subject', Icons.school_outlined, 'เกี่ยวกับวิชา (เปิดหน้าวิชา)'),
      if (o.status == OccurrenceStatus.planned && o.timed) ctxItem('time', Icons.schedule, 'แก้เวลาเฉพาะวันนี้'),
      ctxItem('commit', Icons.lock_outline, 'คำมั่น (ล็อก)…'),
      ctxItem('edit', Icons.edit_outlined, o.repeats ? 'แก้ไขงาน (ทุกครั้งจากนี้ไป)' : 'แก้ไขงาน'),
      ctxItem('delete', Icons.delete_outline, o.repeats ? 'ลบงานซ้ำนี้ทั้งหมด' : 'ลบงานนี้', danger: true),
    ];

/// คลิกซ้ายที่งาน → เมนู "กรอกผล" ตรงตำแหน่งเมาส์ · ไม่มีอะไรให้กรอก (เช่น ถูกเลื่อนไปแล้ว) → รายละเอียด
/// แก้ไข / ไปหน้าวิชา อยู่ที่คลิกขวา ไม่ซ้ำกัน
Future<void> openOccurrence(BuildContext context, CalendarRepository repo, Occurrence o, {Offset? at}) async {
  final items = resultItems(o);
  if (items.isEmpty) {
    await showOccurrenceDetails(context, o);
    return;
  }
  final action = await showContextMenuAt<String>(context, at ?? lastPointerDown, items);
  if (action == null || !context.mounted) return;
  await runOccurrenceAction(context, repo, o, action);
}

/// แผ่นรายละเอียดงาน 1 ครั้ง (ดูอย่างเดียว)
Future<void> showOccurrenceDetails(BuildContext context, Occurrence o) {
  final c = context.noir;
  final time = o.timed ? '${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)} · ' : '';
  final status = switch (o.status) {
    OccurrenceStatus.planned => 'ตามแผน',
    OccurrenceStatus.done => 'ทำแล้ว',
    OccurrenceStatus.cancelled => 'ยกเลิก',
    OccurrenceStatus.inbox => 'อยู่ใน Updates (ยังไม่มีวัน)',
    OccurrenceStatus.moved => 'ถูกเลื่อนไปวันอื่นแล้ว',
    OccurrenceStatus.shifted => 'เลื่อนไปรอบถัดไปแล้ว',
  };
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(o.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('$time${thaiShortDate(o.day)}${o.session == null ? '' : ' · ${o.session!.label}'}'),
            Text('สถานะ: $status · ความสำคัญ: ${importanceText(o.importance)}'),
            if (o.actualEnd != null) Text('เลิกจริง ${fmtTime(o.actualEnd!)}'),
            if (o.reason != null) Text('ยกเลิกเพราะ: ${o.reason}'),
            const SizedBox(height: 12),
            Text('คลิก = กรอกผล (ทำแล้ว + บันทึกเรียน · เลื่อน · ยกเลิก) · คลิกขวา = แก้ไข · เกี่ยวกับวิชา · ลบ',
                style: TextStyle(fontSize: 13, color: c.muted)),
          ],
        ),
      ),
    ),
  );
}

/// คลิกขวา / กดค้าง ([at] = ตำแหน่งเมาส์) → เมนูแก้ไข / ตรวจสอบตรงนั้น
Future<void> openOccurrenceActions(
    BuildContext context, CalendarRepository repo, Occurrence o, {required Offset at}) async {
  final action = await showContextMenuAt<String>(context, at, modifyItems(o));
  if (action == null || !context.mounted) return;
  await runOccurrenceAction(context, repo, o, action);
}

/// ทำตามตัวเลือกที่เลือกจากเมนูซ้าย / ขวา
Future<void> runOccurrenceAction(BuildContext context, CalendarRepository repo, Occurrence o, String action) async {
  // 🔒 งานที่เริ่มแล้ว: แก้ย้อนหลังต้องยืนยัน (กรอกผลไม่ต้อง)
  if (lockGuarded.contains(action) && !await confirmUnlock(context, repo, o)) return;
  if (!context.mounted) return;
  switch (action) {
    case 'commit':
      await editCommitment(context, repo, o);
    case 'details':
      await showOccurrenceDetails(context, o);
    case 'subject':
      subjectJump.go(o.subjectId!);
    case 'free':
      await freeTimeFlow(context, repo, o);
    case 'done':
      await repo.setDone(o.id, true);
      // ทำก่อนเวลา (เช่น ทำตอนว่างจากงาน) → บันทึกเวลาที่ทำจริง · ช่องเดิมขึ้น "ทำไปแล้ว"
      if (o.timed && o.subjectId == null && DateTime.now().isBefore(o.startAt!) && dayOnly(DateTime.now()) == o.day) {
        final now = DateTime.now();
        final len = o.endAt!.difference(o.startAt!);
        final start = now.subtract(len).isBefore(dayOnly(now)) ? dayOnly(now) : now.subtract(len);
        await repo.setActualTimes(o.id, start: start, end: now);
        if (context.mounted) _toast(context, 'ทำก่อนเวลา · ${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)} ว่างแล้ว');
      }
      // รอบติว → ถามว่าบทที่ติวจบหรือยัง (รอบหน้าจะได้ไล่บทถัดไป)
      if (o.kind == ActivityKind.tutor && o.subjectId != null && context.mounted) {
        await _askChapterProgress(context, o.subjectId!, o.id);
      }
      // คาบเรียน → แผ่นเดียว: เรียนถึงไหน + เวลาเลิกจริง ("แค่ทำแล้ว" ข้ามได้ · ปิดถามได้ในตั้งค่า)
      else if (o.kind == ActivityKind.classSession && o.subjectId != null && context.mounted) {
        final ask = await StudyScope.of(context).getSetting(askClassLogKey);
        if (ask != 'off' && context.mounted) {
          await showClassLogDialog(context,
              subjectId: o.subjectId!, day: o.day, occurrence: o.copyWithStatus(OccurrenceStatus.done), justDone: true);
        }
      }
      // งานผูกวิชาอื่น ๆ → ถามเวลาเลิกจริง (ทำสถิติ)
      else if (o.subjectId != null && o.timed && context.mounted) {
        final end = await askActualEnd(context, o);
        if (end != null) await repo.setActualTimes(o.id, end: end);
      }
      // ความสำเร็จ: งานสุดท้ายของวันเสร็จ → แถบแจ้งสั้นด้านล่าง
      if (context.mounted) await celebrateIfDayComplete(context, repo, o.day);
    case 'classlog':
      final logs = await StudyScope.of(context).classLogs(o.subjectId!);
      if (!context.mounted) return;
      await showClassLogDialog(context,
          subjectId: o.subjectId!,
          day: o.day,
          occurrence: o,
          existing: logs.where((l) => l.occurrenceId == o.id).firstOrNull);
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

/// งานยืดหยุ่น "วันนี้ว่าง": ทั้งช่วง / บางช่วง → แล้วเสนอดึงงานอื่นมาทำในช่วงว่าง
Future<void> freeTimeFlow(BuildContext context, CalendarRepository repo, Occurrence o) async {
  final r = await askFreeRange(context, o);
  if (r == null || !context.mounted) return;
  if (r.clear) {
    await repo.setFree(o.id, null, null);
    if (context.mounted) _toast(context, 'ยกเลิกว่าง · "${o.title}" กลับเป็นตามแผน');
    return;
  }
  await repo.setFree(o.id, r.start, r.end);
  if (!context.mounted) return;
  // ช่วงว่าง → งานที่ดึงมาทำได้: วันนี้หลังช่วงว่าง + พรุ่งนี้ · ยาวไม่เกินช่วงว่าง
  final free = r.end!.difference(r.start!).inMinutes;
  final today = await repo.occurrencesOn(o.day);
  final tomorrow = await repo.occurrencesOn(o.day.add(const Duration(days: 1)));
  final cands = [
    for (final x in [...today, ...tomorrow])
      if (x.id != o.id &&
          x.status == OccurrenceStatus.planned &&
          x.timed &&
          !x.startAt!.isBefore(r.end!) &&
          x.kind != ActivityKind.classSession &&
          x.endAt!.difference(x.startAt!).inMinutes <= free)
        x,
  ]..sort((a, b) => a.startAt!.compareTo(b.startAt!));
  if (!context.mounted) return;
  final pick = await askPullIn(context, free: (r.start!, r.end!), candidates: cands.take(6).toList());
  if (pick == null || !context.mounted) return;
  final len = pick.endAt!.difference(pick.startAt!);
  await repo.moveOccurrence(pick.id, o.day, start: r.start, end: r.start!.add(len));
  if (context.mounted) _toast(context, 'ดึง "${pick.title}" มาทำ ${fmtTime(r.start!)}–${fmtTime(r.start!.add(len))}');
}

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
  final done = await showMiniForm<bool>(
    context,
    (ctx) => MiniForm(
      title: 'ติวไปถึงไหนแล้ว? · ${ch.name}',
      secondaryLabel: 'ข้าม',
      primaryLabel: 'จบบทแล้ว',
      onPrimary: () => Navigator.pop(ctx, true),
      children: [
        MiniRow(label: 'ยังไม่จบ', valueText: 'รอบหน้าติวบทนี้ต่อ', last: true, onTap: () => Navigator.pop(ctx, false)),
        const MiniLabel('จบบทแล้ว → รอบหน้าไล่บทถัดไป'),
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

/// ห่อกล่องงาน: คลิกขวา / กดค้าง → เมนูตัวเลือกตรงตำแหน่งเมาส์ (คลิกซ้ายยังเป็นของกล่องเดิม)
class OccurrenceMenuArea extends StatelessWidget {
  const OccurrenceMenuArea({super.key, required this.o, required this.child});

  final Occurrence o;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    void open(Offset at) => openOccurrenceActions(context, CalendarScope.of(context), o, at: at);
    return GestureDetector(
      onSecondaryTapUp: (d) => open(d.globalPosition),
      onLongPressStart: (d) => open(d.globalPosition),
      child: child,
    );
  }
}

/// ทำครบทุกงานของวัน → แถบแจ้ง "ครบทุกงานวันนี้ · สตรีค n วัน"
Future<void> celebrateIfDayComplete(BuildContext context, CalendarRepository repo, DateTime day) async {
  if (!dayComplete(await repo.occurrencesOn(day))) return;
  final today = dayOnly(DateTime.now());
  final streak = dayOnly(day) == today ? (await loadStreak(repo, today)).current : 0;
  if (!context.mounted) return;
  final when = dayOnly(day) == today ? 'วันนี้' : thaiShortDate(day);
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
    content: Text('ครบทุกงาน$when${streak > 1 ? ' · Streak $streak วัน' : ''}'),
  ));
}
