/// ฟอร์มของสกิล (MiniForm ทั้งหมด · หน้าตาเหมือนฟอร์มอื่นในแอป)
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../calendar/calendar_ui.dart' show categoryAccent, pickMinute;
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'skill_models.dart';
import 'skill_progress.dart';
import 'skill_repository.dart';

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', ''));

/// เพิ่ม / แก้สกิล · คืน id
Future<int?> editSkillForm(BuildContext context, SkillRepository repo, {Skill? skill}) async {
  final name = TextEditingController(text: skill?.name ?? '');
  final why = TextEditingController(text: skill?.why ?? '');
  var icon = skill?.icon ?? skillIcons.first;
  var color = skill?.colorKey ?? 'purple';
  var showErr = false;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      return MiniForm(
        title: skill == null ? 'สกิลใหม่' : 'แก้สกิล',
        primaryLabel: skill == null ? 'สร้าง' : 'บันทึก',
        onPrimary: () {
          if (name.text.trim().isEmpty) return setLocal(() => showErr = true);
          Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('skill-name'), controller: name, hint: 'เช่น DaVinci Resolve'),
          if (showErr && name.text.trim().isEmpty) Text('ใส่ชื่อสกิล', style: TextStyle(fontSize: 12, color: c.bad)),
          const MiniLabel('ไอคอน'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in skillIcons)
              InkWell(
                key: ValueKey('skill-icon-$e'),
                borderRadius: BorderRadius.circular(10),
                onTap: () => setLocal(() => icon = e),
                child: Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: e == icon ? c.accent.withValues(alpha: 0.18) : c.surface2,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: e == icon ? c.accent : Colors.transparent, width: 2),
                  ),
                  child: Text(e, style: const TextStyle(fontSize: 20)),
                ),
              ),
          ]),
          const MiniLabel('สี'),
          Wrap(spacing: 8, children: [
            for (final k in categoryColorKeys)
              InkWell(
                customBorder: const CircleBorder(),
                onTap: () => setLocal(() => color = k),
                child: Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: categoryAccent(k),
                    shape: BoxShape.circle,
                    border: Border.all(color: k == color ? c.text : Colors.transparent, width: 2.5),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          MiniRow(
            icon: Icons.flag_outlined,
            label: 'ฝึกไปทำไม',
            last: true,
            value: MiniInlineField(controller: why, hint: 'เช่น ตัดคลิปสตรีมเอง', width: 200),
          ),
        ],
      );
    }),
  );
  if (ok != true) return null;
  return repo.saveSkill(Skill(
    id: skill?.id ?? 0,
    name: name.text.trim(),
    icon: icon,
    colorKey: color,
    why: why.text.trim().isEmpty ? null : why.text.trim(),
    status: skill?.status ?? SkillStatus.active,
    startedAt: skill?.startedAt ?? DateTime.now(),
    doneAt: skill?.doneAt,
  ));
}

/// เพิ่ม / แก้เป้า · [from] = ยกระดับจากเป้าเดิม (ค่าเริ่มต้นตามเดิม)
Future<int?> editGoalForm(BuildContext context, SkillRepository repo, int skillId, {SkillGoal? goal, SkillGoal? from}) async {
  final base = goal ?? from;
  var kind = base?.kind ?? GoalKind.faster;
  final title = TextEditingController(text: base?.title ?? '');
  final target = TextEditingController(text: base == null || base.target == 0 ? '' : fmtNumber(base.target));
  final unit = TextEditingController(text: base?.unit ?? 'นาที');
  final streak = TextEditingController(text: '${base?.streak ?? 3}');
  final steps = TextEditingController(text: base?.steps.map((s) => s.title).join('\n') ?? '');
  var showErr = false;
  String? err() {
    if (title.text.trim().isEmpty) return 'ใส่ชื่อเป้า';
    if (kind == GoalKind.milestone) return steps.text.trim().isEmpty ? 'ใส่ด่านอย่างน้อย 1 ด่าน' : null;
    if ((_num(target.text) ?? 0) <= 0) return 'ใส่ค่าเป้าเป็นตัวเลข';
    return null;
  }

  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      final hint = switch (kind) {
        GoalKind.faster => 'เช่น ตัดคลิป 1 ชม.',
        GoalKind.count => 'เช่น คำศัพท์ใหม่',
        GoalKind.volume => 'เช่น ฝึกฟัง English',
        GoalKind.milestone => 'เช่น รู้จักทุกหน้าใน DaVinci',
      };
      return MiniForm(
        title: goal != null ? 'แก้เป้า' : (from != null ? 'ยกระดับเป้า' : 'เป้าใหม่'),
        primaryLabel: 'บันทึก',
        onPrimary: () {
          if (err() != null) return setLocal(() => showErr = true);
          Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniSegments<GoalKind>(
            key: const Key('goal-kind'),
            value: kind,
            items: [for (final k in GoalKind.values) (k, goalKindText(k))],
            onChanged: goal != null
                ? (_) {} // แก้เป้าเดิม = เปลี่ยนแบบไม่ได้ (ข้อมูลที่บันทึกไว้จะคิดผิด)
                : (k) => setLocal(() {
                      kind = k;
                      unit.text = switch (k) {
                        GoalKind.faster => 'นาที',
                        GoalKind.count => 'คำ',
                        GoalKind.volume => 'ชม.',
                        GoalKind.milestone => '',
                      };
                    }),
          ),
          const SizedBox(height: 8),
          MiniBigField(key: const Key('goal-title'), controller: title, hint: hint, autofocus: false),
          if (kind != GoalKind.milestone) ...[
            MiniRow(
              icon: kind == GoalKind.faster ? Icons.timer_outlined : Icons.straighten,
              label: switch (kind) {
                GoalKind.faster => 'ไม่เกิน',
                GoalKind.count => 'อย่างน้อย / วัน',
                _ => 'ชั่วโมง / สัปดาห์',
              },
              value: Row(mainAxisSize: MainAxisSize.min, children: [
                MiniInlineField(
                    key: const Key('goal-target'),
                    controller: target,
                    hint: kind == GoalKind.faster ? '90' : '10',
                    width: 70,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => setLocal(() {})),
                if (kind != GoalKind.volume) ...[
                  const SizedBox(width: 6),
                  MiniInlineField(key: const Key('goal-unit'), controller: unit, hint: 'หน่วย', width: 70),
                ],
              ]),
            ),
            MiniRow(
              icon: Icons.repeat,
              label: switch (kind) {
                GoalKind.faster => 'ทำได้ติดกัน (รอบ)',
                GoalKind.count => 'ทำได้ติดกัน (วัน)',
                _ => 'ทำได้ติดกัน (สัปดาห์)',
              },
              last: true,
              value: MiniInlineField(controller: streak, hint: '3', width: 60, keyboardType: TextInputType.number),
            ),
          ] else ...[
            const MiniLabel('ด่าน (1 บรรทัด = 1 ด่าน)'),
            TextField(
              key: const Key('goal-steps'),
              controller: steps,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(hintText: 'Cut page\nColor page\nFairlight'),
              onChanged: (_) => setLocal(() {}),
            ),
          ],
          if (showErr && err() != null) Text(err()!, style: TextStyle(fontSize: 12, color: c.bad)),
        ],
      );
    }),
  );
  if (ok != true) return null;
  final old = {for (final s in base?.steps ?? const <GoalStep>[]) s.title: s.done};
  final saved = SkillGoal(
    id: goal?.id ?? 0,
    skillId: skillId,
    kind: kind,
    title: title.text.trim(),
    unit: kind == GoalKind.volume ? 'ชม.' : unit.text.trim(),
    target: _num(target.text) ?? 0,
    streak: (int.tryParse(streak.text.trim()) ?? 3).clamp(1, 60),
    status: goal?.status ?? GoalStatus.active,
    steps: [
      for (final l in steps.text.split('\n'))
        if (l.trim().isNotEmpty) GoalStep(l.trim(), done: goal != null && (old[l.trim()] ?? false)),
    ],
  );
  if (from != null) await repo.saveGoal(from.copyWith(status: GoalStatus.met));
  return repo.saveGoal(saved);
}

String fmtNumber(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

/// บันทึกรอบที่ฝึก · [minutes] / [occurrenceId] มาจากงานในปฏิทินที่เพิ่งกด "ทำแล้ว"
Future<int?> editLogForm(
  BuildContext context,
  SkillRepository repo,
  Skill skill, {
  SkillLog? log,
  int? minutes,
  int? occurrenceId,
  DateTime? day,
}) async {
  final goals = [for (final g in await repo.goals(skill.id)) if (g.status == GoalStatus.active && (g.kind == GoalKind.faster || g.kind == GoalKind.count)) g];
  if (!context.mounted) return null;
  var goalId = log?.goalId ?? goals.firstOrNull?.id;
  final mins = TextEditingController(text: '${log?.minutes ?? minutes ?? ''}');
  final value = TextEditingController(text: log?.value == null ? '' : fmtNumber(log!.value!));
  final better = TextEditingController(text: log?.better ?? '');
  final stuck = TextEditingController(text: log?.stuck ?? '');
  final next = TextEditingController(text: log?.next ?? '');
  var rating = log?.rating ?? 0;
  var skipped = log?.skipped ?? false;
  final when = log?.day ?? day ?? DateTime.now();
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      final g = goals.where((x) => x.id == goalId).firstOrNull;
      return MiniForm(
        title: '${skill.icon} ${skill.name} · ${thaiShortDate(when)}',
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, true),
        secondaryLabel: log == null && occurrenceId != null ? 'ข้าม' : 'ยกเลิก',
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniSwitchRow(
            icon: Icons.do_not_disturb_on_outlined,
            label: 'รอบนี้ไม่ได้ฝึก',
            value: skipped,
            onChanged: (v) => setLocal(() => skipped = v),
          ),
          if (!skipped) ...[
            MiniRow(
              icon: Icons.schedule,
              label: 'ฝึกไปกี่นาที',
              value: MiniInlineField(
                  key: const Key('log-minutes'), controller: mins, hint: '60', width: 70, keyboardType: TextInputType.number),
            ),
            if (goals.isNotEmpty) ...[
              MiniRow(
                icon: Icons.flag_outlined,
                label: 'วัดเป้า',
                valueText: g?.title ?? 'ไม่วัด',
                onTap: () async {
                  final v = await showMiniChoice<int>(ctx,
                      title: 'วัดเป้าไหน',
                      current: goalId ?? -1,
                      items: [miniChoice(-1, 'ไม่วัด'), for (final x in goals) miniChoice(x.id, x.title, detail: goalRuleText(x))]);
                  if (v != null) setLocal(() => goalId = v == -1 ? null : v);
                },
              ),
              if (g != null)
                MiniRow(
                  icon: g.kind == GoalKind.faster ? Icons.timer_outlined : Icons.numbers,
                  label: g.kind == GoalKind.faster ? 'รอบนี้ใช้ (${g.unit})' : 'รอบนี้ได้ (${g.unit})',
                  value: MiniInlineField(
                      key: const Key('log-value'),
                      controller: value,
                      hint: '—',
                      width: 70,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                ),
            ],
            const MiniLabel('พอใจแค่ไหน'),
            Row(children: [
              for (var i = 1; i <= 5; i++)
                IconButton(
                  key: ValueKey('log-star-$i'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setLocal(() => rating = rating == i ? 0 : i),
                  icon: Icon(i <= rating ? Icons.star_rounded : Icons.star_outline_rounded, color: i <= rating ? c.warn : c.muted),
                ),
            ]),
          ],
          MiniRow(icon: Icons.trending_up, label: 'ดีขึ้นตรงไหน', value: MiniInlineField(controller: better, width: 200)),
          MiniRow(
              icon: Icons.report_outlined,
              label: skipped ? 'ทำไมไม่ได้ฝึก' : 'ติดตรงไหน',
              value: MiniInlineField(key: const Key('log-stuck'), controller: stuck, width: 200)),
          MiniRow(icon: Icons.east, label: 'ครั้งหน้าลอง', last: true, value: MiniInlineField(controller: next, width: 200)),
        ],
      );
    }),
  );
  if (ok != true) return null;
  String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  return repo.saveLog(SkillLog(
    id: log?.id ?? 0,
    skillId: skill.id,
    goalId: skipped ? null : goalId,
    day: when,
    minutes: skipped ? null : int.tryParse(mins.text.trim()),
    value: skipped || goalId == null ? null : _num(value.text),
    rating: skipped || rating == 0 ? null : rating,
    better: t(better),
    stuck: t(stuck),
    next: t(next),
    skipped: skipped,
    occurrenceId: log?.occurrenceId ?? occurrenceId,
  ));
}

/// ตั้งแผนฝึก: วันในสัปดาห์ + เวลา + ความยาว → งานซ้ำรายสัปดาห์ (ยืดหยุ่น) ในปฏิทิน ผูกกับสกิล
Future<bool> planPracticeForm(BuildContext context, CalendarRepository cal, Skill skill) async {
  final days = <int>{1, 3, 5};
  var start = 19 * 60;
  var len = 60;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      return MiniForm(
        title: 'แผนฝึก ${skill.name}',
        primaryLabel: 'ลงปฏิทิน',
        onPrimary: () {
          if (days.isNotEmpty) Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          const MiniLabel('วันที่ฝึก'),
          WeekdayCircles(selected: days, onToggle: (d) => setLocal(() => days.contains(d) ? days.remove(d) : days.add(d))),
          const SizedBox(height: 8),
          MiniRow(
            icon: Icons.schedule,
            label: 'เริ่ม',
            valueText: '${(start ~/ 60).toString().padLeft(2, '0')}:${(start % 60).toString().padLeft(2, '0')}',
            onTap: () async {
              final m = await pickMinute(ctx, start, title: 'เวลาเริ่มฝึก');
              if (m != null) setLocal(() => start = m);
            },
          ),
          const MiniLabel('รอบละ'),
          MiniSegments<int>(
            value: len,
            items: const [(30, '30 นาที'), (60, '1 ชม.'), (90, '1:30'), (120, '2 ชม.')],
            onChanged: (v) => setLocal(() => len = v),
          ),
          const SizedBox(height: 8),
          Text('ลงเป็นงานซ้ำทุกสัปดาห์ แบบ "ยืดหยุ่น" (บางวันว่างได้ ไม่นับพลาด) · กด "ทำแล้ว" = ขึ้นให้บันทึกรอบ',
              style: TextStyle(fontSize: 12, color: c.muted)),
        ],
      );
    }),
  );
  if (ok != true) return false;
  final cats = await cal.categories();
  final today = DateTime.now();
  final id = await cal.addActivity(NewActivity(
    name: 'ฝึก · ${skill.name}',
    categoryId: studyCategoryId(cats) ?? cats.first.id,
    importance: 2,
    timed: true,
    day: DateTime(today.year, today.month, today.day),
    startMinute: start,
    durationMin: len,
    repeat: RepeatKind.weekly,
    weekdays: {...days},
    flexible: true,
  ));
  await cal.skillRepo.linkActivity(skill.id, id);
  return true;
}

/// ประเมินตัวเองเดือนนี้
Future<void> reviewForm(BuildContext context, SkillRepository repo, Skill skill, DateTime month) async {
  final key = monthKey(month);
  final old = await repo.review(skill.id, key);
  if (!context.mounted) return;
  final can = TextEditingController(text: old?.can ?? '');
  final weak = TextEditingController(text: old?.weak ?? '');
  final next = TextEditingController(text: old?.nextGoal ?? '');
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => MiniForm(
      title: 'ประเมิน ${skill.name} · ${thaiMonthYear(month)}',
      primaryLabel: 'บันทึก',
      onPrimary: () => Navigator.pop(ctx, true),
      onSecondary: () => Navigator.pop(ctx, false),
      children: [
        MiniRow(icon: Icons.check_circle_outline, label: 'ทำได้แล้ว', value: MiniInlineField(key: const Key('rv-can'), controller: can, width: 220)),
        MiniRow(icon: Icons.warning_amber_outlined, label: 'ยังอ่อน', value: MiniInlineField(controller: weak, width: 220)),
        MiniRow(icon: Icons.flag_outlined, label: 'เป้าถัดไป', last: true, value: MiniInlineField(controller: next, width: 220)),
      ],
    ),
  );
  if (ok != true) return;
  String? t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
  await repo.saveReview(SkillReview(skillId: skill.id, month: key, can: t(can), weak: t(weak), nextGoal: t(next)));
}

/// เพิ่มรูป / ไฟล์ลง Portfolio (คัดลอกเข้าโฟลเดอร์แอป · ลบต้นฉบับแล้วยังอยู่)
Future<int> addPortfolioFiles(SkillRepository repo, int skillId, {int? logId}) async {
  final res = await FilePicker.platform.pickFiles(allowMultiple: true);
  final picked = [for (final f in res?.files ?? const <PlatformFile>[]) ?f.path];
  if (picked.isEmpty) return 0;
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'portfolio', '$skillId'));
  await dir.create(recursive: true);
  for (final src in picked) {
    final dest = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_${p.basename(src)}');
    await File(src).copy(dest);
    final ext = p.extension(src).toLowerCase();
    await repo.saveFile(SkillFile(
      skillId: skillId,
      logId: logId,
      kind: const {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'}.contains(ext) ? SkillFileKind.image : SkillFileKind.file,
      path: dest,
      title: p.basenameWithoutExtension(src),
      addedAt: DateTime.now(),
    ));
  }
  return picked.length;
}

/// เพิ่มลิงก์ (เช่น YouTube) ลง Portfolio
Future<bool> addPortfolioLink(BuildContext context, SkillRepository repo, int skillId) async {
  final url = TextEditingController();
  final title = TextEditingController();
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => MiniForm(
      title: 'เพิ่มลิงก์ผลงาน',
      primaryLabel: 'เพิ่ม',
      onPrimary: () {
        if (url.text.trim().isNotEmpty) Navigator.pop(ctx, true);
      },
      onSecondary: () => Navigator.pop(ctx, false),
      children: [
        MiniBigField(key: const Key('link-url'), controller: url, hint: 'https://…', fontSize: 16),
        MiniRow(icon: Icons.label_outline, label: 'ชื่อ', last: true, value: MiniInlineField(controller: title, width: 200)),
      ],
    ),
  );
  if (ok != true) return false;
  await repo.saveFile(SkillFile(
    skillId: skillId,
    kind: SkillFileKind.link,
    path: url.text.trim(),
    title: title.text.trim().isEmpty ? url.text.trim() : title.text.trim(),
    addedAt: DateTime.now(),
  ));
  return true;
}
