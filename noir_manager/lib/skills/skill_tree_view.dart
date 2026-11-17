/// แผนผังสกิลแบบเกม (รอบ 9B): วงกลมกระจายจากศูนย์กลาง → สาย → สกิล → ทักษะย่อย
/// คลิก = ดูรายละเอียด · คลิกขวา / กดค้าง = แก้แผนผัง · ลาก = เลื่อน · ล้อเมาส์ / หยิก = ซูม
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart';
import '../calendar/calendar_ui.dart' show categoryAccent;
import '../theme/noir_colors.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'skill_forms.dart';
import 'skill_models.dart';
import 'skill_repository.dart';
import 'skill_tree.dart';

class SkillTreeView extends StatefulWidget {
  const SkillTreeView({super.key, required this.onOpenSkill});

  /// เปิดหน้ารายละเอียดสกิล (แท็บรายการ)
  final ValueChanged<int> onOpenSkill;

  @override
  State<SkillTreeView> createState() => _SkillTreeViewState();
}

class _SkillTreeViewState extends State<SkillTreeView> {
  SkillRepository? _repo;
  List<SkillBranch> _branches = const [];
  List<Skill> _skills = const [];
  List<SkillNode> _nodes = const [];
  List<SkillTopic> _topics = const [];
  List<SkillNeed> _needs = const [];
  Map<int, SkillStat> _stats = const {};
  Map<int, SkillGoal?> _goal = const {};
  List<TreeDot> _dots = const [];
  int? _next;
  String _sel = 'root-0';
  final _tc = TransformationController();
  Size? _fitted;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = CalendarScope.of(context).skillRepo;
    if (repo != _repo) {
      _repo?.removeListener(_load);
      _repo = repo..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _repo?.removeListener(_load);
    _tc.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final repo = _repo!;
    final today = DateTime.now();
    final branches = await repo.branches();
    final skills = await repo.skills();
    final nodes = await repo.nodes();
    final needs = await repo.needs();
    final topics = await repo.topics();
    final hours = <int, double>{}, ratios = <int, double>{};
    final goal = <int, SkillGoal?>{};
    for (final s in skills) {
      final logs = await repo.logs(s.id);
      final goals = await repo.goals(s.id);
      hours[s.id] = practiceHours(logs);
      // % = หัวข้อที่ 🟢 ของบทเรียนในสกิลนี้ (รอบ 13) · ไม่มีหัวข้อ = บท / เป้า เหมือนเดิม
      ratios[s.id] = skillRatio(s,
          nodes: nodes.where((n) => n.skillId == s.id).toList(), topics: topics, goals: goals, logs: logs, today: today);
      goal[s.id] = goals.where((g) => g.status == GoalStatus.active).firstOrNull;
    }
    final stats = skillStats(skills, needs, hours, ratios);
    final total = hours.values.fold<double>(0, (a, b) => a + b);
    if (!mounted) return;
    setState(() {
      _branches = branches;
      _skills = skills;
      _nodes = nodes;
      _topics = topics;
      _needs = needs;
      _stats = stats;
      _goal = goal;
      _next = nextSkill(stats.values);
      _dots = layoutTree(
          branches: branches, skills: skills, nodes: nodes, topics: topics, stats: stats, rootLabel: 'Lv ${skillLevel(total)}');
      if (!_dots.any((d) => d.key == _sel)) _sel = 'root-0';
    });
  }

  TreeDot? get _selDot => _dots.where((d) => d.key == _sel).firstOrNull;

  // ---------------- การกระทำ ----------------

  Future<void> _addBranch() => editBranchForm(context, _repo!);

  Future<void> _addSkill([int? branchId]) async {
    final id = await editSkillForm(context, _repo!, branchId: branchId);
    if (id != null && mounted) setState(() => _sel = 'skill-$id');
  }

  Future<void> _addNode(int skillId) => editNodeForm(context, _repo!, skillId);

  void _open(int skillId) {
    final st = _stats[skillId];
    if (st != null && st.state == TreeState.lock) {
      // แอปอิสระ: แค่เตือนว่าข้ามด่าน แล้วเปิดให้เลย
      showToast(context, 'ยังไม่ผ่าน ${st.waitFor.map((s) => s.name).join(', ')} · ฝึกได้เลย แค่เตือนว่าข้ามด่าน', kind: ToastKind.warn);
    }
    widget.onOpenSkill(skillId);
  }

  Future<void> _toggleNode(SkillNode n) async {
    final mine = _nodes.where((x) => x.skillId == n.skillId).toList();
    final i = mine.indexWhere((x) => x.id == n.id);
    if (!n.done && nodeState(mine, i, topics: _topics) == TreeState.lock) {
      showToast(context, 'ข้ามด่าน: ยังไม่ผ่าน "${mine[i - 1].name}" · บันทึกให้แล้ว', kind: ToastKind.warn);
    }
    await _repo!.saveNode(n.copyWith(done: !n.done));
    if (!n.done && mine.where((x) => x.id != n.id).every((x) => x.done) && mounted) {
      showToast(context, 'ครบทุกด่านแล้ว 🎉 ไปตั้งเป้าใหม่หรือกด "จบ" ในหน้าสกิล', kind: ToastKind.success);
    }
  }

  Future<void> _moveNodeUp(SkillNode n) async {
    final mine = _nodes.where((x) => x.skillId == n.skillId).toList();
    final i = mine.indexWhere((x) => x.id == n.id);
    if (i <= 0) return;
    mine.insert(i - 1, mine.removeAt(i));
    for (final (k, x) in mine.indexed) {
      if (x.sort != k) await _repo!.saveNode(x.copyWith(sort: k));
    }
  }

  Future<void> _setNeed(Skill s) async {
    final have = _needs.where((n) => n.skillId == s.id).map((n) => n.needId).toSet();
    final others = _skills.where((x) => x.id != s.id && !have.contains(x.id)).toList();
    if (others.isEmpty) {
      showToast(context, 'ยังไม่มีสกิลอื่นให้เลือก', kind: ToastKind.info);
      return;
    }
    final need = await showMiniChoice<int>(context,
        title: '${s.name} ต้องผ่านอะไรก่อน', items: [for (final o in others) miniChoice(o.id, '${o.icon} ${o.name}')]);
    if (need == null || !mounted) return;
    if (needMakesLoop(_needs, s.id, need)) {
      final n = _skills.firstWhere((x) => x.id == need).name;
      showToast(context, 'ตั้งไม่ได้: $n ต้องผ่าน ${s.name} อยู่แล้ว (จะวนกัน)', kind: ToastKind.error);
      return;
    }
    await _repo!.addNeed(s.id, need);
  }

  Future<void> _removeNeed(Skill s) async {
    final have = [for (final n in _needs.where((n) => n.skillId == s.id)) _skills.firstWhere((x) => x.id == n.needId)];
    if (have.isEmpty) return;
    final need = await showMiniChoice<int>(context,
        title: 'เอา "ต้องผ่านก่อน" ออก', items: [for (final o in have) miniChoice(o.id, '${o.icon} ${o.name}')]);
    if (need != null) await _repo!.removeNeed(s.id, need);
  }

  Future<void> _menu(TreeDot d, Offset at) async {
    setState(() => _sel = d.key);
    final repo = _repo!;
    switch (d.kind) {
      case DotKind.root:
        final v = await showContextMenuAt<String>(context, at, [
          ctxItem('branch', Icons.account_tree_outlined, 'เพิ่มสาย'),
          ctxItem('skill', Icons.add, 'เพิ่มสกิล'),
        ]);
        if (v == 'branch') {
          await _addBranch();
        } else if (v == 'skill') {
          await _addSkill();
        }
      case DotKind.branch:
        final b = _branches.where((b) => b.id == d.id).firstOrNull;
        final v = await showContextMenuAt<String>(context, at, [
          ctxItem('skill', Icons.add, 'เพิ่มสกิลในสายนี้'),
          if (b != null) ctxItem('edit', Icons.edit_outlined, 'แก้สาย'),
          if (b != null) ctxItem('delete', Icons.delete_outline, 'ลบสาย', danger: true),
        ]);
        if (!mounted) return;
        switch (v) {
          case 'skill':
            await _addSkill(b?.id);
          case 'edit':
            await editBranchForm(context, repo, branch: b);
          case 'delete':
            final ok = await confirmMini(context,
                title: 'ลบสาย', message: 'ลบสาย "${b!.name}"? สกิลในสายไม่หาย (ย้ายไป "ยังไม่จัดสาย")', okLabel: 'ลบ', danger: true);
            if (ok) await repo.deleteBranch(b.id);
        }
      case DotKind.skill:
        final s = _skills.firstWhere((s) => s.id == d.id);
        final hasNeed = _needs.any((n) => n.skillId == s.id);
        final v = await showContextMenuAt<String>(context, at, [
          ctxItem('open', Icons.open_in_new, 'เปิดสกิล'),
          ctxItem('node', Icons.add, 'เพิ่มทักษะย่อย'),
          ctxItem('need', Icons.link, 'ตั้ง "ต้องผ่านก่อน"…'),
          if (hasNeed) ctxItem('unneed', Icons.link_off, 'เอา "ต้องผ่านก่อน" ออก…'),
          ctxItem('edit', Icons.edit_outlined, 'แก้สกิล / ย้ายสาย'),
          ctxItem('delete', Icons.delete_outline, 'ลบสกิล', danger: true),
        ]);
        if (!mounted) return;
        switch (v) {
          case 'open':
            _open(s.id);
          case 'node':
            await _addNode(s.id);
          case 'need':
            await _setNeed(s);
          case 'unneed':
            await _removeNeed(s);
          case 'edit':
            await editSkillForm(context, repo, skill: s);
          case 'delete':
            if (await confirmDelete(context, s.name)) await repo.deleteSkill(s.id);
        }
      case DotKind.node:
        final n = _nodes.firstWhere((n) => n.id == d.id);
        final first = _nodes.firstWhere((x) => x.skillId == n.skillId).id == n.id;
        final v = await showContextMenuAt<String>(context, at, [
          ctxItem('toggle', n.done ? Icons.undo : Icons.check, n.done ? 'ยังไม่ผ่าน' : 'ผ่านแล้ว'),
          ctxItem('edit', Icons.edit_outlined, 'แก้ชื่อ'),
          if (!first) ctxItem('up', Icons.arrow_upward, 'เลื่อนขึ้น (ทำก่อน)'),
          ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
        ]);
        if (!mounted) return;
        switch (v) {
          case 'toggle':
            await _toggleNode(n);
          case 'edit':
            await editNodeForm(context, repo, n.skillId, node: n);
          case 'up':
            await _moveNodeUp(n);
          case 'delete':
            await repo.deleteNode(n.id);
        }
    }
  }

  // ---------------- หน้าตา ----------------

  void _fit(Size box) {
    if (_fitted == box) return;
    _fitted = box;
    final s = math.min(1.0, math.min(box.width / treeCanvas.w, box.height / treeCanvas.h));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tc.value = Matrix4.diagonal3Values(s, s, 1)
        ..setTranslationRaw((box.width - treeCanvas.w * s) / 2, (box.height - treeCanvas.h * s) / 2, 0);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (_skills.isEmpty && _branches.isEmpty) return _empty(c);
    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 760;
      final treeH = wide ? box.maxHeight - 40 : math.max(220.0, box.maxHeight - 250);
      final tree = LayoutBuilder(builder: (context, b) {
        _fit(b.biggest);
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(colors: [c.surface2, c.bg]),
              border: Border.all(color: c.line),
              borderRadius: BorderRadius.circular(14),
            ),
            child: InteractiveViewer(
              transformationController: _tc,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(400),
              minScale: 0.25,
              maxScale: 2.5,
              child: SizedBox(width: treeCanvas.w, height: treeCanvas.h, child: _canvas(c)),
            ),
          ),
        );
      });
      final legend = _legend(c);
      if (wide) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
          child: Column(children: [
            Expanded(
              child: Stack(children: [
                Positioned.fill(child: tree),
                Positioned(top: 12, right: 12, width: 290, child: _panel(c)),
              ]),
            ),
            const SizedBox(height: 8),
            legend,
          ]),
        );
      }
      return ListView(padding: const EdgeInsets.fromLTRB(16, 4, 16, 16), children: [
        SizedBox(height: treeH, child: tree),
        const SizedBox(height: 8),
        _panel(c),
        const SizedBox(height: 8),
        legend,
      ]);
    });
  }

  Widget _empty(NoirColors c) => Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('🌟', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 8),
            Text('แผนผังสกิล: สาย → สกิล → ทักษะย่อย', style: TextStyle(color: c.text)),
            Text('เริ่มจากสาย เช่น ตัดต่อ · ภาษา · ศิลปะ แล้วเพิ่มสกิลเข้าไป',
                textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
              FilledButton.icon(
                  key: const Key('tree-add-branch'), onPressed: _addBranch, icon: const Icon(Icons.account_tree_outlined), label: const Text('เพิ่มสาย')),
              OutlinedButton.icon(
                  key: const Key('tree-add-skill'), onPressed: () => _addSkill(), icon: const Icon(Icons.add), label: const Text('เพิ่มสกิล')),
            ]),
          ]),
        ),
      );

  Widget _canvas(NoirColors c) {
    final byId = {for (final d in _dots.where((d) => d.kind == DotKind.skill)) d.id: d};
    final needLines = [
      for (final n in _needs)
        if (byId[n.needId] != null && byId[n.skillId] != null) (byId[n.needId]!.pos, byId[n.skillId]!.pos)
    ];
    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(child: CustomPaint(painter: _Lines(_dots, needLines, c))),
      for (final d in _dots) ..._dot(d, c),
    ]);
  }

  List<Widget> _dot(TreeDot d, NoirColors c) {
    final col = d.kind == DotKind.root ? c.accent : categoryAccent(d.colorKey);
    final sel = d.key == _sel;
    final lock = d.state == TreeState.lock;
    final done = d.state == TreeState.done && (d.kind == DotKind.skill || d.kind == DotKind.node);
    final r = d.radius;
    final (fill, border, bw) = switch (d.kind) {
      DotKind.root => (c.surface2, c.accent, 3.0),
      DotKind.branch => (col.withValues(alpha: 0.18), col, 2.5),
      _ when done => (col.withValues(alpha: 0.9), col, 2.0),
      _ => (c.surface2, lock ? c.line : c.muted.withValues(alpha: 0.6), 2.0),
    };
    final center = switch (d.kind) {
      DotKind.node => done
          ? const Icon(Icons.check, size: 16, color: Colors.white)
          : lock
              ? const Text('🔒', style: TextStyle(fontSize: 11))
              : null,
      _ => Text(d.icon, style: TextStyle(fontSize: d.kind == DotKind.root ? 24 : r * 0.72)),
    };
    final st = d.kind == DotKind.skill ? _stats[d.id] : null;
    final sub = switch (d.kind) {
      DotKind.skill when st != null => 'Lv ${st.level}${st.state == TreeState.prog ? ' · ${(st.ratio * 100).round()}%' : ''}',
      _ => null,
    };
    void tap() => setState(() => _sel = d.key);
    return [
      Positioned(
        left: d.pos.dx - r - 8,
        top: d.pos.dy - r - 8,
        width: r * 2 + 16,
        height: r * 2 + 16,
        child: GestureDetector(
          key: ValueKey('tree-${d.key}'),
          behavior: HitTestBehavior.opaque,
          onTap: tap,
          onSecondaryTapUp: (e) => _menu(d, e.globalPosition),
          onLongPressStart: (e) => _menu(d, e.globalPosition),
          child: Stack(alignment: Alignment.center, children: [
            if (sel || (d.kind == DotKind.skill && d.id == _next))
              Container(
                width: r * 2 + 14,
                height: r * 2 + 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: sel ? c.text.withValues(alpha: 0.6) : c.accent.withValues(alpha: 0.45), width: 2),
                ),
              ),
            Container(
              width: r * 2,
              height: r * 2,
              alignment: Alignment.center,
              decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: Border.all(color: border, width: bw)),
              child: center,
            ),
            if (d.kind == DotKind.skill && d.state == TreeState.prog)
              SizedBox(
                width: r * 2 - 2,
                height: r * 2 - 2,
                child: CircularProgressIndicator(value: d.ratio.clamp(0.0, 1.0), strokeWidth: 4, color: col, backgroundColor: Colors.transparent),
              ),
            if (d.kind == DotKind.skill && lock) const Positioned(top: 0, right: 2, child: Text('🔒', style: TextStyle(fontSize: 12))),
          ]),
        ),
      ),
      Positioned(
        left: d.pos.dx - 70,
        top: d.pos.dy + r + (d.kind == DotKind.root ? -r * 2 - 22 : 4),
        width: 140,
        child: IgnorePointer(
          child: Column(children: [
            Text(
              d.kind == DotKind.root ? 'สกิล · ${d.label}' : d.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: d.kind == DotKind.node ? 11 : 12.5,
                fontWeight: d.kind == DotKind.root || d.kind == DotKind.branch ? FontWeight.w600 : FontWeight.w400,
                color: lock ? c.muted : c.text,
              ),
            ),
            if (sub != null) Text(sub, style: TextStyle(fontSize: 10.5, color: c.muted)),
          ]),
        ),
      ),
    ];
  }

  Widget _legend(NoirColors c) {
    Widget item(Widget dot, String t) => Row(mainAxisSize: MainAxisSize.min, children: [dot, const SizedBox(width: 6), Text(t)]);
    Widget circle(Color fill, Color border) => Container(
        width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: fill, border: Border.all(color: border, width: 2)));
    return DefaultTextStyle(
      style: TextStyle(fontSize: 12, color: c.muted),
      child: Wrap(spacing: 14, runSpacing: 4, children: [
        item(circle(c.good, c.good), 'ถึงเป้า'),
        item(circle(c.surface2, c.accent), 'กำลังฝึก (วง = %)'),
        item(circle(c.surface2, c.muted), 'ยังไม่เริ่ม'),
        item(const Text('🔒'), 'ต้องผ่านอันก่อน (แค่เตือน)'),
        item(Container(width: 16, height: 2, color: c.warn), 'ต้องผ่านก่อน (ข้ามสาย)'),
        const Text('คลิกขวา / กดค้าง = แก้แผนผัง'),
      ]),
    );
  }

  String _h(double h) => h == h.roundToDouble() ? h.toInt().toString() : h.toStringAsFixed(1);

  Widget _panel(NoirColors c) {
    final d = _selDot;
    final small = TextStyle(fontSize: 12, color: c.muted);
    // ป้ายยาว (ต้องผ่าน ... ก่อน) หดได้ ไม่ดันแผงล้น
    Widget tag(String t, Color col) => Flexible(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(color: col.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(99)),
            child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11, color: col)),
          ),
        );
    Widget btn(String key, String label, VoidCallback on, {bool filled = false}) => filled
        ? FilledButton(key: Key(key), onPressed: on, style: FilledButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(label))
        : OutlinedButton(key: Key(key), onPressed: on, style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact), child: Text(label));
    Widget more(TreeDot d) => Builder(
          builder: (bc) => IconButton(
            key: const Key('tree-more'),
            tooltip: 'แก้แผนผัง',
            visualDensity: VisualDensity.compact,
            onPressed: () {
              final box = bc.findRenderObject() as RenderBox;
              _menu(d, box.localToGlobal(box.size.center(Offset.zero)));
            },
            icon: const Icon(Icons.more_horiz),
          ),
        );
    final children = <Widget>[];
    if (d == null || d.kind == DotKind.root) {
      final total = _stats.values.fold<double>(0, (a, s) => a + s.hours);
      final next = _skills.where((s) => s.id == _next).firstOrNull;
      children.addAll([
        Row(children: [
          Expanded(child: Text('สกิลทั้งหมด', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
          if (d != null) more(d),
        ]),
        Text('${_branches.length} สาย · ${_skills.length} สกิล · ฝึกรวม ${_h(total)} ชม. · Lv ${skillLevel(total)}', style: small),
        if (next != null) ...[
          const SizedBox(height: 6),
          Text('🧭 ฝึกต่อ: ${next.icon} ${next.name} (ใกล้เป้าที่สุด)', key: const Key('tree-next'), style: TextStyle(fontSize: 12.5, color: c.text)),
        ],
        const SizedBox(height: 6),
        Text('คลิกวงกลม = ดู · คลิกขวา / กดค้าง = แก้ · ลาก = เลื่อน · ล้อเมาส์ = ซูม', style: small),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          btn('tree-add-branch', '＋ สาย', _addBranch),
          btn('tree-add-skill', '＋ สกิล', () => _addSkill()),
        ]),
      ]);
    } else if (d.kind == DotKind.branch) {
      final list = _skills.where((s) => d.id < 0 ? !_branches.any((b) => b.id == s.branchId) : s.branchId == d.id).toList();
      final done = list.where((s) => _stats[s.id]?.passed ?? false).length;
      children.addAll([
        Row(children: [
          Expanded(child: Text('${d.icon} สาย${d.label}', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
          more(d),
        ]),
        Text('${list.length} สกิล · ถึงเป้า $done', style: small),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in list)
            ActionChip(label: Text('${s.icon} ${s.name}', overflow: TextOverflow.ellipsis), onPressed: () => setState(() => _sel = 'skill-${s.id}')),
        ]),
        const SizedBox(height: 8),
        btn('tree-add-skill', '＋ สกิลในสายนี้', () => _addSkill(d.id < 0 ? null : d.id)),
      ]);
    } else if (d.kind == DotKind.skill) {
      final st = _stats[d.id]!;
      final s = st.skill;
      final col = categoryAccent(d.colorKey);
      final mine = _nodes.where((n) => n.skillId == s.id).toList();
      final g = _goal[s.id];
      final needNames = [for (final n in _needs.where((n) => n.skillId == s.id)) _skills.firstWhere((x) => x.id == n.needId).name];
      children.addAll([
        Row(children: [
          Expanded(child: Text('${s.icon} ${s.name}', style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
          switch (st.state) {
            TreeState.done => tag('ถึงเป้า', c.good),
            TreeState.prog => tag('กำลังฝึก', c.accent),
            TreeState.open => tag('ยังไม่เริ่ม', c.muted),
            TreeState.lock => tag('🔒 ต้องผ่าน ${st.waitFor.map((x) => x.name).join(', ')} ก่อน', c.warn),
          },
          more(d),
        ]),
        Text('Lv ${st.level} · ฝึก ${_h(st.hours)} ชม.${s.status == SkillStatus.paused ? ' · พักไว้' : ''}', style: small),
        const SizedBox(height: 6),
        Text(s.status == SkillStatus.done ? 'จบแล้ว' : (g?.title ?? 'ยังไม่มีเป้า'), style: TextStyle(fontSize: 12.5, color: c.text)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: st.ratio.clamp(0.0, 1.0), minHeight: 6, backgroundColor: c.surface2, color: col),
        ),
        const SizedBox(height: 6),
        Text(
          mine.isEmpty
              ? 'ยังไม่มีทักษะย่อย'
              : 'ทักษะย่อย: ${[
                  for (final (i, n) in mine.indexed) '${nodePassed(n, _topics) ? '✓ ' : nodeState(mine, i, topics: _topics) == TreeState.lock ? '🔒 ' : ''}${n.name}'
                ].join(' → ')}',
          style: small,
        ),
        if (needNames.isNotEmpty) Text('ต้องผ่านก่อน: ${needNames.join(', ')}', style: small),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          btn('tree-open-skill', 'เปิดสกิล', () => _open(s.id), filled: true),
          btn('tree-add-node', '＋ ทักษะย่อย', () => _addNode(s.id)),
        ]),
      ]);
    } else {
      final n = _nodes.firstWhere((n) => n.id == d.id);
      final skill = _skills.firstWhere((s) => s.id == n.skillId);
      children.addAll([
        Row(children: [
          Expanded(child: Text(n.name, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
          switch (d.state) {
            TreeState.done => tag('ผ่านแล้ว', c.good),
            TreeState.lock => tag('🔒 ผ่านอันก่อนก่อน', c.warn),
            _ => tag('ด่านถัดไป', c.accent),
          },
          more(d),
        ]),
        Text('ทักษะย่อยของ ${skill.name}', style: small),
        if (d.state == TreeState.lock) Text('กดผ่านได้เลย (แอปแค่เตือนว่าข้ามด่าน)', style: small),
        const SizedBox(height: 8),
        btn('tree-node-toggle', n.done ? 'ยังไม่ผ่าน' : 'ผ่านด่านนี้แล้ว', () => _toggleNode(n), filled: !n.done),
      ]);
    }
    return Container(
      key: const Key('tree-panel'),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.97),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// เส้นแม่ → ลูก (โค้งเข้าหาศูนย์กลางเล็กน้อย) + เส้นประ "ต้องผ่านก่อน" สีส้ม
class _Lines extends CustomPainter {
  _Lines(this.dots, this.needs, this.c);
  final List<TreeDot> dots;
  final List<(Offset, Offset)> needs;
  final NoirColors c;

  static void _dashed(Canvas canvas, Path path, Paint paint, double on, double off) {
    for (final m in path.computeMetrics()) {
      var d = 0.0;
      while (d < m.length) {
        canvas.drawPath(m.extractPath(d, math.min(d + on, m.length)), paint);
        d += on + off;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (final d in dots) {
      final p = d.parent;
      if (p == null) continue;
      final mid = (d.pos + p.pos) / 2;
      final ctrl = center + (mid - center) * 0.92;
      final path = Path()
        ..moveTo(p.pos.dx, p.pos.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, d.pos.dx, d.pos.dy);
      final lock = d.state == TreeState.lock;
      final col = categoryAccent(d.colorKey);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = d.kind == DotKind.branch ? 3 : 2
        ..color = lock ? c.line : col.withValues(alpha: 0.55);
      if (lock) {
        _dashed(canvas, path, paint, 4, 5);
      } else {
        canvas.drawPath(path, paint);
      }
    }
    final need = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = c.warn.withValues(alpha: 0.85);
    for (final (a, b) in needs) {
      final path = Path()
        ..moveTo(a.dx, a.dy)
        ..quadraticBezierTo(center.dx, center.dy, b.dx, b.dy);
      _dashed(canvas, path, need, 4, 5);
    }
  }

  @override
  bool shouldRepaint(_Lines old) => old.dots != dots || old.needs != needs || old.c != c;
}
