/// แผนผังสกิล (รอบ 9B): คิดสถานะ · Lv · ตำแหน่งวงกลม (ไม่มี UI · เทสได้ตรง ๆ)
/// ชั้น: ศูนย์กลาง → สาย → สกิล → ทักษะย่อย · "ล็อก" แค่เตือน ไม่บล็อก
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'skill_models.dart';
import 'skill_progress.dart';

/// done = ถึงเป้า · prog = กำลังฝึก · open = ปลดล็อกแล้ว ยังไม่เริ่ม · lock = ต้องผ่านอันก่อนหน้า
enum TreeState { done, prog, open, lock }

/// Lv ขึ้นทุก 10 ชม. ที่ฝึก (เริ่ม Lv 1)
int skillLevel(double hours) => 1 + (hours / 10).floor();

/// ชั่วโมงฝึกจากบันทึก (ไม่นับรอบที่ข้าม)
double practiceHours(List<SkillLog> logs) =>
    logs.where((l) => !l.skipped).fold<int>(0, (s, l) => s + (l.minutes ?? 0)) / 60;

/// ความคืบหน้า 0–1: จบแล้ว = 1 · มีทักษะย่อย = สัดส่วนที่ผ่าน · ไม่มี = เฉลี่ยเป้าที่ยังเปิด
double skillRatio(Skill s, {List<SkillNode> nodes = const [], List<SkillGoal> goals = const [], List<SkillLog> logs = const [], required DateTime today}) {
  if (s.status == SkillStatus.done) return 1;
  if (nodes.isNotEmpty) return nodes.where((n) => n.done).length / nodes.length;
  final open = goals.where((g) => g.status != GoalStatus.closed).toList();
  if (open.isEmpty) return 0;
  var sum = 0.0;
  for (final g in open) {
    if (g.status == GoalStatus.met) {
      sum += 1;
      continue;
    }
    final p = goalProgress(g, logs, today: today);
    sum += p.met ? 1 : (p.ratio ?? (g.streak > 0 ? p.run / g.streak : 0)).clamp(0.0, 1.0);
  }
  return sum / open.length;
}

/// ข้อมูลของ 1 สกิลที่แผนผังต้องใช้
class SkillStat {
  const SkillStat({required this.skill, required this.hours, required this.ratio, required this.state, this.waitFor = const []});
  final Skill skill;
  final double hours;
  final double ratio;
  final TreeState state;

  /// สกิลที่ "ต้องผ่านก่อน" แต่ยังไม่ผ่าน
  final List<Skill> waitFor;

  int get level => skillLevel(hours);
  bool get passed => state == TreeState.done;
}

/// สถานะทุกสกิล · [hours] / [ratios] ตาม id สกิล
Map<int, SkillStat> skillStats(List<Skill> skills, List<SkillNeed> needs, Map<int, double> hours, Map<int, double> ratios) {
  final byId = {for (final s in skills) s.id: s};
  bool passed(Skill s) => s.status == SkillStatus.done || (ratios[s.id] ?? 0) >= 1;
  return {
    for (final s in skills)
      s.id: () {
        final h = hours[s.id] ?? 0, r = ratios[s.id] ?? 0;
        final wait = [
          for (final n in needs)
            if (n.skillId == s.id && byId[n.needId] != null && !passed(byId[n.needId]!)) byId[n.needId]!
        ];
        final state = passed(s)
            ? TreeState.done
            : wait.isNotEmpty
                ? TreeState.lock
                : (h == 0 && r == 0 ? TreeState.open : TreeState.prog);
        return SkillStat(skill: s, hours: h, ratio: r, state: state, waitFor: wait);
      }(),
  };
}

/// สถานะทักษะย่อย: ผ่านแล้ว · ล็อก (อันก่อนหน้ายังไม่ผ่าน) · เปิดอยู่
TreeState nodeState(List<SkillNode> ordered, int index) {
  if (ordered[index].done) return TreeState.done;
  if (index > 0 && !ordered[index - 1].done) return TreeState.lock;
  return TreeState.open;
}

/// ตั้ง "[skillId] ต้องผ่าน [needId] ก่อน" แล้วจะวนกันไหม (A ต้องผ่าน B · B ต้องผ่าน A)
bool needMakesLoop(List<SkillNeed> needs, int skillId, int needId) {
  if (skillId == needId) return true;
  final seen = <int>{};
  final stack = [needId];
  while (stack.isNotEmpty) {
    final cur = stack.removeLast();
    if (cur == skillId) return true;
    if (!seen.add(cur)) continue;
    for (final n in needs) {
      if (n.skillId == cur) stack.add(n.needId);
    }
  }
  return false;
}

/// สกิลที่ควรฝึกต่อ: กำลังฝึกและใกล้เป้าที่สุด
int? nextSkill(Iterable<SkillStat> stats) {
  final prog = stats.where((s) => s.state == TreeState.prog && s.skill.status == SkillStatus.active).toList()
    ..sort((a, b) => b.ratio.compareTo(a.ratio));
  return prog.firstOrNull?.skill.id;
}

// ---------------- ตำแหน่ง ----------------

enum DotKind { root, branch, skill, node }

/// 1 วงกลมในแผนผัง
class TreeDot {
  TreeDot({
    required this.kind,
    required this.id,
    required this.label,
    this.icon = '',
    required this.colorKey,
    required this.pos,
    required this.radius,
    this.parent,
    this.state = TreeState.open,
    this.ratio = 0,
  });
  final DotKind kind;

  /// root = 0 · สาย "ยังไม่จัดสาย" = -1
  final int id;
  final String label;
  final String icon;
  final String colorKey;
  final Offset pos;
  final double radius;
  final TreeDot? parent;
  final TreeState state;
  final double ratio;

  String get key => '${kind.name}-$id';
}

/// ขนาดพื้นที่วาด (จุดศูนย์กลางอยู่กลาง)
const treeCanvas = (w: 1100.0, h: 820.0);

/// สาย "ยังไม่จัดสาย" สำหรับสกิลที่ไม่มีสาย
const unsortedBranch = SkillBranch(id: -1, name: 'ยังไม่จัดสาย', icon: '📦', colorKey: 'gray');

/// วางวงกลมเป็นวง: สายกระจายรอบศูนย์กลาง · พื้นที่ของแต่ละสายตามจำนวนสกิล (สายใหญ่ไม่เบียด)
List<TreeDot> layoutTree({
  required List<SkillBranch> branches,
  required List<Skill> skills,
  required List<SkillNode> nodes,
  required Map<int, SkillStat> stats,
  required String rootLabel,
}) {
  final c = Offset(treeCanvas.w / 2, treeCanvas.h / 2);
  // วงรีเล็กน้อย เพราะจอคอมกว้างกว่าสูง
  Offset at(double r, double a) => c + Offset(math.cos(a) * r * 1.18, math.sin(a) * r * 0.9);
  final root = TreeDot(kind: DotKind.root, id: 0, label: rootLabel, icon: '🌟', colorKey: 'sky', pos: c, radius: 46);
  final dots = <TreeDot>[root];
  final groups = [
    for (final b in branches) (b, skills.where((s) => s.branchId == b.id).toList()),
    if (skills.any((s) => s.branchId == null || !branches.any((b) => b.id == s.branchId)))
      (unsortedBranch, skills.where((s) => s.branchId == null || !branches.any((b) => b.id == s.branchId)).toList()),
  ];
  if (groups.isEmpty) return dots;
  final weight = [for (final (_, list) in groups) math.max(1, list.length)];
  final total = weight.fold<int>(0, (a, b) => a + b);
  var start = -math.pi / 2 - (2 * math.pi * weight.first / total) / 2;
  for (final (gi, (b, list)) in groups.indexed) {
    final span = 2 * math.pi * weight[gi] / total;
    final mid = start + span / 2;
    final bd = TreeDot(
        kind: DotKind.branch, id: b.id, label: b.name, icon: b.icon, colorKey: b.colorKey, pos: at(150, mid), radius: 34, parent: root);
    dots.add(bd);
    for (final (j, s) in list.indexed) {
      final slot = span / list.length;
      final a = start + slot * (j + 0.5);
      final st = stats[s.id];
      final sd = TreeDot(
        kind: DotKind.skill,
        id: s.id,
        label: s.name,
        icon: s.icon,
        colorKey: b.colorKey,
        pos: at(285, a),
        radius: 28,
        parent: bd,
        state: st?.state ?? TreeState.open,
        ratio: st?.ratio ?? 0,
      );
      dots.add(sd);
      final mine = nodes.where((n) => n.skillId == s.id).toList();
      // ทักษะย่อยต้องอยู่ในช่องของสกิลตัวเอง (ไม่ไปทับสกิลข้าง ๆ)
      final step = mine.length <= 1 ? 0.0 : math.min(0.2, slot * 0.85 / (mine.length - 1));
      for (final (m, n) in mine.indexed) {
        final aa = a + (m - (mine.length - 1) / 2) * step;
        dots.add(TreeDot(
          kind: DotKind.node,
          id: n.id,
          label: n.name,
          colorKey: b.colorKey,
          pos: at(m.isEven ? 405 : 455, aa), // สลับระยะ ชื่อไม่ชนกัน
          radius: 17,
          parent: sd,
          state: nodeState(mine, m),
          ratio: n.done ? 1 : 0,
        ));
      }
    }
    start += span;
  }
  return dots;
}
