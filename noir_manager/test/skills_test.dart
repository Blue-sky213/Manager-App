import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/skills/skill_models.dart';
import 'package:noir_manager/skills/skill_progress.dart';
import 'package:noir_manager/skills/skill_repository.dart';
import 'package:noir_manager/skills/sqlite_skill_repository.dart';

final today = DateTime(2026, 11, 14); // เสาร์

SkillLog log(int id, DateTime day, {int? goal, double? value, int? minutes, int? occ, bool skipped = false}) =>
    SkillLog(id: id, skillId: 1, goalId: goal, day: day, value: value, minutes: minutes, occurrenceId: occ, skipped: skipped);

/// เก็บ / อ่าน / ลบ · เหมือนกันทั้ง RAM และ SQLite
Future<void> repoRules(SkillRepository repo) async {
  final id = await repo.saveSkill(Skill(name: 'DaVinci Resolve', icon: '🎬', startedAt: DateTime(2026, 11, 1), why: 'ตัดคลิปสตรีม'));
  final g = await repo.saveGoal(SkillGoal(
      skillId: id, kind: GoalKind.milestone, title: 'รู้จักทุกหน้า', steps: const [GoalStep('Cut', done: true), GoalStep('Color')]));
  final goals = await repo.goals(id);
  expect(goals.single.steps.map((s) => (s.title, s.done)), [('Cut', true), ('Color', false)]);
  final l1 = await repo.saveLog(SkillLog(skillId: id, goalId: g, day: DateTime(2026, 11, 9), minutes: 90, rating: 4, better: 'blade ไวขึ้น'));
  await repo.saveLog(SkillLog(skillId: id, day: DateTime(2026, 11, 12), skipped: true, stuck: 'งานด่วน'));
  final logs = await repo.logs(id);
  expect(logs.map((l) => l.day.day), [12, 9]); // ใหม่ → เก่า
  expect(logs.last.better, 'blade ไวขึ้น');
  expect(logs.first.skipped, isTrue);
  await repo.saveFile(SkillFile(skillId: id, logId: l1, kind: SkillFileKind.link, path: 'https://youtu.be/x', title: 'คลิป', addedAt: DateTime(2026, 11, 9)));
  final f = (await repo.files(id)).single;
  await repo.saveFile(f.copyWith(featured: true));
  expect((await repo.files(id)).single.featured, isTrue);
  await repo.saveReview(SkillReview(skillId: id, month: '2026-11', can: 'Cut page', weak: 'Color'));
  await repo.saveReview(SkillReview(skillId: id, month: '2026-11', can: 'Cut page · ซับ', weak: 'Color'));
  expect((await repo.review(id, '2026-11'))!.can, 'Cut page · ซับ');
  await repo.linkActivity(id, 77);
  expect(await repo.skillOfActivity(77), id);
  expect(await repo.activitiesOf(id), [77]);
  final s = (await repo.skills()).single;
  await repo.saveSkill(s.copyWith(status: SkillStatus.done, doneAt: DateTime(2026, 11, 30)));
  expect((await repo.skills()).single.status, SkillStatus.done);
  await repo.deleteSkill(id);
  expect(await repo.skills(), isEmpty);
  expect(await repo.logs(id), isEmpty);
  expect(await repo.skillOfActivity(77), isNull);
}

void main() {
  group('ความคืบหน้าเป้า', () {
    test('เร็วขึ้น: นับรอบติดจากล่าสุด · ถึงเป้าเมื่อครบ', () {
      const g = SkillGoal(id: 5, skillId: 1, kind: GoalKind.faster, title: 'ตัดคลิป 1 ชม.', unit: 'นาที', target: 90, streak: 3);
      final logs = [
        log(1, DateTime(2026, 11, 1), goal: 5, value: 160),
        log(2, DateTime(2026, 11, 3), goal: 5, value: 88),
        log(3, DateTime(2026, 11, 5), goal: 5, value: 95), // ตัดสาย
        log(4, DateTime(2026, 11, 7), goal: 5, value: 89),
        log(5, DateTime(2026, 11, 9), goal: 5, value: 90),
        log(6, DateTime(2026, 11, 10), goal: 9, value: 10), // เป้าอื่น
      ];
      var p = goalProgress(g, logs, today: today);
      expect(p.run, 2);
      expect(p.met, isFalse);
      expect(p.current, '1:30 ชม.');
      expect(p.best, '1:28 ชม.');
      expect(p.series.length, 5);
      p = goalProgress(g, [...logs, log(7, DateTime(2026, 11, 12), goal: 5, value: 84)], today: today);
      expect(p.run, 3);
      expect(p.met, isTrue);
    });

    test('จำนวน: วันนี้ยังไม่ครบไม่ตัดสาย · ขาดวันตัดสาย', () {
      const g = SkillGoal(id: 2, skillId: 1, kind: GoalKind.count, title: 'คำศัพท์', unit: 'คำ', target: 10, streak: 3);
      final logs = [
        log(1, DateTime(2026, 11, 10), goal: 2, value: 12),
        log(2, DateTime(2026, 11, 12), goal: 2, value: 6),
        log(3, DateTime(2026, 11, 12), goal: 2, value: 5), // รวม 11
        log(4, DateTime(2026, 11, 13), goal: 2, value: 10),
        log(5, DateTime(2026, 11, 14), goal: 2, value: 3), // วันนี้ยังไม่ครบ
      ];
      final p = goalProgress(g, logs, today: today);
      expect(p.run, 2); // 12, 13 (11 ขาด)
      expect(p.current, '3 คำ วันนี้');
      expect(p.ratio, closeTo(0.3, 1e-9));
    });

    test('ปริมาณ: ปฏิทิน + บันทึกที่ไม่ได้มาจากปฏิทิน (ไม่นับซ้ำ) · สัปดาห์ติด', () {
      const g = SkillGoal(id: 3, skillId: 1, kind: GoalKind.volume, title: 'ฟัง English', unit: 'ชม.', target: 2, streak: 2);
      final practice = {DateTime(2026, 11, 3): 60, DateTime(2026, 11, 5): 60, DateTime(2026, 11, 10): 90};
      final logs = [
        log(1, DateTime(2026, 11, 10), minutes: 90, occ: 33), // มาจากงานในปฏิทิน (นับแล้ว)
        log(2, DateTime(2026, 11, 13), minutes: 30), // ฝึกนอกแผน
      ];
      final p = goalProgress(g, logs, practiceMinutes: practice, today: today);
      expect(p.current, '2 / 2 ชม. สัปดาห์นี้');
      expect(p.run, 2);
      expect(p.met, isTrue);
    });

    test('ด่าน: ผ่านครบ = ถึงเป้า', () {
      const g = SkillGoal(skillId: 1, kind: GoalKind.milestone, title: 'หน้าใน DaVinci', steps: [GoalStep('Cut', done: true), GoalStep('Color')]);
      expect(goalProgress(g, const [], today: today).met, isFalse);
      final done = g.copyWith(steps: const [GoalStep('Cut', done: true), GoalStep('Color', done: true)]);
      final p = goalProgress(done, const [], today: today);
      expect(p.met, isTrue);
      expect(p.current, '2 / 2 ด่าน');
    });
  });

  test('RAM: เก็บ / อ่าน / ลบสกิล', () => repoRules(MemorySkillRepository()));

  test('SQLite v19: เก็บ / อ่าน / ลบ (ลบสกิล = ลบของในสกิล) · รันซ้ำได้', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createSkillV19(db);
    await createSkillV19(db);
    await repoRules(SqliteSkillRepository(db));
    await db.close();
  });

  testWidgets('การเรียน › สกิล: สร้างสกิล → เป้าเร็วขึ้น → บันทึก 3 รอบ → ถึงเป้า ถามจบ/พัก/ยกระดับ · แผนฝึกลงปฏิทิน',
      (tester) async {
    tester.view.physicalSize = const Size(1400, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('สกิล').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('skill-add-empty')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('skill-name')), 'DaVinci Resolve');
    await tester.tap(find.byKey(const Key('skill-icon-🎬')));
    await tester.tap(find.widgetWithText(FilledButton, 'สร้าง'));
    await tester.pumpAndSettle();
    expect(find.text('DaVinci Resolve'), findsWidgets);

    // เป้า: ตัดคลิป ≤ 90 นาที · 3 รอบติด
    await tester.tap(find.byKey(const Key('goal-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('goal-title')), 'ตัดคลิป 1 ชม.');
    await tester.enterText(find.byKey(const Key('goal-target')), '90');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(find.text('≤ 1:30 ชม. · 3 รอบติด'), findsOneWidget);

    for (final v in ['88', '85', '80']) {
      await tester.tap(find.byKey(const Key('skill-log')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('log-minutes')), '95');
      await tester.enterText(find.byKey(const Key('log-value')), v);
      await tester.tap(find.byKey(const Key('log-star-4')));
      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();
    }
    final skill = (await cal.skillRepo.skills()).single;
    expect(await cal.skillRepo.logs(skill.id), hasLength(3));
    expect(find.textContaining('ถึงเป้าแล้ว'), findsOneWidget);

    // แผนฝึก → งานซ้ำรายสัปดาห์ ผูกกับสกิล
    await tester.tap(find.byKey(const Key('skill-plan')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ลงปฏิทิน'));
    await tester.pumpAndSettle();
    final acts = await cal.skillRepo.activitiesOf(skill.id);
    expect(acts, hasLength(1));
    final a = await cal.activity(acts.single);
    expect(a.name, 'ฝึก · DaVinci Resolve');
    expect(a.flexible, isTrue);
    expect(a.weekdays, {1, 3, 5});
    expect(find.textContaining('แผน: จ พ ศ · 19:00'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
