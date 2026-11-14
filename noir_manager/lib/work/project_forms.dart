/// ฟอร์มโปรเจกต์ (MiniForm)
library;

import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_form.dart';
import 'money_models.dart';
import 'project_calc.dart';
import 'project_models.dart';
import 'work_repository.dart';

double? _num(String s) => double.tryParse(s.trim().replaceAll(',', '').replaceAll('฿', ''));
String _plain(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(2);
String? _t(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

Future<DateTime?> _pick(BuildContext context, DateTime? initial) => showDatePicker(
      context: context,
      initialDate: initial ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );

/// เพิ่ม / แก้โปรเจกต์ · ใหม่ + มีราคา → สร้างงวด 30 / 40 / 30 ให้ได้
Future<int?> editProjectForm(BuildContext context, WorkRepository repo, {Project? project}) async {
  final name = TextEditingController(text: project?.name ?? '');
  final client = TextEditingController(text: project?.client ?? '');
  final price = TextEditingController(text: project?.price == null ? '' : _plain(project!.price!));
  final travel = TextEditingController(text: project?.travelMinutes?.toString() ?? '');
  final note = TextEditingController(text: project?.note ?? '');
  var type = project?.type ?? 'steam';
  DateTime? start = project?.start, due = project?.due;
  var split = project == null;
  var showErr = false;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      return MiniForm(
        title: project == null ? 'โปรเจกต์ใหม่' : 'แก้โปรเจกต์',
        primaryLabel: project == null ? 'สร้าง' : 'บันทึก',
        onPrimary: () {
          if (name.text.trim().isEmpty) return setLocal(() => showErr = true);
          Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('pj-name'), controller: name, hint: 'เช่น ติดตั้งระบบท่อไอน้ำ โรงงาน A'),
          if (showErr && name.text.trim().isEmpty) Text('ใส่ชื่อโปรเจกต์', style: TextStyle(fontSize: 12, color: c.bad)),
          const MiniLabel('แบบงาน'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (id, icon, label) in projectTypes)
              ChoiceChip(
                key: ValueKey('pj-type-$id'),
                showCheckmark: false,
                label: Text('$icon $label'),
                selected: type == id,
                onSelected: (_) => setLocal(() => type = id),
              ),
          ]),
          const SizedBox(height: 8),
          MiniRow(icon: Icons.business_outlined, label: 'ลูกค้า', value: MiniInlineField(controller: client, width: 200)),
          MiniRow(
            icon: Icons.payments_outlined,
            label: 'ราคางาน (บาท)',
            value: MiniInlineField(
                key: const Key('pj-price'),
                controller: price,
                hint: '0',
                width: 120,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => setLocal(() {})),
          ),
          MiniRow(
            icon: Icons.play_arrow_outlined,
            label: 'เริ่ม',
            valueText: start == null ? '—' : thaiShortDate(start!),
            onTap: () async {
              final d = await _pick(ctx, start);
              if (d != null) setLocal(() => start = d);
            },
          ),
          MiniRow(
            icon: Icons.flag_outlined,
            label: 'กำหนดเสร็จ',
            valueText: due == null ? '—' : thaiShortDate(due!),
            onTap: () async {
              final d = await _pick(ctx, due ?? start);
              if (d != null) setLocal(() => due = d);
            },
          ),
          MiniRow(
            icon: Icons.directions_car_outlined,
            label: 'กันเวลาเดินทาง (นาที/วัน)',
            value: MiniInlineField(controller: travel, hint: '0', width: 70, keyboardType: TextInputType.number),
          ),
          MiniRow(icon: Icons.notes, label: 'โน้ต', last: project != null, value: MiniInlineField(controller: note, width: 200)),
          if (project == null && (_num(price.text) ?? 0) > 0)
            MiniSwitchRow(
              key: const Key('pj-split'),
              icon: Icons.splitscreen_outlined,
              label: 'สร้างงวด 30 / 40 / 30',
              detail: 'แก้ทีหลังได้',
              value: split,
              last: true,
              onChanged: (v) => setLocal(() => split = v),
            ),
        ],
      );
    }),
  );
  if (ok != true) return null;
  final pr = _num(price.text);
  final id = await repo.saveProject(Project(
    id: project?.id ?? 0,
    name: name.text.trim(),
    client: _t(client),
    type: type,
    status: project?.status ?? ProjectStatus.quote,
    price: pr,
    start: start,
    due: due,
    travelMinutes: int.tryParse(travel.text.trim()),
    note: _t(note),
  ));
  if (project == null && split && pr != null && pr > 0) {
    final amounts = splitByPercent(pr, const [30, 40, 30]);
    const labels = [('1 · 30%', 'เซ็นสัญญา'), ('2 · 40%', 'ทำงานหลักเสร็จ'), ('3 · 30%', 'ส่งมอบ')];
    for (final (i, (label, cond)) in labels.indexed) {
      await repo.savePayment(ProjectPayment(projectId: id, label: label, amount: amounts[i], condition: cond));
    }
  }
  return id;
}

Future<void> editMemberForm(BuildContext context, WorkRepository repo, int projectId, {ProjectMember? member}) async {
  final name = TextEditingController(text: member?.name ?? '');
  final role = TextEditingController(text: member?.role ?? '');
  final duty = TextEditingController(text: member?.duty ?? '');
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => MiniForm(
      title: member == null ? 'เพิ่มคนในทีม' : 'แก้ข้อมูล',
      primaryLabel: 'บันทึก',
      onPrimary: () {
        if (name.text.trim().isNotEmpty) Navigator.pop(ctx, true);
      },
      onSecondary: () => Navigator.pop(ctx, false),
      children: [
        MiniBigField(key: const Key('mb-name'), controller: name, hint: 'ชื่อ เช่น ช่าง ก'),
        MiniRow(
            icon: Icons.badge_outlined,
            label: 'หน้าที่',
            value: MiniInlineField(key: const Key('mb-role'), controller: role, hint: 'เช่น ช่างเชื่อม / ลูกค้า', width: 200)),
        MiniRow(icon: Icons.assignment_outlined, label: 'งานที่ถือ', last: true, value: MiniInlineField(controller: duty, width: 200)),
      ],
    ),
  );
  if (ok != true) return;
  await repo.saveMember(ProjectMember(id: member?.id ?? 0, projectId: projectId, name: name.text.trim(), role: _t(role), duty: _t(duty)));
}

Future<void> editTaskForm(BuildContext context, WorkRepository repo, int projectId, {ProjectTask? task}) async {
  final members = await repo.members(projectId);
  if (!context.mounted) return;
  final title = TextEditingController(text: task?.title ?? '');
  var owner = task?.owner;
  DateTime? due = task?.due;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      return MiniForm(
        title: task == null ? 'ขั้นงานใหม่' : 'แก้ขั้นงาน',
        primaryLabel: 'บันทึก',
        onPrimary: () {
          if (title.text.trim().isNotEmpty) Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('task-title'), controller: title, hint: 'เช่น เดินท่อ ชั้น 2'),
          MiniRow(
            icon: Icons.person_outline,
            label: 'คนรับผิดชอบ',
            valueText: owner ?? '—',
            onTap: members.isEmpty
                ? null
                : () async {
                    final v = await showMiniChoice<String>(ctx,
                        title: 'ใครทำ', current: owner ?? '', items: [miniChoice('', '—'), for (final m in members) miniChoice(m.name, m.name, detail: m.role)]);
                    if (v != null) setLocal(() => owner = v.isEmpty ? null : v);
                  },
          ),
          MiniRow(
            icon: Icons.event,
            label: 'กำหนด',
            valueText: due == null ? '—' : thaiShortDate(due!),
            last: true,
            onTap: () async {
              final d = await _pick(ctx, due);
              if (d != null) setLocal(() => due = d);
            },
          ),
        ],
      );
    }),
  );
  if (ok != true) return;
  await repo.saveTask(ProjectTask(
      id: task?.id ?? 0, projectId: projectId, title: title.text.trim(), owner: owner, due: due, done: task?.done ?? false, activityId: task?.activityId));
}

Future<void> editPaymentForm(BuildContext context, WorkRepository repo, int projectId, {ProjectPayment? payment}) async {
  final label = TextEditingController(text: payment?.label ?? '');
  final amount = TextEditingController(text: payment == null ? '' : _plain(payment.amount));
  final cond = TextEditingController(text: payment?.condition ?? '');
  DateTime? due = payment?.due;
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      return MiniForm(
        title: payment == null ? 'งวดใหม่' : 'แก้งวด',
        primaryLabel: 'บันทึก',
        onPrimary: () {
          if (label.text.trim().isNotEmpty && (_num(amount.text) ?? 0) > 0) Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('pay-label'), controller: label, hint: 'เช่น งวด 2 · 40%'),
          MiniRow(
            icon: Icons.payments_outlined,
            label: 'ยอด (บาท)',
            value: MiniInlineField(
                key: const Key('pay-amount'), controller: amount, width: 120, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
          ),
          MiniRow(icon: Icons.rule, label: 'เงื่อนไข', value: MiniInlineField(controller: cond, hint: 'เช่น เดินท่อเสร็จ', width: 200)),
          MiniRow(
            icon: Icons.event,
            label: 'ครบกำหนด',
            valueText: due == null ? '—' : thaiShortDate(due!),
            last: true,
            onTap: () async {
              final d = await _pick(ctx, due);
              if (d != null) setLocal(() => due = d);
            },
          ),
        ],
      );
    }),
  );
  if (ok != true) return;
  await repo.savePayment(ProjectPayment(
      id: payment?.id ?? 0, projectId: projectId, label: label.text.trim(), amount: _num(amount.text)!, condition: _t(cond), due: due, entryId: payment?.entryId));
}

/// รับเงินงวดนี้แล้ว → ลงรายรับ (หมวด งวดงาน · ผูกโปรเจกต์) · ติ๊กออก = ลบรายการนั้น
Future<void> togglePaymentReceived(WorkRepository repo, Project p, ProjectPayment pay, bool received) async {
  if (received && !pay.received) {
    final entry = await repo.saveEntry(MoneyEntry(
      day: DateTime.now(),
      kind: MoneyKind.income,
      amount: pay.amount,
      category: 'งวดงาน',
      note: '${p.name} · ${pay.label}',
      projectId: p.id,
    ));
    await repo.savePayment(pay.withEntry(entry));
  } else if (!received && pay.received) {
    await repo.deleteEntry(pay.entryId!);
    await repo.savePayment(pay.withEntry(null));
  }
}

/// ลงขั้นงานในปฏิทิน (งานแบบลิสต์ในวันกำหนด · หมวด "งาน" ถ้ามี)
Future<void> taskToCalendar(CalendarRepository cal, Project p, ProjectTask t) async {
  final cats = await cal.categories();
  final work = cats.where((c) => c.name == 'งาน').firstOrNull ?? cats.first;
  final day = t.due ?? DateTime.now();
  final id = await cal.addActivity(NewActivity(
    name: '${p.name} · ${t.title}',
    categoryId: work.id,
    importance: 2,
    timed: false,
    day: DateTime(day.year, day.month, day.day),
  ));
  await cal.workRepo.saveTask(t.copyWith(activityId: id));
}
