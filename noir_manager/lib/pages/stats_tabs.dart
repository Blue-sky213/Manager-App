/// เมนู "สถิติ" (รอบ 9C): ทุกเรื่องอยู่ที่เดียว · แท็บ ภาพรวม · เรียน · สกิล · งาน · เงิน · ชีวิต
/// ภาพรวม = การ์ดละเรื่อง (30 วันล่าสุด) คลิกการ์ด = ไปแท็บนั้น · ชีวิต = หน้าสถิติเดิม (ปฏิทิน · Streak · เหรียญ)
library;

import 'package:flutter/material.dart';

import '../calendar/achievements.dart';
import '../calendar/calendar_models.dart' show dayOnly;
import '../calendar/calendar_repository.dart';
import '../data/study_scope.dart';
import '../shell/app_nav.dart' show currentTab;
import '../skills/skill_models.dart';
import '../skills/skill_tree.dart';
import '../study/mastery.dart';
import '../study/term_overview.dart' show termSubjects;
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/menu_header.dart';
import '../work/money_calc.dart';
import '../work/money_models.dart';
import '../work/project_calc.dart';
import '../work/project_models.dart';
import 'stats_page.dart';

enum StatsTab { overview, learn, skill, work, money, life }

const _tabLabel = {
  StatsTab.overview: 'ภาพรวม',
  StatsTab.learn: 'เรียน',
  StatsTab.skill: 'สกิล',
  StatsTab.work: 'งาน',
  StatsTab.money: 'เงิน',
  StatsTab.life: 'ชีวิต',
};

/// 1 สกิลในสถิติ
class _SkillRow {
  const _SkillRow(this.skill, this.hours, this.recent, this.ratio);
  final Skill skill;
  final double hours;
  final double recent; // 30 วัน
  final double ratio;
}

class StatsPage extends StatefulWidget {
  const StatsPage({super.key});

  @override
  State<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends State<StatsPage> {
  StatsTab _tab = StatsTab.overview;
  CalendarRepository? _cal;
  bool _loaded = false;
  bool _stale = false;

  // ปฏิทิน
  double? _planPct;
  StreakInfo? _streak;
  double? _sleep, _energy;
  // เรียน
  List<(String, double?, int)> _subjects = const []; // ชื่อ · เข้าใจเฉลี่ย · จำนวนหัวข้อ
  // สกิล
  List<_SkillRow> _skills = const [];
  // งาน
  List<Project> _projects = const [];
  WorkSummary? _work;
  List<(Project, double)> _profits = const [];
  // เงิน
  List<MoneyEntry> _money = const [];

  DateTime get _today => dayOnly(DateTime.now());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cal = CalendarScope.of(context);
    if (cal != _cal) {
      _cal?.removeListener(_changed);
      _cal?.skillRepo.removeListener(_changed);
      _cal?.workRepo.removeListener(_changed);
      _cal = cal
        ..addListener(_changed)
        ..skillRepo.addListener(_changed)
        ..workRepo.addListener(_changed);
      currentTab.addListener(_onMenu);
      _load();
    }
  }

  @override
  void dispose() {
    _cal?.removeListener(_changed);
    _cal?.skillRepo.removeListener(_changed);
    _cal?.workRepo.removeListener(_changed);
    currentTab.removeListener(_onMenu);
    super.dispose();
  }

  // หน้าซ่อนอยู่ (อยู่เมนูอื่น) → ไม่โหลดทุกครั้งที่ข้อมูลเปลี่ยน รอกลับมาค่อยโหลดครั้งเดียว
  bool get _hidden => currentTab.value != 'สถิติ' && context.findAncestorWidgetOfExactType<IndexedStack>() != null;

  void _changed() {
    if (!mounted) return;
    if (_hidden) {
      _stale = true;
    } else {
      _load();
    }
  }

  void _onMenu() {
    if (_stale && mounted && !_hidden) {
      _stale = false;
      _load();
    }
  }

  Future<void> _load() async {
    final cal = _cal!;
    final study = StudyScope.of(context);
    final today = _today;
    final from = today.subtract(const Duration(days: 29));

    final days = await cal.occurrencesBetween(today.subtract(const Duration(days: 90)), today);
    final recent = [for (final e in days.entries) if (!e.key.isBefore(from)) ...e.value];
    final checkins = await cal.checkins(from, today.add(const Duration(days: 1)));
    final sleeps = [for (final c in checkins) if (c.sleepHours != null && c.sleepHours! > 0 && c.sleepHours! < 16) c.sleepHours!];
    final energies = [for (final c in checkins) if (c.energy != null) c.energy!];

    final mode = await study.gradingMode();
    final subs = <(String, double?, int)>[];
    for (final s in await termSubjects(await study.subjects(), cal, today)) {
      final topics = [for (final ch in await study.chapters(s.id)) ...ch.subtopics];
      final scores = [for (final t in topics) if (shownScore(t, mode) != null) shownScore(t, mode)!];
      subs.add((s.name, scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length, topics.length));
    }

    final sr = cal.skillRepo;
    final nodes = await sr.nodes();
    final skills = <_SkillRow>[];
    for (final s in await sr.skills()) {
      final logs = await sr.logs(s.id);
      skills.add(_SkillRow(
        s,
        practiceHours(logs),
        practiceHours([for (final l in logs) if (!l.day.isBefore(from)) l]),
        skillRatio(s, nodes: nodes.where((n) => n.skillId == s.id).toList(), goals: await sr.goals(s.id), logs: logs, today: today),
      ));
    }
    skills.sort((a, b) => b.recent != a.recent ? b.recent.compareTo(a.recent) : b.hours.compareTo(a.hours));

    final wr = cal.workRepo;
    final projects = await wr.projects();
    final tasks = {for (final p in projects) p.id: await wr.tasks(p.id)};
    final pays = {for (final p in projects) p.id: await wr.payments(p.id)};
    final money = await wr.entries(DateTime(today.year - 1, today.month, 1), DateTime(today.year, today.month + 1, 0));
    final pjEntries = [for (final e in await wr.entries(DateTime(2000), DateTime(2100))) if (e.projectId != null) e];
    final profits = [
      for (final p in projects)
        if (p.status == ProjectStatus.paid) (p, projectMoney(p, pjEntries, pays[p.id] ?? const []).profit)
    ]..sort((a, b) => b.$2.compareTo(a.$2));

    if (!mounted) return;
    setState(() {
      _planPct = percentDone(recent);
      _streak = streakOf(days, today);
      _sleep = sleeps.isEmpty ? null : sleeps.reduce((a, b) => a + b) / sleeps.length;
      _energy = energies.isEmpty ? null : energies.reduce((a, b) => a + b) / energies.length;
      _subjects = subs;
      _skills = skills;
      _projects = projects;
      _work = workSummary(projects, tasks, pays, pjEntries, today);
      _profits = profits;
      _money = money;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MenuHeader(
          group: 'สรุป',
          title: 'สถิติ',
          tabs: MenuTabs<StatsTab>(
            key: const Key('stats-tabs'),
            value: _tab,
            items: [for (final t in StatsTab.values) (t, _tabLabel[t]!)],
            onChanged: (t) => setState(() => _tab = t),
          ),
        ),
        Expanded(
          child: IndexedStack(index: _tab.index, children: [
            _wrap(_overview),
            _wrap(_learn),
            _wrap(_skill),
            _wrap(_workTab),
            _wrap(_moneyTab),
            const LifeStats(),
          ]),
        ),
      ]);

  Widget _wrap(List<Widget> Function(NoirColors) build) {
    if (!_loaded) return const SizedBox.shrink();
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: build(context.noir));
  }

  String _pct(double? v) => v == null ? '—' : '${v.round()}%';
  String _h(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(1);
  Color _level(NoirColors c, double? v) => v == null ? c.muted : (v >= 80 ? c.good : (v >= 60 ? c.warn : c.bad));

  Widget _bar(NoirColors c, double ratio, Color color) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: ratio.clamp(0.0, 1.0), minHeight: 6, backgroundColor: c.surface2, color: color),
      );

  Widget _head(NoirColors c, String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(t, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
      );

  Widget _empty(NoirColors c, String t) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(t, style: TextStyle(fontSize: 12, color: c.muted)),
      );

  // ---------------- ภาพรวม ----------------

  List<Widget> _overview(NoirColors c) {
    final m = monthSummary(_money, _today);
    final w = _work!;
    final avgs = [for (final s in _subjects) if (s.$2 != null) s.$2!];
    final avg = avgs.isEmpty ? null : avgs.reduce((a, b) => a + b) / avgs.length;
    final recent = _skills.fold<double>(0, (a, s) => a + s.recent);
    final topSkills = _skills.where((s) => s.recent > 0).take(2).map((s) => '${s.skill.name} ${_h(s.recent)}').join(' · ');
    final income = m.income == 0 ? null : (m.net / m.income);
    Widget card(StatsTab t, String title, String value, double? ratio, String sub, {Color? color}) => InkWell(
          key: ValueKey('stats-card-${t.name}'),
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _tab = t),
          child: Container(
            width: 260,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: TextStyle(fontSize: 12, color: c.muted)),
              Text(value, key: ValueKey('stats-value-${t.name}'), style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: color ?? c.text)),
              const SizedBox(height: 4),
              _bar(c, ratio ?? 0, color ?? c.accent),
              const SizedBox(height: 4),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
            ]),
          ),
        );
    return [
      Text('30 วันล่าสุด · คลิกการ์ด = ดูละเอียด', style: TextStyle(fontSize: 12, color: c.muted)),
      const SizedBox(height: 10),
      Wrap(spacing: 12, runSpacing: 12, children: [
        card(StatsTab.life, '🗓️ ทำตามแผน', _pct(_planPct), (_planPct ?? 0) / 100,
            'Streak ${_streak?.current ?? 0} วัน · ดีสุด ${_streak?.best ?? 0}',
            color: _level(c, _planPct)),
        card(StatsTab.learn, '🎓 เข้าใจเฉลี่ย', _pct(avg), (avg ?? 0) / 100, '${_subjects.length} วิชาเทอมนี้', color: _level(c, avg)),
        card(StatsTab.skill, '🌟 ฝึกสกิล', '${_h(recent)} ชม.', _skills.isEmpty ? 0 : (recent / 30).clamp(0, 1).toDouble(),
            topSkills.isEmpty ? '${_skills.length} สกิล · ยังไม่ได้ฝึก' : topSkills),
        card(StatsTab.work, '💼 โปรเจกต์', '${w.doing} กำลังทำ', w.tasksTotal == 0 ? 0 : w.tasksDone / w.tasksTotal,
            'ขั้นงานเสร็จ ${w.tasksDone}/${w.tasksTotal}${w.overdue > 0 ? ' · เลยกำหนด ${w.overdue}' : ''}'),
        card(StatsTab.money, '💰 เหลือเดือนนี้', baht(m.net), income ?? 0, 'รับ ${baht(m.income)} · จ่าย ${baht(m.expense)}',
            color: m.net >= 0 ? c.good : c.bad),
        card(StatsTab.life, '😴 นอนเฉลี่ย', _sleep == null ? '—' : '${_sleep!.toStringAsFixed(1)} ชม.', (_sleep ?? 0) / 8,
            _energy == null ? 'ยังไม่มีเช็กอินเช้า' : 'พลังเช้า ${_energy!.toStringAsFixed(1)}/5'),
      ]),
    ];
  }

  // ---------------- แท็บย่อย ----------------

  List<Widget> _learn(NoirColors c) => [
        _head(c, 'เข้าใจรายวิชา (เทอมนี้)'),
        if (_subjects.isEmpty) _empty(c, 'ยังไม่มีวิชา'),
        for (final (name, avg, n) in _subjects)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(width: 120, child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.text))),
              Expanded(child: _bar(c, (avg ?? 0) / 100, _level(c, avg))),
              const SizedBox(width: 8),
              SizedBox(
                width: 92,
                child: Text('${_pct(avg)} · $n หัวข้อ', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.muted)),
              ),
            ]),
          ),
      ];

  List<Widget> _skill(NoirColors c) => [
        _head(c, 'ชั่วโมงฝึก (30 วัน / ทั้งหมด)'),
        if (_skills.isEmpty) _empty(c, 'ยังไม่มีสกิล · เพิ่มในเมนูสกิล'),
        for (final s in _skills)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              SizedBox(
                width: 120,
                child: Text('${s.skill.icon} ${s.skill.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.text)),
              ),
              Expanded(child: _bar(c, s.ratio, s.ratio >= 1 ? c.good : c.accent)),
              const SizedBox(width: 8),
              SizedBox(
                width: 120,
                child: Text('Lv ${skillLevel(s.hours)} · ${_h(s.recent)} / ${_h(s.hours)} ชม.',
                    textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.muted)),
              ),
            ]),
          ),
        if (_skills.isNotEmpty) Text('แถบ = ความคืบหน้าของเป้า / ทักษะย่อย', style: TextStyle(fontSize: 12, color: c.muted)),
      ];

  List<Widget> _workTab(NoirColors c) {
    final w = _work!;
    return [
      _head(c, 'โปรเจกต์ตามสถานะ'),
      if (_projects.isEmpty) _empty(c, 'ยังไม่มีโปรเจกต์'),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final s in ProjectStatus.values)
          Chip(label: Text('${projectStatusText(s)} ${_projects.where((p) => p.status == s).length}')),
      ]),
      _head(c, 'ขั้นงาน'),
      _bar(c, w.tasksTotal == 0 ? 0 : w.tasksDone / w.tasksTotal, c.good),
      const SizedBox(height: 4),
      Text('เสร็จ ${w.tasksDone}/${w.tasksTotal} · เลยกำหนด ${w.overdue} · รอเก็บเงิน ${baht(w.pending)}',
          style: TextStyle(fontSize: 12, color: c.muted)),
      _head(c, 'กำไรงานที่ปิดแล้ว'),
      if (_profits.isEmpty) _empty(c, 'ยังไม่มีงานที่เก็บเงินครบ'),
      for (final (p, v) in _profits)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(children: [
            Expanded(child: Text('${projectType(p.type).$2} ${p.name}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.text))),
            Text(baht(v), style: TextStyle(fontWeight: FontWeight.w600, color: v >= 0 ? c.good : c.bad)),
          ]),
        ),
    ];
  }

  List<Widget> _moneyTab(NoirColors c) {
    final months = lastMonths(_money, DateTime(_today.year, _today.month), n: 12);
    final maxV = months.fold<double>(1, (m, x) => [m, x.$2, x.$3].reduce((a, b) => a > b ? a : b));
    final m = monthSummary(_money, _today);
    return [
      _head(c, 'รับ - จ่าย 12 เดือน'),
      for (final (month, inc, exp) in months.reversed)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            SizedBox(width: 64, child: Text('${thaiMonthsShort[month.month - 1]} ${month.year % 100 + 43}', style: TextStyle(fontSize: 12, color: c.muted))),
            Expanded(
              child: Column(children: [
                _bar(c, inc / maxV, c.good),
                const SizedBox(height: 2),
                _bar(c, exp / maxV, c.bad),
              ]),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: Text(baht(inc - exp),
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: inc - exp >= 0 ? c.good : c.bad)),
            ),
          ]),
        ),
      _head(c, 'จ่ายไปกับอะไร (เดือนนี้)'),
      if (m.byCategory.isEmpty) _empty(c, 'ยังไม่มีรายจ่ายเดือนนี้'),
      for (final (cat, v) in m.byCategory)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(cat, style: TextStyle(color: c.text))),
            Text(baht(v), style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        ),
    ];
  }
}
