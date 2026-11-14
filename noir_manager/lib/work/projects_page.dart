/// โปรเจกต์ (รอบ 8E): บอร์ด 5 สถานะ · รายละเอียด = ตัวเลข · งวดงาน · ทีม · ขั้นงาน · ไฟล์
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../calendar/calendar_repository.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'money_calc.dart';
import 'money_forms.dart';
import 'money_models.dart';
import 'project_calc.dart';
import 'project_forms.dart';
import 'project_models.dart';
import 'work_repository.dart';

class ProjectsPage extends StatefulWidget {
  const ProjectsPage({super.key});

  @override
  State<ProjectsPage> createState() => _ProjectsPageState();
}

class _ProjectsPageState extends State<ProjectsPage> {
  CalendarRepository? _cal;
  WorkRepository? _repo;
  List<Project> _projects = const [];
  int? _selected;
  List<MoneyEntry> _entries = const [];
  final Map<int, List<ProjectPayment>> _payments = {};
  final Map<int, List<ProjectTask>> _tasks = {};
  List<ProjectMember> _members = const [];
  List<ProjectFile> _files = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cal = CalendarScope.of(context);
    if (cal != _cal) {
      _repo?.removeListener(_load);
      _cal = cal;
      _repo = cal.workRepo..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_load);
    super.dispose();
  }

  Project? get _project => _projects.where((x) => x.id == _selected).firstOrNull;

  Future<void> _load() async {
    final repo = _repo!;
    final projects = await repo.projects();
    final entries = [for (final e in await repo.entries(DateTime(2000), DateTime(2100))) if (e.projectId != null) e];
    final pays = <int, List<ProjectPayment>>{}, tasks = <int, List<ProjectTask>>{};
    for (final pj in projects) {
      pays[pj.id] = await repo.payments(pj.id);
      tasks[pj.id] = await repo.tasks(pj.id);
    }
    final sel = _selected != null && projects.any((x) => x.id == _selected) ? _selected : null;
    final members = sel == null ? <ProjectMember>[] : await repo.members(sel);
    final files = sel == null ? <ProjectFile>[] : await repo.projectFiles(sel);
    if (!mounted) return;
    setState(() {
      _projects = projects;
      _entries = entries;
      _payments
        ..clear()
        ..addAll(pays);
      _tasks
        ..clear()
        ..addAll(tasks);
      _selected = sel;
      _members = members;
      _files = files;
    });
  }

  void _open(int id) {
    setState(() => _selected = id);
    _load();
  }

  Future<void> _cardMenu(Project pj, Offset at) async {
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('move', Icons.swap_horiz, 'ย้ายสถานะ'),
      ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
      ctxItem('delete', Icons.delete_outline, 'ลบโปรเจกต์', danger: true),
    ]);
    if (!mounted || v == null) return;
    final repo = _repo!;
    if (v == 'move') {
      final s = await showMiniChoice<ProjectStatus>(context,
          title: 'ย้ายไป', current: pj.status, items: [for (final s in ProjectStatus.values) miniChoice(s, projectStatusText(s))]);
      if (s != null) await repo.saveProject(pj.copyWith(status: s));
    } else if (v == 'edit') {
      await editProjectForm(context, repo, project: pj);
    } else if (v == 'delete' &&
        await confirmMini(context,
            title: 'ลบ "${pj.name}"?', message: 'ทีม ขั้นงาน งวด และไฟล์หายด้วย · รายการเงินยังอยู่', okLabel: 'ลบ', danger: true)) {
      await repo.deleteProject(pj.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final pj = _project;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 24, 32), children: [
      Row(children: [
        Expanded(child: Text('โปรเจกต์', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text))),
        FilledButton.icon(
          key: const Key('pj-add'),
          onPressed: () async {
            final id = await editProjectForm(context, _repo!);
            if (id != null) _open(id);
          },
          icon: const Icon(Icons.add, size: 18),
          label: const Text('โปรเจกต์'),
        ),
      ]),
      const SizedBox(height: 10),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final st in ProjectStatus.values) _column(context, c, st),
        ]),
      ),
      if (_projects.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('เช่น งานสตีม / ท่อ · ติดตั้งเครื่องจักร · เว็บ · ช่อง YouTube · คลิกขวาที่การ์ด = ย้ายสถานะ',
              style: TextStyle(fontSize: 12, color: c.muted)),
        ),
      if (pj != null) ...[const SizedBox(height: 16), _detail(context, c, pj)],
    ]);
  }

  Widget _column(BuildContext context, NoirColors c, ProjectStatus st) {
    final list = _projects.where((x) => x.status == st).toList();
    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(8),
      constraints: const BoxConstraints(minHeight: 110),
      decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text(projectStatusText(st), style: TextStyle(fontSize: 12, color: c.muted))),
          Text('${list.length}', style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
        const SizedBox(height: 6),
        for (final pj in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: GestureDetector(
              onSecondaryTapUp: (e) => _cardMenu(pj, e.globalPosition),
              onLongPressStart: (e) => _cardMenu(pj, e.globalPosition),
              child: Material(
                color: c.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: pj.id == _selected ? c.accent : c.line, width: pj.id == _selected ? 1.5 : 1),
                ),
                child: InkWell(
                  key: ValueKey('pj-${pj.id}'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => _open(pj.id),
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${projectType(pj.type).$2} ${pj.name}',
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.text)),
                      Text(_cardSub(pj), style: TextStyle(fontSize: 11, color: c.muted)),
                    ]),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }

  String _cardSub(Project pj) {
    final m = projectMoney(pj, _entries, _payments[pj.id] ?? const []);
    final next = nextTask(_tasks[pj.id] ?? const []);
    return switch (pj.status) {
      ProjectStatus.quote => m.price > 0 ? baht(m.price) : 'รอตอบ',
      ProjectStatus.paid => 'กำไร ${baht(m.received - m.cost)}',
      _ => [
          if (m.paymentCount > 0) 'งวด ${m.paidCount}/${m.paymentCount}',
          if (next?.due != null) 'ถัดไป ${thaiShortDate(next!.due!)}',
        ].join(' · '),
    };
  }

  Widget _detail(BuildContext context, NoirColors c, Project pj) {
    final repo = _repo!;
    final pays = _payments[pj.id] ?? const <ProjectPayment>[];
    final tasks = _tasks[pj.id] ?? const <ProjectTask>[];
    final m = projectMoney(pj, _entries, pays);
    final head = [
      if (pj.client != null) 'ลูกค้า: ${pj.client}',
      if (pj.start != null || pj.due != null) '${pj.start == null ? '' : thaiShortDate(pj.start!)} – ${pj.due == null ? '' : thaiShortDate(pj.due!)}',
      if (pj.travelMinutes != null && pj.travelMinutes! > 0) 'กันเวลาเดินทาง ${pj.travelMinutes} นาที/วัน',
    ].join(' · ');

    Widget section(String title, Widget? action, List<Widget> children) => Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
                ?action,
              ]),
              ...children,
            ]),
          ),
        );

    final money = section('ตัวเลข', TextButton.icon(
      key: const Key('pj-expense'),
      onPressed: () => editEntryForm(context, repo, projectId: pj.id),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('ค่าใช้จ่าย'),
    ), [
      Wrap(spacing: 18, runSpacing: 8, children: [
        _kpi(c, 'ราคางาน', baht(m.price), c.text, 'pj-kpi-price'),
        _kpi(c, 'ต้นทุนจริง', baht(m.cost), c.bad, 'pj-kpi-cost'),
        _kpi(c, 'กำไรคาด', baht(m.profit), m.profit >= 0 ? c.good : c.bad, 'pj-kpi-profit'),
        _kpi(c, 'รับแล้ว', baht(m.received), c.accent, 'pj-kpi-received'),
      ]),
      const SizedBox(height: 10),
      Text('งวดงาน (ติ๊ก = รับเงินแล้ว → ลงรายรับในการเงินให้)', style: TextStyle(fontSize: 12, color: c.muted)),
      for (final pay in pays)
        GestureDetector(
          onSecondaryTapUp: (e) => _rowMenu(e.globalPosition,
              edit: () => editPaymentForm(context, repo, pj.id, payment: pay), delete: () => repo.deletePayment(pay.id)),
          child: Row(children: [
            Checkbox(
              key: ValueKey('pay-${pay.id}'),
              value: pay.received,
              onChanged: (v) => togglePaymentReceived(repo, pj, pay, v ?? false),
            ),
            Expanded(
              child: Text('${pay.label}${pay.condition == null ? '' : ' · ${pay.condition}'}',
                  style: TextStyle(color: c.text), maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            if (!pay.received && pay.due != null)
              Text('ครบ ${thaiShortDate(pay.due!)} ',
                  style: TextStyle(fontSize: 12, color: pay.due!.isBefore(DateTime.now()) ? c.warn : c.muted)),
            Text(baht(pay.amount), style: TextStyle(color: pay.received ? c.good : c.text)),
          ]),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('pay-add'),
          onPressed: () => editPaymentForm(context, repo, pj.id),
          icon: const Icon(Icons.add, size: 18),
          label: const Text('งวด'),
        ),
      ),
    ]);

    final team = section('ทีม + หน้าที่', IconButton(
      key: const Key('mb-add'),
      tooltip: 'เพิ่มคน',
      onPressed: () => editMemberForm(context, repo, pj.id),
      icon: const Icon(Icons.person_add_alt),
    ), [
      if (_members.isEmpty) Text('ช่าง · ผู้วางแผน · ลูกค้า (ผู้ตรวจรับ)', style: TextStyle(fontSize: 12, color: c.muted)),
      for (final mb in _members)
        GestureDetector(
          onSecondaryTapUp: (e) => _rowMenu(e.globalPosition,
              edit: () => editMemberForm(context, repo, pj.id, member: mb), delete: () => repo.deleteMember(mb.id)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              SizedBox(width: 90, child: Text(mb.name, style: TextStyle(color: c.text))),
              Expanded(child: Text(mb.role ?? '', style: TextStyle(fontSize: 12, color: c.muted))),
              Flexible(child: Text(mb.duty ?? '', style: TextStyle(fontSize: 12, color: c.text), overflow: TextOverflow.ellipsis)),
            ]),
          ),
        ),
    ]);

    final steps = section('ขั้นงาน', IconButton(
      key: const Key('task-add'),
      tooltip: 'เพิ่มขั้นงาน',
      onPressed: () => editTaskForm(context, repo, pj.id),
      icon: const Icon(Icons.add_task),
    ), [
      if (tasks.isEmpty) Text('เช่น สำรวจหน้างาน · สั่งของ · ติดตั้ง · ทดสอบ · คลิกขวา = ลงปฏิทิน', style: TextStyle(fontSize: 12, color: c.muted)),
      for (final t in tasks)
        GestureDetector(
          onSecondaryTapUp: (e) async {
            final v = await showContextMenuAt<String>(context, e.globalPosition, [
              if (t.activityId == null) ctxItem('cal', Icons.event_available, 'ลงปฏิทิน'),
              ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
              ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
            ]);
            if (v == 'cal') {
              await taskToCalendar(_cal!, pj, t);
              if (context.mounted) showToast(context, 'ลงปฏิทินแล้ว · ${t.due == null ? 'วันนี้' : thaiShortDate(t.due!)}');
            }
            if (v == 'edit' && context.mounted) await editTaskForm(context, repo, pj.id, task: t);
            if (v == 'delete') await repo.deleteTask(t.id);
          },
          child: Row(children: [
            Checkbox(key: ValueKey('task-${t.id}'), value: t.done, onChanged: (v) => repo.saveTask(t.copyWith(done: v ?? false))),
            Expanded(
              child: Text(t.title,
                  style: TextStyle(color: t.done ? c.muted : c.text, decoration: t.done ? TextDecoration.lineThrough : null)),
            ),
            if (t.activityId != null) Icon(Icons.event_available, size: 16, color: c.accent),
            if (t.owner != null) Text(' ${t.owner}', style: TextStyle(fontSize: 12, color: c.muted)),
            if (t.due != null)
              Text(' · ${thaiShortDate(t.due!)}',
                  style: TextStyle(fontSize: 12, color: !t.done && t.due!.isBefore(DateTime.now()) ? c.warn : c.muted)),
          ]),
        ),
    ]);

    final files = section('ไฟล์ · รูปก่อน/หลัง', Wrap(children: [
      IconButton(tooltip: 'เพิ่มไฟล์', onPressed: () => _addFiles(pj), icon: const Icon(Icons.attach_file)),
      IconButton(tooltip: 'เพิ่มลิงก์', onPressed: () => _addLink(pj), icon: const Icon(Icons.link)),
    ]), [
      if (_files.isEmpty) Text('ใบเสนอราคา · แบบ P&ID · รูปหน้างาน', style: TextStyle(fontSize: 12, color: c.muted)),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final f in _files)
          GestureDetector(
            onSecondaryTapUp: (e) => _rowMenu(e.globalPosition, delete: () => repo.deleteProjectFile(f.id)),
            child: InkWell(
              onTap: () async {
                await Clipboard.setData(ClipboardData(text: f.path));
                if (context.mounted) showToast(context, 'คัดลอก${f.kind == ProjectFileKind.link ? 'ลิงก์' : 'ที่อยู่ไฟล์'}แล้ว');
              },
              child: Container(
                width: 120,
                height: 90,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
                child: Stack(fit: StackFit.expand, children: [
                  if (f.kind == ProjectFileKind.image)
                    Image.file(File(f.path), fit: BoxFit.cover, errorBuilder: (_, _, _) => const SizedBox())
                  else
                    Icon(f.kind == ProjectFileKind.link ? Icons.link : Icons.insert_drive_file_outlined, color: c.muted),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      color: c.surface.withValues(alpha: 0.8),
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Text(f.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: c.text)),
                    ),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    ]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Text(projectType(pj.type).$2, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(pj.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
            Text('${projectType(pj.type).$3} · ${projectStatusText(pj.status)}${head.isEmpty ? '' : ' · $head'}',
                style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        ),
        IconButton(tooltip: 'แก้ไข', onPressed: () => editProjectForm(context, repo, project: pj), icon: const Icon(Icons.edit_outlined)),
      ]),
      const SizedBox(height: 8),
      LayoutBuilder(builder: (context, box) {
        if (box.maxWidth < 760) {
          return Column(children: [money, team, steps, files]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Column(children: [money, files])),
          const SizedBox(width: 12),
          Expanded(child: Column(children: [team, steps])),
        ]);
      }),
    ]);
  }

  Widget _kpi(NoirColors c, String k, String v, Color color, String key) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(fontSize: 11, color: c.muted)),
        Text(v, key: Key(key), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: color)),
      ]);

  Future<void> _rowMenu(Offset at, {Future<void> Function()? edit, required Future<void> Function() delete}) async {
    final v = await showContextMenuAt<String>(context, at, [
      if (edit != null) ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
      ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
    ]);
    if (v == 'edit') await edit!();
    if (v == 'delete') await delete();
  }

  Future<void> _addFiles(Project pj) async {
    final res = await FilePicker.platform.pickFiles(allowMultiple: true);
    final picked = [for (final f in res?.files ?? const <PlatformFile>[]) ?f.path];
    if (picked.isEmpty) return;
    final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'projects', '${pj.id}'));
    await dir.create(recursive: true);
    for (final src in picked) {
      final dest = p.join(dir.path, '${DateTime.now().microsecondsSinceEpoch}_${p.basename(src)}');
      await File(src).copy(dest);
      final ext = p.extension(src).toLowerCase();
      await _repo!.saveProjectFile(ProjectFile(
        projectId: pj.id,
        kind: const {'.png', '.jpg', '.jpeg', '.webp', '.gif', '.bmp'}.contains(ext) ? ProjectFileKind.image : ProjectFileKind.file,
        path: dest,
        title: p.basenameWithoutExtension(src),
        addedAt: DateTime.now(),
      ));
    }
  }

  Future<void> _addLink(Project pj) async {
    final url = TextEditingController();
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => MiniForm(
        title: 'เพิ่มลิงก์',
        primaryLabel: 'เพิ่ม',
        onPrimary: () {
          if (url.text.trim().isNotEmpty) Navigator.pop(ctx, true);
        },
        onSecondary: () => Navigator.pop(ctx, false),
        children: [MiniBigField(controller: url, hint: 'https://…', fontSize: 16)],
      ),
    );
    if (ok != true) return;
    await _repo!.saveProjectFile(
        ProjectFile(projectId: pj.id, kind: ProjectFileKind.link, path: url.text.trim(), title: url.text.trim(), addedAt: DateTime.now()));
  }
}
