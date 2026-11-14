/// หน้าสกิล (รอบ 8C): รายชื่อซ้าย · รายละเอียดขวา (คอม) / ทีละหน้า (มือถือ)
/// เป้า + กราฟ · บันทึกแต่ละรอบ · Portfolio · ประเมินรายเดือน
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../calendar/calendar_ui.dart' show categoryAccent;
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'skill_forms.dart';
import 'skill_models.dart';
import 'skill_progress.dart';
import 'skill_repository.dart';

const _wide = 900.0;

class SkillsPage extends StatefulWidget {
  const SkillsPage({super.key});

  @override
  State<SkillsPage> createState() => _SkillsPageState();
}

class _SkillsPageState extends State<SkillsPage> {
  CalendarRepository? _cal;
  SkillRepository? _repo;
  List<Skill> _skills = const [];
  int? _selected;
  bool _showDetail = false; // มือถือ: เปิดรายละเอียดอยู่
  List<SkillGoal> _goals = const [];
  List<SkillLog> _logs = const [];
  List<SkillFile> _files = const [];
  SkillReview? _review;
  Map<DateTime, int> _practice = const {};
  List<Activity> _plans = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cal = CalendarScope.of(context);
    if (cal != _cal) {
      _repo?.removeListener(_load);
      _cal?.removeListener(_load);
      _cal = cal..addListener(_load);
      _repo = cal.skillRepo..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_load);
    _cal?.removeListener(_load);
    super.dispose();
  }

  Skill? get _skill => _skills.where((s) => s.id == _selected).firstOrNull;

  Future<void> _load() async {
    final repo = _repo!, cal = _cal!;
    final skills = await repo.skills();
    var sel = _selected;
    if (sel == null || !skills.any((s) => s.id == sel)) {
      sel = (skills.where((s) => s.status == SkillStatus.active).firstOrNull ?? skills.firstOrNull)?.id;
    }
    var goals = <SkillGoal>[], logs = <SkillLog>[], files = <SkillFile>[];
    SkillReview? review;
    final practice = <DateTime, int>{};
    final plans = <Activity>[];
    if (sel != null) {
      goals = await repo.goals(sel);
      logs = await repo.logs(sel);
      files = await repo.files(sel);
      review = await repo.review(sel, monthKey(DateTime.now()));
      final acts = (await repo.activitiesOf(sel)).toSet();
      for (final id in acts) {
        try {
          plans.add(await cal.activity(id));
        } catch (_) {/* งานถูกลบไปแล้ว */}
      }
      if (acts.isNotEmpty) {
        // นาทีที่ฝึกจริงจากปฏิทิน 12 สัปดาห์ล่าสุด (ไว้คิดเป้าแบบปริมาณ)
        final today = dayOnly(DateTime.now());
        final byDay = await cal.occurrencesBetween(today.subtract(const Duration(days: 84)), today);
        for (final e in byDay.entries) {
          for (final o in e.value) {
            if (!acts.contains(o.activityId) || o.status != OccurrenceStatus.done || !o.timed) continue;
            final m = (o.actualEnd ?? o.endAt!).difference(o.actualStart ?? o.startAt!).inMinutes;
            practice[e.key] = (practice[e.key] ?? 0) + (m > 0 ? m : 0);
          }
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _skills = skills;
      _selected = sel;
      _goals = goals;
      _logs = logs;
      _files = files;
      _review = review;
      _practice = practice;
      _plans = plans;
    });
  }

  Future<void> _add() async {
    final id = await editSkillForm(context, _repo!);
    if (id != null) {
      setState(() {
        _selected = id;
        _showDetail = true;
      });
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= _wide;
      if (wide) {
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 260, child: _list(context)),
          Expanded(child: _skill == null ? _empty(context) : _detail(context, _skill!)),
        ]);
      }
      if (_showDetail && _skill != null) return _detail(context, _skill!, back: true);
      return _list(context);
    });
  }

  Widget _empty(BuildContext context) {
    final c = context.noir;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text('🎯', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text('สกิล = สิ่งที่ฝึกเอง ไม่มีตารางจากอาจารย์ ไม่มีเกรด', style: TextStyle(color: c.text)),
          Text('ตั้งเป้าเอง ฝึกจนพอใจ แล้วกด "จบ" ไปฝึกอย่างอื่น · ทุกรอบเก็บเป็น Portfolio',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 12),
          FilledButton.icon(key: const Key('skill-add-empty'), onPressed: _add, icon: const Icon(Icons.add), label: const Text('เพิ่มสกิล')),
        ]),
      ),
    );
  }

  Widget _list(BuildContext context) {
    final c = context.noir;
    final groups = [
      for (final st in SkillStatus.values)
        (st, _skills.where((s) => s.status == st).toList()),
    ];
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 8, 24), children: [
      Row(children: [
        Expanded(child: Text('สกิล', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text))),
        TextButton.icon(key: const Key('skill-add'), onPressed: _add, icon: const Icon(Icons.add, size: 18), label: const Text('เพิ่ม')),
      ]),
      if (_skills.isEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text('ยังไม่มีสกิล · กด "เพิ่ม" เช่น DaVinci Resolve, English', style: TextStyle(fontSize: 12, color: c.muted)),
        ),
      for (final (st, list) in groups)
        if (list.isNotEmpty) ...[
          if (st != SkillStatus.active)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 12, 0, 4),
              child: Text(skillStatusText(st), style: TextStyle(fontSize: 12, color: c.muted)),
            ),
          for (final s in list)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: s.id == _selected ? c.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  key: ValueKey('skill-${s.id}'),
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    setState(() {
                      _selected = s.id;
                      _showDetail = true;
                    });
                    _load();
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(children: [
                      _iconBox(s, 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(s.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontWeight: FontWeight.w600, color: st == SkillStatus.active ? c.text : c.muted)),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ],
    ]);
  }

  Widget _iconBox(Skill s, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: categoryAccent(s.colorKey).withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(size * 0.28),
        ),
        child: Text(s.icon, style: TextStyle(fontSize: size * 0.5)),
      );

  // ---------- รายละเอียด ----------

  Future<void> _skillMenu(Skill s, Offset at) async {
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
      ctxItem('plan', Icons.event_repeat, 'ตั้งแผนฝึก (ลงปฏิทิน)'),
      if (s.status == SkillStatus.active) ctxItem('pause', Icons.pause_circle_outline, 'พักไว้'),
      if (s.status != SkillStatus.active) ctxItem('resume', Icons.play_circle_outline, 'กลับมาฝึก'),
      if (s.status != SkillStatus.done) ctxItem('done', Icons.emoji_events_outlined, 'จบแล้ว'),
      ctxItem('delete', Icons.delete_outline, 'ลบสกิล', danger: true),
    ]);
    if (!mounted || v == null) return;
    final repo = _repo!;
    switch (v) {
      case 'edit':
        await editSkillForm(context, repo, skill: s);
      case 'plan':
        if (await planPracticeForm(context, _cal!, s) && mounted) showToast(context, 'ลงแผนฝึกในปฏิทินแล้ว');
      case 'pause':
        await repo.saveSkill(s.copyWith(status: SkillStatus.paused));
      case 'resume':
        await repo.saveSkill(s.copyWith(status: SkillStatus.active, clearDone: true));
      case 'done':
        await _finish(s);
      case 'delete':
        if (await confirmMini(context,
            title: 'ลบ "${s.name}"?',
            message: 'เป้า บันทึก และผลงานในสกิลนี้หายด้วย (งานในปฏิทินยังอยู่)',
            okLabel: 'ลบ',
            danger: true)) {
          await repo.deleteSkill(s.id);
          setState(() => _showDetail = false);
        }
    }
  }

  Future<void> _finish(Skill s) async {
    await _repo!.saveSkill(s.copyWith(status: SkillStatus.done, doneAt: DateTime.now()));
    if (mounted) showToast(context, 'จบ "${s.name}" แล้ว 🏆 · ไปฝึกอะไรต่อดี?', action: 'เพิ่มสกิล', onAction: _add);
  }

  String _planText() {
    if (_plans.isEmpty) return '';
    final a = _plans.first;
    const wd = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];
    final days = [for (final d in (a.weekdays.toList()..sort())) wd[d - 1]].join(' ');
    final t = a.startMinute == null ? '' : ' · ${(a.startMinute! ~/ 60).toString().padLeft(2, '0')}:${(a.startMinute! % 60).toString().padLeft(2, '0')}';
    final len = a.durationMin == null ? '' : ' · ${a.durationMin} นาที';
    return 'แผน: $days$t$len${_plans.length > 1 ? ' (+${_plans.length - 1})' : ''}';
  }

  Widget _detail(BuildContext context, Skill s, {bool back = false}) {
    final c = context.noir;
    final today = DateTime.now();
    final active = _goals.where((g) => g.status == GoalStatus.active).toList();
    final past = _goals.where((g) => g.status != GoalStatus.active).toList();
    return ListView(padding: const EdgeInsets.fromLTRB(16, 12, 24, 32), children: [
      Row(children: [
        if (back)
          IconButton(
            tooltip: 'กลับ',
            onPressed: () => setState(() => _showDetail = false),
            icon: const Icon(Icons.arrow_back),
          ),
        _iconBox(s, 48),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.name, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600, color: c.text)),
            Text(
              '${skillStatusText(s.status)} · เริ่ม ${thaiShortDate(s.startedAt)}${s.doneAt == null ? '' : ' · จบ ${thaiShortDate(s.doneAt!)}'}',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
          ]),
        ),
        Builder(
          builder: (bctx) => IconButton(
            key: const Key('skill-menu'),
            tooltip: 'เมนู',
            onPressed: () {
              final box = bctx.findRenderObject() as RenderBox;
              _skillMenu(s, box.localToGlobal(box.size.center(Offset.zero)));
            },
            icon: const Icon(Icons.more_vert),
          ),
        ),
      ]),
      if (s.why != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text('🎯 ${s.why}', style: TextStyle(color: c.muted))),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        if (_plans.isNotEmpty)
          Chip(label: Text(_planText()), visualDensity: VisualDensity.compact)
        else
          OutlinedButton.icon(
            key: const Key('skill-plan'),
            onPressed: () async {
              if (await planPracticeForm(context, _cal!, s) && context.mounted) showToast(context, 'ลงแผนฝึกในปฏิทินแล้ว');
            },
            icon: const Icon(Icons.event_repeat, size: 18),
            label: const Text('ตั้งแผนฝึก'),
          ),
        FilledButton.icon(
          key: const Key('skill-log'),
          onPressed: () => editLogForm(context, _repo!, s),
          icon: const Icon(Icons.edit_note, size: 18),
          label: const Text('บันทึกรอบ'),
        ),
      ]),

      // ---- เป้า ----
      _header(c, 'เป้า', TextButton.icon(
        key: const Key('goal-add'),
        onPressed: () => editGoalForm(context, _repo!, s.id),
        icon: const Icon(Icons.add, size: 18),
        label: const Text('เป้า'),
      )),
      if (active.isEmpty)
        Text('ยังไม่มีเป้า · ตั้งได้ 4 แบบ: ปริมาณ (ชม./สัปดาห์) · เร็วขึ้น (≤ เวลา) · จำนวน (ต่อวัน) · ด่าน (เช็กลิสต์)',
            style: TextStyle(fontSize: 12, color: c.muted)),
      for (final g in active) _goalCard(context, s, g, goalProgress(g, _logs, practiceMinutes: _practice, today: today)),
      if (past.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('เป้าที่ผ่านแล้ว: ${past.map((g) => g.title).join(' · ')}', style: TextStyle(fontSize: 12, color: c.muted)),
        ),

      // ---- บันทึก ----
      _header(c, 'บันทึกแต่ละรอบ', null),
      if (_logs.isEmpty) Text('ยังไม่มี · กด "บันทึกรอบ" หรือกด "ทำแล้ว" ที่งานฝึกในปฏิทิน', style: TextStyle(fontSize: 12, color: c.muted)),
      for (final l in _logs.take(20)) _logRow(context, s, l),

      // ---- Portfolio ----
      _header(c, 'Portfolio', Wrap(children: [
        TextButton.icon(
          key: const Key('pf-add'),
          onPressed: () async {
            final n = await addPortfolioFiles(_repo!, s.id);
            if (n > 0 && context.mounted) showToast(context, 'เพิ่มผลงาน $n ชิ้นแล้ว');
          },
          icon: const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: const Text('รูป / ไฟล์'),
        ),
        TextButton.icon(
          key: const Key('pf-link'),
          onPressed: () => addPortfolioLink(context, _repo!, s.id),
          icon: const Icon(Icons.link, size: 18),
          label: const Text('ลิงก์'),
        ),
      ])),
      if (_files.isEmpty)
        Text('เก็บรูป ไฟล์งาน ลิงก์คลิป · คลิกขวา = ⭐ ผลงานเด่น / ลบ', style: TextStyle(fontSize: 12, color: c.muted))
      else
        Wrap(spacing: 10, runSpacing: 10, children: [for (final f in _files) _fileTile(context, f)]),

      // ---- ประเมินรายเดือน ----
      _header(c, 'ประเมินตัวเอง · ${thaiMonthYear(today)}', TextButton(
        key: const Key('review-edit'),
        onPressed: () => reviewForm(context, _repo!, s, today),
        child: Text(_review == null ? 'ประเมิน' : 'แก้'),
      )),
      if (_review == null)
        Text('ทุกสิ้นเดือน: ทำได้แล้ว · ยังอ่อน · เป้าถัดไป', style: TextStyle(fontSize: 12, color: c.muted))
      else
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          for (final (k, v) in [('ทำได้แล้ว', _review!.can), ('ยังอ่อน', _review!.weak), ('เป้าถัดไป', _review!.nextGoal)])
            if (v != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(width: 90, child: Text(k, style: TextStyle(fontSize: 13, color: c.muted))),
                  Expanded(child: Text(v, style: TextStyle(fontSize: 13, color: c.text))),
                ]),
              ),
        ]),
    ]);
  }

  Widget _header(NoirColors c, String title, Widget? action) => Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Row(children: [
          Expanded(child: Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
          ?action,
        ]),
      );

  Widget _goalCard(BuildContext context, Skill s, SkillGoal g, GoalProgress p) {
    final c = context.noir;
    final repo = _repo!;
    return Card(
      key: ValueKey('goal-${g.id}'),
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: c.accent.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
              child: Text(goalKindText(g.kind), style: TextStyle(fontSize: 11, color: c.accent)),
            ),
            const SizedBox(width: 8),
            Expanded(child: Text(g.title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
            PopupMenuButton<String>(
              tooltip: 'เมนูเป้า',
              icon: Icon(Icons.more_horiz, color: c.muted),
              onSelected: (v) async {
                if (v == 'edit') await editGoalForm(context, repo, s.id, goal: g);
                if (v == 'delete') await repo.deleteGoal(g.id);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('แก้เป้า')),
                PopupMenuItem(value: 'delete', child: Text('ลบเป้า')),
              ],
            ),
          ]),
          Text(goalRuleText(g), style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 8),
          Wrap(spacing: 18, runSpacing: 6, children: [
            _kpi(c, 'ตอนนี้', p.current),
            if (p.best != null) _kpi(c, 'ดีที่สุด', p.best!),
            if (g.kind != GoalKind.milestone) _kpi(c, 'ติดกัน', '${p.run} / ${g.streak}'),
          ]),
          if (p.ratio != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: p.ratio, minHeight: 6, backgroundColor: c.surface2, color: c.good),
            ),
          ],
          if (p.series.length >= 2) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: 90,
              child: CustomPaint(
                painter: _LinePainter(
                  [for (final x in p.series) x.$2],
                  target: g.kind == GoalKind.milestone ? null : g.target,
                  line: c.accent,
                  targetColor: c.good,
                  grid: c.line,
                ),
              ),
            ),
          ],
          if (g.kind == GoalKind.milestone)
            for (final (i, st) in g.steps.indexed)
              CheckboxListTile(
                key: ValueKey('step-${g.id}-$i'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: st.done,
                title: Text(st.title),
                onChanged: (v) => repo.saveGoal(g.copyWith(steps: [
                  for (final (k, x) in g.steps.indexed) k == i ? GoalStep(x.title, done: v ?? false) : x,
                ])),
              ),
          // ถึงเป้า → ถาม (ไม่หยุดเอง): จบ · พัก · ยกระดับเป้า
          if (p.met) ...[
            const SizedBox(height: 10),
            Container(
              key: ValueKey('goal-met-${g.id}'),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: c.good.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Text('🎉 ถึงเป้าแล้ว · พอใจแล้วไหม?', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                const SizedBox(height: 6),
                Wrap(spacing: 8, runSpacing: 6, children: [
                  FilledButton(
                    onPressed: () async {
                      await repo.saveGoal(g.copyWith(status: GoalStatus.met));
                      await _finish(s);
                    },
                    child: const Text('จบแล้ว'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      await repo.saveGoal(g.copyWith(status: GoalStatus.met));
                      await repo.saveSkill(s.copyWith(status: SkillStatus.paused));
                    },
                    child: const Text('พักไว้'),
                  ),
                  OutlinedButton(
                    key: ValueKey('goal-raise-${g.id}'),
                    onPressed: () => editGoalForm(context, repo, s.id, from: g),
                    child: const Text('ยกระดับเป้า'),
                  ),
                ]),
              ]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _kpi(NoirColors c, String k, String v) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(k, style: TextStyle(fontSize: 11, color: c.muted)),
        Text(v, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.accent)),
      ]);

  Widget _logRow(BuildContext context, Skill s, SkillLog l) {
    final c = context.noir;
    final g = _goals.where((x) => x.id == l.goalId).firstOrNull;
    final attached = _files.where((f) => f.logId == l.id).toList();
    Future<void> menu(Offset at) async {
      final v = await showContextMenuAt<String>(context, at, [
        ctxItem('edit', Icons.edit_outlined, 'แก้บันทึก'),
        ctxItem('attach', Icons.attach_file, 'แนบรูป / ไฟล์'),
        ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
      ]);
      if (!context.mounted) return;
      if (v == 'edit') await editLogForm(context, _repo!, s, log: l);
      if (v == 'attach') await addPortfolioFiles(_repo!, s.id, logId: l.id);
      if (v == 'delete') await _repo!.deleteLog(l.id);
    }

    final head = [
      if (l.skipped) 'ไม่ได้ฝึก',
      if (g != null && l.value != null) fmtGoalValue(l.value!, g.unit),
      if (l.minutes != null) '${l.minutes} นาที',
      if (l.rating != null) '★' * l.rating! + '☆' * (5 - l.rating!),
    ].join(' · ');
    final notes = [
      if (l.better != null) 'ดีขึ้น: ${l.better}',
      if (l.stuck != null) '${l.skipped ? 'เหตุผล' : 'ติด'}: ${l.stuck}',
      if (l.next != null) 'ครั้งหน้า: ${l.next}',
    ].join(' · ');
    return GestureDetector(
      onSecondaryTapUp: (e) => menu(e.globalPosition),
      onLongPressStart: (e) => menu(e.globalPosition),
      child: Container(
        key: ValueKey('log-${l.id}'),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 80, child: Text(thaiShortDate(l.day), style: TextStyle(fontSize: 12, color: c.muted))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(head.isEmpty ? 'บันทึก' : head,
                  style: TextStyle(fontWeight: FontWeight.w600, color: l.skipped ? c.warn : c.text)),
              if (notes.isNotEmpty) Text(notes, style: TextStyle(fontSize: 12, color: c.muted)),
              if (attached.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Wrap(spacing: 4, children: [for (final f in attached) _thumb(c, f, 40)]),
                ),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _thumb(NoirColors c, SkillFile f, double size) => Container(
        width: size,
        height: size,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(8)),
        child: f.kind == SkillFileKind.image
            ? Image.file(File(f.path), fit: BoxFit.cover, errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: c.muted))
            : Icon(f.kind == SkillFileKind.link ? Icons.link : Icons.insert_drive_file_outlined, color: c.muted, size: size * 0.5),
      );

  Widget _fileTile(BuildContext context, SkillFile f) {
    final c = context.noir;
    Future<void> menu(Offset at) async {
      final v = await showContextMenuAt<String>(context, at, [
        ctxItem('star', Icons.star_outline, f.featured ? 'เลิกเป็นผลงานเด่น' : '⭐ ผลงานเด่น'),
        ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
      ]);
      if (v == 'star') await _repo!.saveFile(f.copyWith(featured: !f.featured));
      if (v == 'delete') await _repo!.deleteFile(f.id);
    }

    return GestureDetector(
      onSecondaryTapUp: (e) => menu(e.globalPosition),
      onLongPressStart: (e) => menu(e.globalPosition),
      child: InkWell(
        key: ValueKey('pf-${f.id}'),
        borderRadius: BorderRadius.circular(12),
        onTap: () => _open(context, f),
        child: Container(
          width: 150,
          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(height: 84, child: _thumb(c, f, 84)),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${f.featured ? '⭐ ' : ''}${f.title}',
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text)),
                Text(thaiShortDate(f.addedAt), style: TextStyle(fontSize: 11, color: c.muted)),
              ]),
            ),
          ]),
        ),
      ),
    );
  }

  /// รูป = ดูใหญ่ · ลิงก์ = คัดลอก · ไฟล์ = บอกที่อยู่ (คัดลอก)
  Future<void> _open(BuildContext context, SkillFile f) async {
    if (f.kind == SkillFileKind.image) {
      await showDialog<void>(
        context: context,
        builder: (ctx) => Dialog(
          clipBehavior: Clip.antiAlias,
          child: InkWell(onTap: () => Navigator.pop(ctx), child: Image.file(File(f.path), fit: BoxFit.contain)),
        ),
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: f.path));
    if (context.mounted) showToast(context, f.kind == SkillFileKind.link ? 'คัดลอกลิงก์แล้ว' : 'คัดลอกที่อยู่ไฟล์แล้ว');
  }
}

/// กราฟเส้นเล็ก + เส้นเป้า (ประ)
class _LinePainter extends CustomPainter {
  _LinePainter(this.values, {this.target, required this.line, required this.targetColor, required this.grid});
  final List<double> values;
  final double? target;
  final Color line;
  final Color targetColor;
  final Color grid;

  @override
  void paint(Canvas canvas, Size size) {
    final all = [...values, ?target];
    var lo = all.reduce((a, b) => a < b ? a : b), hi = all.reduce((a, b) => a > b ? a : b);
    if (hi - lo < 1e-9) {
      lo -= 1;
      hi += 1;
    }
    final pad = (hi - lo) * 0.12;
    lo -= pad;
    hi += pad;
    double y(double v) => size.height - (v - lo) / (hi - lo) * size.height;
    double x(int i) => values.length == 1 ? size.width / 2 : i * size.width / (values.length - 1);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, size.height), Paint()..color = grid);
    if (target != null) {
      final p = Paint()
        ..color = targetColor
        ..strokeWidth = 1.5;
      for (var dx = 0.0; dx < size.width; dx += 10) {
        canvas.drawLine(Offset(dx, y(target!)), Offset(dx + 5, y(target!)), p);
      }
    }
    final path = Path()..moveTo(x(0), y(values[0]));
    for (var i = 1; i < values.length; i++) {
      path.lineTo(x(i), y(values[i]));
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line
          ..strokeWidth = 2.5
          ..style = PaintingStyle.stroke);
    final dot = Paint()..color = line;
    for (var i = 0; i < values.length; i++) {
      canvas.drawCircle(Offset(x(i), y(values[i])), 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values || old.target != target || old.line != line;
}
