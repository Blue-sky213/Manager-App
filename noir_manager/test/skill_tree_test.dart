// รอบ 9B: แผนผังสกิล · สาย → สกิล → ทักษะย่อย · ต้องผ่านก่อน (แค่เตือน) · Lv
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/skills/skill_models.dart';
import 'package:noir_manager/skills/skill_repository.dart';
import 'package:noir_manager/skills/skill_tree.dart';
import 'package:noir_manager/skills/sqlite_skill_repository.dart';

final today = DateTime(2026, 11, 16);

Skill sk(int id, String name, {int? branch, SkillStatus status = SkillStatus.active}) =>
    Skill(id: id, name: name, branchId: branch, status: status, startedAt: DateTime(2026, 9, 1));

/// สาย / ทักษะย่อย / ต้องผ่านก่อน · เหมือนกันทั้ง RAM และ SQLite
Future<void> treeRepoRules(SkillRepository repo) async {
  final b = await repo.saveBranch(const SkillBranch(name: 'ตัดต่อ', icon: '🎬', colorKey: 'purple'));
  await repo.saveBranch(SkillBranch(id: b, name: 'ตัดต่อวิดีโอ', icon: '🎬', colorKey: 'pink'));
  expect((await repo.branches()).single.name, 'ตัดต่อวิดีโอ');
  final dv = await repo.saveSkill(Skill(name: 'DaVinci', branchId: b, startedAt: DateTime(2026, 9, 1)));
  final ps = await repo.saveSkill(Skill(name: 'Photoshop', startedAt: DateTime(2026, 9, 1)));
  final th = await repo.saveSkill(Skill(name: 'Thumbnail', branchId: b, startedAt: DateTime(2026, 9, 1)));
  expect((await repo.skills()).firstWhere((s) => s.id == dv).branchId, b);
  expect((await repo.skills()).firstWhere((s) => s.id == ps).branchId, isNull);

  final cut = await repo.saveNode(SkillNode(skillId: dv, name: 'Cut'));
  await repo.saveNode(SkillNode(skillId: dv, name: 'Color', sort: 1));
  await repo.saveNode(SkillNode(skillId: th, name: 'Layout'));
  final n = (await repo.nodes()).firstWhere((n) => n.id == cut);
  await repo.saveNode(n.copyWith(done: true));
  expect([for (final n in await repo.nodes()) if (n.skillId == dv) (n.name, n.done)], [('Cut', true), ('Color', false)]);

  await repo.addNeed(th, ps);
  await repo.addNeed(th, ps); // ซ้ำ = ไม่เพิ่ม
  await repo.addNeed(th, dv);
  expect((await repo.needs()).length, 2);
  await repo.removeNeed(th, dv);
  expect([for (final x in await repo.needs()) (x.skillId, x.needId)], [(th, ps)]);

  // ลบสาย → สกิลยังอยู่ (ยังไม่จัดสาย)
  await repo.deleteBranch(b);
  expect(await repo.branches(), isEmpty);
  expect((await repo.skills()).length, 3);
  expect((await repo.skills()).every((s) => s.branchId == null), isTrue);

  // ลบสกิล → ทักษะย่อย + เส้นต้องผ่านก่อน (ทั้งสองทาง) หาย
  await repo.deleteSkill(ps);
  expect(await repo.needs(), isEmpty);
  await repo.deleteSkill(dv);
  expect([for (final n in await repo.nodes()) n.name], ['Layout']);
}

void main() {
  group('คิดแผนผัง', () {
    test('Lv ขึ้นทุก 10 ชม. · ชั่วโมงไม่นับรอบที่ข้าม', () {
      expect(skillLevel(0), 1);
      expect(skillLevel(9.9), 1);
      expect(skillLevel(10), 2);
      expect(skillLevel(55), 6);
      final logs = [
        SkillLog(skillId: 1, day: today, minutes: 90),
        SkillLog(skillId: 1, day: today, minutes: 30),
        SkillLog(skillId: 1, day: today, minutes: 600, skipped: true),
      ];
      expect(practiceHours(logs), 2);
    });

    test('ความคืบหน้า: จบแล้ว = 100% · มีทักษะย่อย = สัดส่วนที่ผ่าน · ไม่มีอะไร = 0', () {
      expect(skillRatio(sk(1, 'A', status: SkillStatus.done), today: today), 1);
      final nodes = [
        const SkillNode(skillId: 1, name: 'Cut', done: true),
        const SkillNode(skillId: 1, name: 'Color'),
        const SkillNode(skillId: 1, name: 'Fairlight'),
        const SkillNode(skillId: 1, name: 'Fusion'),
      ];
      expect(skillRatio(sk(1, 'A'), nodes: nodes, today: today), 0.25);
      expect(skillRatio(sk(1, 'A'), today: today), 0);
      const milestone = SkillGoal(
          id: 5, skillId: 1, kind: GoalKind.milestone, title: 'ด่าน', steps: [GoalStep('a', done: true), GoalStep('b')]);
      expect(skillRatio(sk(1, 'A'), goals: const [milestone], today: today), 0.5);
    });

    test('สถานะ: ล็อกจนกว่าสกิลที่ต้องผ่านก่อนจะถึงเป้า · ไม่มีชั่วโมง = ยังไม่เริ่ม', () {
      final skills = [sk(1, 'Photoshop'), sk(2, 'Thumbnail'), sk(3, 'OBS'), sk(4, 'Premiere', status: SkillStatus.done)];
      const needs = [SkillNeed(2, 1), SkillNeed(3, 4)];
      var st = skillStats(skills, needs, {1: 6, 3: 4}, {1: 0.55, 3: 0.7});
      expect(st[1]!.state, TreeState.prog);
      expect(st[2]!.state, TreeState.lock);
      expect(st[2]!.waitFor.map((s) => s.name), ['Photoshop']);
      expect(st[3]!.state, TreeState.prog); // Premiere จบแล้ว → ปลดล็อก
      expect(st[4]!.state, TreeState.done);
      st = skillStats(skills, needs, {1: 6}, {1: 1.0});
      expect(st[1]!.state, TreeState.done);
      expect(st[2]!.state, TreeState.open); // ปลดล็อกแล้ว ยังไม่เริ่ม
      expect(nextSkill(skillStats(skills, needs, {1: 6, 3: 4}, {1: 0.55, 3: 0.7}).values), 3); // ใกล้เป้าที่สุด
    });

    test('ทักษะย่อย: ด่านถัดไปเปิด · ด่านหลังจากนั้นล็อก', () {
      const ns = [
        SkillNode(skillId: 1, name: 'Cut', done: true),
        SkillNode(skillId: 1, name: 'Color'),
        SkillNode(skillId: 1, name: 'Fusion'),
      ];
      expect([for (var i = 0; i < 3; i++) nodeState(ns, i)], [TreeState.done, TreeState.open, TreeState.lock]);
    });

    test('ต้องผ่านก่อนห้ามวน (A→B→C→A) · ห้ามตัวเอง', () {
      const needs = [SkillNeed(2, 1), SkillNeed(3, 2)]; // 2 ต้องผ่าน 1 · 3 ต้องผ่าน 2
      expect(needMakesLoop(needs, 1, 3), isTrue);
      expect(needMakesLoop(needs, 1, 2), isTrue);
      expect(needMakesLoop(needs, 1, 1), isTrue);
      expect(needMakesLoop(needs, 3, 1), isFalse); // ทางลัด ไม่วน
      expect(needMakesLoop(needs, 4, 3), isFalse);
    });

    test('วางตำแหน่ง: วงกลมไม่ทับกัน · สกิลไม่มีสายไปอยู่ "ยังไม่จัดสาย" · อยู่ในพื้นที่วาด', () {
      const branches = [
        SkillBranch(id: 10, name: 'ตัดต่อ', colorKey: 'purple'),
        SkillBranch(id: 11, name: 'ภาษา', colorKey: 'sky'),
        SkillBranch(id: 12, name: 'ศิลปะ', colorKey: 'pink'),
        SkillBranch(id: 13, name: 'สตรีม', colorKey: 'mint'),
        SkillBranch(id: 14, name: 'ว่าง', colorKey: 'gray'),
      ];
      final skills = [
        sk(1, 'DaVinci', branch: 10),
        sk(2, 'Premiere', branch: 10),
        sk(3, 'English', branch: 11),
        sk(4, 'Drawing', branch: 12),
        sk(5, 'Photoshop', branch: 12),
        sk(6, 'Thumbnail', branch: 13),
        sk(7, 'OBS', branch: 13),
        sk(8, 'Excel'),
      ];
      var id = 100;
      final nodes = [
        for (final (s, n) in [(1, 6), (3, 3), (4, 2), (8, 4)])
          for (var i = 0; i < n; i++) SkillNode(id: id++, skillId: s, name: 'n$i', sort: i),
      ];
      final dots = layoutTree(
          branches: branches, skills: skills, nodes: nodes, stats: skillStats(skills, const [], const {}, const {}), rootLabel: 'Lv 1');
      expect(dots.where((d) => d.kind == DotKind.branch).map((d) => d.label), [...branches.map((b) => b.name), 'ยังไม่จัดสาย']);
      expect(dots.where((d) => d.kind == DotKind.skill).length, 8);
      expect(dots.where((d) => d.kind == DotKind.node).length, 15);
      for (final (i, a) in dots.indexed) {
        expect(a.pos.dx - a.radius >= 0 && a.pos.dx + a.radius <= treeCanvas.w, isTrue, reason: a.label);
        expect(a.pos.dy - a.radius >= 0 && a.pos.dy + a.radius <= treeCanvas.h, isTrue, reason: a.label);
        for (final b in dots.skip(i + 1)) {
          expect((a.pos - b.pos).distance > a.radius + b.radius, isTrue, reason: '${a.key} ทับ ${b.key}');
        }
      }
    });
  });

  test('RAM: สาย · ทักษะย่อย · ต้องผ่านก่อน', () => treeRepoRules(MemorySkillRepository()));

  test('SQLite v22: สาย · ทักษะย่อย · ต้องผ่านก่อน · อัปเกรดจาก v19 ไม่แตะข้อมูลเดิม · รันซ้ำได้', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createSkillV19(db);
    await db.insert('skill', {'name': 'สกิลเดิม', 'status': 'active', 'started_at': '2026-10-01'});
    await createSkillTreeV22(db);
    await createSkillTreeV22(db);
    final repo = SqliteSkillRepository(db);
    final old = (await repo.skills()).single;
    expect((old.name, old.branchId), ('สกิลเดิม', null));
    await repo.deleteSkill(old.id);
    await treeRepoRules(repo);
    await db.close();
  });

  testWidgets('สกิล › แผนผัง: สร้างสาย → สกิล → ทักษะย่อย · ข้ามด่าน = เตือน · ต้องผ่านก่อน + กันวน · เปิดสกิลจากแผนผัง',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    final repo = cal.skillRepo;
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สกิล').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('tab-แผนผัง')), findsOneWidget);

    // สาย
    await tester.tap(find.byKey(const Key('tree-add-branch')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('branch-name')), 'ตัดต่อ');
    await tester.tap(find.widgetWithText(FilledButton, 'สร้าง'));
    await tester.pumpAndSettle();
    final b = (await repo.branches()).single;
    expect(find.byKey(ValueKey('tree-branch-${b.id}')), findsOneWidget);

    // สกิลในสาย (จากเมนูคลิกขวาที่สาย)
    await tester.tap(find.byKey(ValueKey('tree-branch-${b.id}')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มสกิลในสายนี้'));
    await tester.pumpAndSettle();
    expect(tester.widget<ChoiceChip>(find.byKey(ValueKey('skill-branch-${b.id}'))).selected, isTrue);
    await tester.enterText(find.byKey(const Key('skill-name')), 'DaVinci');
    await tester.tap(find.widgetWithText(FilledButton, 'สร้าง'));
    await tester.pumpAndSettle();
    final dv = (await repo.skills()).single;
    expect(dv.branchId, b.id);
    expect(find.descendant(of: find.byKey(const Key('tree-panel')), matching: find.text('ยังไม่เริ่ม')), findsOneWidget); // แผงขวาเลือกสกิลใหม่ให้

    // ทักษะย่อย 2 ด่าน
    for (final n in ['Cut', 'Color']) {
      await tester.tap(find.byKey(const Key('tree-add-node')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('node-name')), n);
      await tester.tap(find.widgetWithText(FilledButton, 'เพิ่ม'));
      await tester.pumpAndSettle();
    }
    final nodes = await repo.nodes();
    expect(nodes.map((n) => n.name), ['Cut', 'Color']);

    // ข้ามด่าน: Color ล็อกอยู่ → กดผ่านได้ แต่เตือน
    await tester.tap(find.byKey(ValueKey('tree-node-${nodes[1].id}')));
    await tester.pumpAndSettle();
    expect(find.text('🔒 ผ่านอันก่อนก่อน'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tree-node-toggle')));
    await tester.pump();
    expect(find.textContaining('ข้ามด่าน'), findsOneWidget);
    await tester.pumpAndSettle();
    expect((await repo.nodes()).last.done, isTrue);

    // สกิลที่ 2 + ต้องผ่าน DaVinci ก่อน (เมนูคลิกขวา)
    final th = await repo.saveSkill(Skill(name: 'Thumbnail', branchId: b.id, startedAt: DateTime(2026, 11, 1)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('tree-skill-$th')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้ง "ต้องผ่านก่อน"…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🎬 DaVinci').last); // ไอคอนเริ่มต้นของฟอร์ม
    await tester.pumpAndSettle();
    expect([for (final n in await repo.needs()) (n.skillId, n.needId)], [(th, dv.id)]);
    expect(find.text('🔒 ต้องผ่าน DaVinci ก่อน'), findsOneWidget);

    // กันวน: DaVinci ต้องผ่าน Thumbnail → ไม่ได้
    await tester.tap(find.byKey(ValueKey('tree-skill-${dv.id}')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้ง "ต้องผ่านก่อน"…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('🎯 Thumbnail').last);
    await tester.pump();
    expect(find.textContaining('จะวนกัน'), findsOneWidget);
    await tester.pumpAndSettle();
    expect((await repo.needs()).length, 1);

    // เปิดสกิลที่ล็อก → เตือน แล้วไปแท็บรายการ
    await tester.tap(find.byKey(ValueKey('tree-skill-$th')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('tree-open-skill')));
    await tester.pump();
    expect(find.textContaining('แค่เตือนว่าข้ามด่าน'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('skill-log')), findsOneWidget); // หน้ารายละเอียดสกิล
    expect(tester.takeException(), isNull);
  });
}
