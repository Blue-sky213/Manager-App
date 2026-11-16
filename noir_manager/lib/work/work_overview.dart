/// งาน › ภาพรวม + ขั้นงานทั้งหมด (รอบ 9C): ดูทุกโปรเจกต์ในที่เดียว ไม่ต้องเปิดทีละการ์ด
library;

import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'money_calc.dart' show baht;
import 'money_models.dart';
import 'project_calc.dart';
import 'project_forms.dart' show togglePaymentReceived;
import 'project_models.dart';
import 'work_repository.dart';

/// โหลดทุกโปรเจกต์ + ขั้นงาน + งวด + รายการเงินที่ผูกโปรเจกต์ (ใช้ทั้ง 2 แท็บ)
mixin _WorkData<T extends StatefulWidget> on State<T> {
  WorkRepository? repo;
  List<Project> projects = const [];
  Map<int, List<ProjectTask>> tasks = const {};
  Map<int, List<ProjectPayment>> payments = const {};
  List<MoneyEntry> entries = const [];
  bool loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final r = CalendarScope.of(context).workRepo;
    if (r != repo) {
      repo?.removeListener(load);
      repo = r..addListener(load);
      load();
    }
  }

  @override
  void dispose() {
    repo?.removeListener(load);
    super.dispose();
  }

  Future<void> load() async {
    final r = repo!;
    final ps = await r.projects();
    final t = <int, List<ProjectTask>>{}, pay = <int, List<ProjectPayment>>{};
    for (final p in ps) {
      t[p.id] = await r.tasks(p.id);
      pay[p.id] = await r.payments(p.id);
    }
    final es = [for (final e in await r.entries(DateTime(2000), DateTime(2100))) if (e.projectId != null) e];
    if (!mounted) return;
    setState(() {
      projects = ps;
      tasks = t;
      payments = pay;
      entries = es;
      loaded = true;
    });
  }

  Future<void> toggleTask(ProjectTask t) => repo!.saveTask(t.copyWith(done: !t.done));
}

/// 1 แถวขั้นงาน (ติ๊กเสร็จได้เลย)
Widget _taskRow(BuildContext context, NoirColors c, Project p, ProjectTask t, DateTime today, Future<void> Function(ProjectTask) toggle,
    ValueChanged<int> onOpen,
    {String keyPrefix = 'ov-task'}) {
  final b = taskBucket(t, today);
  final dueColor = switch (b) {
    TaskBucket.overdue => c.bad,
    TaskBucket.week => c.warn,
    _ => c.muted,
  };
  return Container(
    padding: const EdgeInsets.symmetric(vertical: 2),
    decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
    child: Row(children: [
      Checkbox(key: ValueKey('$keyPrefix-${t.id}'), value: t.done, onChanged: (_) => toggle(t)),
      Expanded(
        child: InkWell(
          onTap: () => onOpen(p.id),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.text, decoration: t.done ? TextDecoration.lineThrough : null)),
            Text('${projectType(p.type).$2} ${p.name}${t.owner == null ? '' : ' · ${t.owner}'}',
                maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        ),
      ),
      if (t.due != null) Text(thaiShortDate(t.due!), style: TextStyle(fontSize: 12, color: t.done ? c.muted : dueColor)),
    ]),
  );
}

Widget _kpi(NoirColors c, String k, String v, String sub, {Color? color, required String key}) => Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(fontSize: 12, color: c.muted)),
        Text(v, key: Key(key), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: color ?? c.text)),
        Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
      ]),
    );

class WorkOverview extends StatefulWidget {
  const WorkOverview({super.key, required this.onOpenProject, required this.onAllTasks});

  /// เปิดโปรเจกต์ในแท็บบอร์ด
  final ValueChanged<int> onOpenProject;
  final VoidCallback onAllTasks;

  @override
  State<WorkOverview> createState() => _WorkOverviewState();
}

class _WorkOverviewState extends State<WorkOverview> with _WorkData<WorkOverview> {
  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (!loaded) return const SizedBox.shrink();
    final today = DateTime.now();
    final s = workSummary(projects, tasks, payments, entries, today);
    final open = openTasks(projects, tasks);
    final pend = pendingPayments(projects, payments);
    final head = TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text);
    if (projects.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('ยังไม่มีโปรเจกต์ · ไปแท็บ "บอร์ด" กด ＋ โปรเจกต์', key: const Key('work-empty'), style: TextStyle(color: c.muted)),
        ),
      );
    }
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _kpi(c, 'กำลังทำ', '${s.doing}', s.nextDue == null ? 'ยังไม่มีกำหนดส่ง' : 'ส่งมอบถัดไป ${thaiShortDate(s.nextDue!)}',
            key: 'work-kpi-doing'),
        _kpi(
            c,
            'รอเก็บเงิน',
            baht(s.pending),
            s.nextPay == null
                ? 'ไม่มีงวดค้าง'
                : '${s.nextPay!.$2.label}${s.nextPay!.$2.due == null ? '' : ' · ครบ ${thaiShortDate(s.nextPay!.$2.due!)}'}',
            color: s.pending > 0 ? c.warn : null,
            key: 'work-kpi-pending'),
        _kpi(c, 'กำไรปีนี้', baht(s.profitYear), '${s.closedYear} งานปิดแล้ว',
            color: s.profitYear >= 0 ? c.good : c.bad, key: 'work-kpi-profit'),
        _kpi(c, 'ขั้นงาน', '${s.tasksDone}/${s.tasksTotal}', s.overdue == 0 ? 'ไม่มีเลยกำหนด' : 'เลยกำหนด ${s.overdue}',
            color: s.overdue > 0 ? c.bad : null, key: 'work-kpi-tasks'),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Text('ขั้นงานใกล้กำหนด (ทุกโปรเจกต์)', style: head)),
        TextButton(key: const Key('work-all-tasks'), onPressed: widget.onAllTasks, child: const Text('ดูทั้งหมด')),
      ]),
      if (open.isEmpty) Text('ไม่มีขั้นงานค้าง 🎉', style: TextStyle(fontSize: 12, color: c.muted)),
      for (final (p, t) in open.take(8)) _taskRow(context, c, p, t, today, toggleTask, widget.onOpenProject),
      const SizedBox(height: 18),
      Text('งวดรอรับ', style: head),
      if (pend.isEmpty) Text('ไม่มีงวดค้าง', style: TextStyle(fontSize: 12, color: c.muted)),
      for (final (p, x) in pend.take(6))
        Container(
          decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
          child: Row(children: [
            Checkbox(
              key: ValueKey('ov-pay-${x.id}'),
              value: false,
              onChanged: (_) => togglePaymentReceived(repo!, p, x, true),
            ),
            Expanded(
              child: InkWell(
                onTap: () => widget.onOpenProject(p.id),
                child: Text('${p.name} · ${x.label}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.text)),
              ),
            ),
            if (x.due != null)
              Text(thaiShortDate(x.due!),
                  style: TextStyle(fontSize: 12, color: x.due!.isBefore(DateTime(today.year, today.month, today.day)) ? c.bad : c.muted)),
            const SizedBox(width: 10),
            Text(baht(x.amount), style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          ]),
        ),
      const SizedBox(height: 18),
      Text('ทุกโปรเจกต์', style: head),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in projects)
          ActionChip(
            key: ValueKey('ov-pj-${p.id}'),
            avatar: Text(projectType(p.type).$2),
            label: Text('${p.name} · ${projectStatusText(p.status)}'),
            onPressed: () => widget.onOpenProject(p.id),
          ),
      ]),
    ]);
  }
}

/// ขั้นงานทั้งหมด แบ่งกลุ่มตามกำหนด · เสร็จแล้วพับไว้
class AllTasksView extends StatefulWidget {
  const AllTasksView({super.key, required this.onOpenProject});
  final ValueChanged<int> onOpenProject;

  @override
  State<AllTasksView> createState() => _AllTasksViewState();
}

class _AllTasksViewState extends State<AllTasksView> with _WorkData<AllTasksView> {
  bool _showDone = false;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (!loaded) return const SizedBox.shrink();
    final today = DateTime.now();
    final open = openTasks(projects, tasks);
    final done = [
      for (final p in projects)
        for (final t in tasks[p.id] ?? const <ProjectTask>[])
          if (t.done) (p, t)
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      if (open.isEmpty && done.isEmpty) Text('ยังไม่มีขั้นงาน · เพิ่มในการ์ดโปรเจกต์ (แท็บบอร์ด)', style: TextStyle(color: c.muted)),
      for (final b in TaskBucket.values)
        if (open.any((x) => taskBucket(x.$2, today) == b)) ...[
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 2),
            child: Text('${taskBucketText(b)} · ${open.where((x) => taskBucket(x.$2, today) == b).length}',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: b == TaskBucket.overdue ? c.bad : c.text)),
          ),
          for (final (p, t) in open.where((x) => taskBucket(x.$2, today) == b))
            _taskRow(context, c, p, t, today, toggleTask, widget.onOpenProject, keyPrefix: 'all-task'),
        ],
      if (done.isNotEmpty) ...[
        const SizedBox(height: 12),
        TextButton.icon(
          key: const Key('all-done-toggle'),
          onPressed: () => setState(() => _showDone = !_showDone),
          icon: Icon(_showDone ? Icons.expand_less : Icons.expand_more),
          label: Text('เสร็จแล้ว ${done.length}'),
        ),
        if (_showDone)
          for (final (p, t) in done) _taskRow(context, c, p, t, today, toggleTask, widget.onOpenProject, keyPrefix: 'all-task'),
      ],
    ]);
  }
}
