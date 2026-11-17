// รอบ 13: บทเรียนในสกิล · หัวข้อ + คะแนน + ลิงก์คลิป · ย้ายวิชาเรียนเอง (รอบ 11) มาที่สกิล
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/data/noir_plan.dart';
import 'package:noir_manager/data/self_study.dart';
import 'package:noir_manager/skills/skill_lessons.dart';
import 'package:noir_manager/skills/skill_models.dart';
import 'package:noir_manager/skills/skill_repository.dart';
import 'package:noir_manager/skills/skill_tree.dart';
import 'package:noir_manager/skills/sqlite_skill_repository.dart';
import 'package:noir_manager/utils/open_link.dart';

final today = DateTime(2026, 11, 17);

/// หัวข้อ: เก็บ / คะแนนเป็นประวัติ / ลิงก์ · ลบบท = ลบหัวข้อ · ลบสกิล = ลบทั้งหมด
Future<void> topicRules(SkillRepository r) async {
  final s = await r.saveSkill(Skill(name: 'DaVinci Resolve', startedAt: today));
  final n = await r.saveNode(SkillNode(skillId: s, name: 'บท 1', url: 'https://youtu.be/a'));
  final n2 = await r.saveNode(SkillNode(skillId: s, name: 'บท 2', sort: 1));
  expect((await r.nodes()).firstWhere((x) => x.id == n).url, 'https://youtu.be/a');
  final t = await r.saveTopic(SkillTopic(nodeId: n, name: 'Cut', url: 'https://youtu.be/b'));
  await r.saveTopic(SkillTopic(nodeId: n, name: 'Trim', sort: 1));
  await r.saveTopic(SkillTopic(nodeId: n2, name: 'Color'));
  await r.addTopicScore(t, 40, at: DateTime(2026, 11, 10));
  await r.addTopicScore(t, 150, at: DateTime(2026, 11, 12)); // เกิน 100 → 100
  var cut = (await r.topics()).firstWhere((x) => x.id == t);
  expect(cut.scores.map((x) => x.score), [40, 100]);
  expect(cut.score, 100);
  expect(cut.green, isTrue);
  // แก้ชื่อ / โน้ต ไม่ทำคะแนนหาย
  await r.saveTopic(cut.copyWith(name: 'Cut page', note: 'blade = B'));
  cut = (await r.topics()).firstWhere((x) => x.id == t);
  expect((cut.name, cut.note, cut.url, cut.scores.length), ('Cut page', 'blade = B', 'https://youtu.be/b', 2));
  await r.saveNode((await r.nodes()).firstWhere((x) => x.id == n).copyWith(clearUrl: true));
  expect((await r.nodes()).firstWhere((x) => x.id == n).url, isNull);

  await r.deleteNode(n2);
  expect([for (final x in await r.topics()) x.name], ['Cut page', 'Trim']);
  await r.deleteSkill(s);
  expect(await r.nodes(), isEmpty);
  expect(await r.topics(), isEmpty);
}

void main() {
  sqfliteFfiInit();

  test('RAM: หัวข้อ + คะแนน', () => topicRules(MemorySkillRepository()));

  test('SQLite v23: หัวข้อ + คะแนน · CASCADE', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createSkillV19(db);
    await createSkillTreeV22(db);
    await createSkillLessonV23(db);
    await createSkillLessonV23(db); // รันซ้ำได้
    await topicRules(SqliteSkillRepository(db));
    await db.close();
  });

  test('อัปเกรด v22 → v23: ข้อมูลสกิลเดิมอยู่ครบ', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createSkillV19(db);
    await createSkillTreeV22(db);
    final repo = SqliteSkillRepository(db);
    final s = await repo.saveSkill(Skill(name: 'Canva', startedAt: today));
    await db.insert('skill_node', {'skill_id': s, 'name': 'ปก', 'sort': 0, 'done': 1});
    await createSkillLessonV23(db);
    final n = (await repo.nodes()).firstWhere((x) => x.skillId == s);
    expect((n.name, n.done, n.url), ('ปก', true, null));
    expect((await repo.skills()).single.name, 'Canva');
    await db.close();
  });

  group('% และสถานะบท จากหัวข้อ', () {
    final s = Skill(id: 1, name: 'A', startedAt: today);
    const n1 = SkillNode(id: 1, skillId: 1, name: 'บท 1');
    const n2 = SkillNode(id: 2, skillId: 1, name: 'บท 2', done: true); // ติ๊กเอง แต่มีหัวข้อ → ใช้หัวข้อ
    const n3 = SkillNode(id: 3, skillId: 1, name: 'บท 3');
    SkillTopic t(int id, int node, [int? score]) =>
        SkillTopic(id: id, nodeId: node, name: 't$id', scores: [if (score != null) TopicScore(score, today)]);

    test('% = หัวข้อ 🟢 / ทั้งหมด', () {
      final topics = [t(1, 1, 90), t(2, 1, 85), t(3, 2, 70), t(4, 2)];
      expect(skillRatio(s, nodes: const [n1, n2, n3], topics: topics, today: today), 0.5);
      // สกิลอื่นไม่ปน
      expect(skillRatio(s, nodes: const [n3], topics: topics, today: today), 0);
    });

    test('ผ่านบท = 🟢 ครบ · กำลังเรียน = มีคะแนน · บทก่อนไม่ผ่าน = ล็อก (แค่เตือน)', () {
      final topics = [t(1, 1, 90), t(2, 1, 85), t(3, 2, 70), t(4, 2)];
      expect(nodePassed(n1, topics), isTrue);
      expect(nodePassed(n2, topics), isFalse);
      expect(nodePassed(n3, topics), isFalse); // ไม่มีหัวข้อ + ไม่ติ๊ก
      final ns = const [n1, n2, n3];
      expect([for (var i = 0; i < 3; i++) nodeState(ns, i, topics: topics)], [TreeState.done, TreeState.prog, TreeState.lock]);
      final dots = layoutTree(
          branches: const [], skills: [s], nodes: ns, topics: topics, stats: skillStats([s], const [], const {}, const {}), rootLabel: 'Lv 1');
      expect([for (final d in dots) if (d.kind == DotKind.node) d.ratio], [1.0, 0.0, 0.0]);
    });

    test('ระดับสี 🟢 ≥ 80 · 🟡 60–79 · 🔴 < 60', () {
      expect([for (final v in [null, 40, 59, 60, 79, 80, 100]) topicLevel(v)], [
        TopicLevel.none, TopicLevel.bad, TopicLevel.bad, TopicLevel.ok, TopicLevel.ok, TopicLevel.good, TopicLevel.good, //
      ]);
    });
  });

  group('สารบัญ + ลิงก์', () {
    test('ทุกลิงก์เป็น YouTube https · ทุกบทมีหัวข้อ · ชื่อไม่ซ้ำในบท', () {
      for (final (_, _, _, toc) in lessonPresets) {
        expect({for (final ch in toc) ch.$1}.length, toc.length);
        for (final (_, url, topics) in toc) {
          expect(topics, isNotEmpty);
          expect({for (final x in topics) x.$1}.length, topics.length);
          for (final u in [url, for (final x in topics) x.$2]) {
            if (u == null) continue;
            expect(isWebLink(u), isTrue, reason: u);
            expect(Uri.parse(u).host, 'www.youtube.com', reason: u);
          }
        }
      }
      expect(yt('abc', 950), 'https://www.youtube.com/watch?v=abc&t=950s');
      expect(ytSearch('E2 IELTS listening'), 'https://www.youtube.com/results?search_query=E2+IELTS+listening');
    });

    test('ใส่สารบัญ: สร้างสกิลที่ยังไม่มี · กดซ้ำไม่ซ้อน · ทักษะย่อยแผนเก่าที่ว่างถูกแทน แต่ของที่มีข้อมูลอยู่ต่อ', () async {
      final r = MemorySkillRepository();
      final dv = await r.saveSkill(Skill(name: 'DaVinci', startedAt: today));
      await r.saveNode(SkillNode(skillId: dv, name: 'Color')); // แผนเก่า ว่าง → ลบ
      await r.saveNode(SkillNode(skillId: dv, name: 'Fairlight เสียง', done: true)); // ติ๊กแล้ว → เก็บ
      await r.saveNode(SkillNode(skillId: dv, name: 'บทของนัวร์')); // ตั้งเอง → เก็บ
      final res = await applyLessonPresets(r);
      expect(res.skills, 2); // Canva + IELTS
      expect(res.removed, 1);
      final total = lessonPresets.fold<int>(0, (a, p) => a + p.$4.length);
      expect(res.chapters, total);
      expect(res.topics, lessonPresets.fold<int>(0, (a, p) => a + p.$4.fold<int>(0, (b, c) => b + c.$3.length)));
      final names = [for (final n in await r.nodes()) if (n.skillId == dv) n.name];
      expect(names, containsAll(['Fairlight เสียง', 'บทของนัวร์', 'บท 5 สี (Color)']));
      expect(names, isNot(contains('Color')));
      final again = await applyLessonPresets(r);
      expect((again.skills, again.chapters, again.topics, again.removed), (0, 0, 0, 0));
    });

    test('แผนนัวร์ใส่สารบัญด้วย (ไม่มีทักษะย่อยแบบเก่า)', () async {
      final cal = MemoryCalendarRepository();
      await applyNoirPlan(cal, today);
      final names = {for (final n in await cal.skillRepo.nodes()) n.name};
      expect(names, isNot(contains('Vocab')));
      expect(names, contains('บท 2 Listening (E2 IELTS)'));
      expect((await cal.skillRepo.topics()).length, greaterThan(80));
    });
  });

  test('ย้ายวิชาเรียนเอง → สกิล: คะแนนตามมา · งานกลับเป็นงานธรรมดา · ลบวิชา · วิชาอื่นไม่โดน · กดซ้ำได้', () async {
    final cal = MemoryCalendarRepository();
    final study = MemoryStudyRepository();
    await applyNoirPlan(cal, today);
    final math = await study.addSubject('คณิต');
    final dvSub = await study.addSubject('DaVinci Resolve');
    final ch = await study.addChapter(dvSub, 'บท 5 สี (Color)');
    final same = await study.addSubtopic(ch, 'LUT'); // ชื่อตรงกับสารบัญ
    final other = await study.addSubtopic(ch, 'เรื่องเก่าที่ไม่มีแล้ว');
    await study.addSubtopic(ch, 'ยังไม่ให้คะแนน');
    await study.addAssessment(same, 60, at: DateTime(2026, 11, 1));
    await study.addAssessment(same, 85, at: DateTime(2026, 11, 5));
    await study.addAssessment(other, 50, at: DateTime(2026, 11, 2));
    // งานในแผนที่เคยผูกเป็นรอบติว (รอบ 11)
    final act = (await cal.activityIds()).first;
    final a = await cal.activity(act);
    await cal.updateActivity(
        act,
        NewActivity(
            name: a.name,
            categoryId: a.categoryId,
            importance: a.importance,
            timed: a.timed,
            day: a.startDate,
            startMinute: a.startMinute,
            durationMin: a.durationMin,
            repeat: a.repeat,
            weekdays: a.weekdays,
            endDate: a.endDate,
            subjectId: dvSub,
            kind: ActivityKind.tutor,
            flexible: a.flexible));

    final r = await moveSelfStudyToSkills(study, cal);
    expect((r.subjects, r.scores, r.unlinked), (1, 2, 1));
    expect([for (final s in await study.subjects()) s.id], [math]);
    final back = await cal.activity(act);
    expect((back.subjectId, back.kind, back.name), (null, ActivityKind.todo, a.name));

    final topics = await cal.skillRepo.topics();
    final lut = topics.where((t) => t.name == 'LUT').single;
    expect(lut.scores.map((s) => s.score), [60, 85]);
    expect(lut.green, isTrue);
    final moved = topics.where((t) => t.name == 'เรื่องเก่าที่ไม่มีแล้ว').single;
    expect(moved.score, 50);
    expect((await cal.skillRepo.nodes()).firstWhere((n) => n.id == moved.nodeId).name, movedChapterName);
    expect(topics.where((t) => t.name == 'ยังไม่ให้คะแนน'), isEmpty);

    final again = await moveSelfStudyToSkills(study, cal);
    expect((again.subjects, again.scores, again.unlinked, again.lessons.topics), (0, 0, 0, 0));
  });

  test('เปิดลิงก์: คำสั่งตามระบบ · มือถือ = ไม่มี (คัดลอกแทน) · ไม่ใช่ http = ไม่เปิด', () {
    final win = openCommand('https://x.y', os: 'windows')!;
    expect(win.$1, 'rundll32');
    expect(win.$2, ['url.dll,FileProtocolHandler', 'https://x.y']);
    expect(openCommand('https://x.y', os: 'macos')!.$1, 'open');
    expect(openCommand('https://x.y', os: 'android'), isNull);
    expect(isWebLink('https://www.youtube.com/watch?v=a'), isTrue);
    expect(isWebLink('file:///C:/x.exe'), isFalse);
    expect(isWebLink('calc.exe'), isFalse);
    expect(isWebLink(null), isFalse);
  });

  testWidgets('หน้าสกิล › บทเรียน: เพิ่มบท + หัวข้อ → ให้คะแนน 🟢 → % ขึ้น · บันทึกรอบเลือกหัวข้อได้', (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String?;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    tester.view.physicalSize = const Size(1400, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    final repo = cal.skillRepo;
    final s = await repo.saveSkill(Skill(name: 'Canva', icon: '🎨', startedAt: today));
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สกิล').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('tab-รายการ')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(ValueKey('skill-$s')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('lesson-add-chapter')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('chapter-name')), 'บท 1 ปก');
    await tester.enterText(find.byKey(const Key('chapter-url')), 'https://www.youtube.com/watch?v=abc');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    final node = (await repo.nodes()).single;
    expect(node.url, 'https://www.youtube.com/watch?v=abc');

    for (final name in ['ขนาด 1280×720', 'ลบพื้นหลัง']) {
      await tester.tap(find.byKey(ValueKey('lesson-add-topic-${node.id}')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('topic-name')), name);
      await tester.tap(find.widgetWithText(FilledButton, 'เพิ่ม'));
      await tester.pumpAndSettle();
    }
    final topics = await repo.topics();
    expect(topics.map((t) => t.name), ['ขนาด 1280×720', 'ลบพื้นหลัง']);
    expect(find.text('ประเมินแล้ว 0/2 หัวข้อ · 🟢 0'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('lesson-topic-${topics.first.id}')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('topic-score-90')));
    await tester.enterText(find.byKey(const Key('topic-url')), 'https://www.youtube.com/watch?v=xyz');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    final t1 = (await repo.topics()).first;
    expect((t1.score, t1.url), (90, 'https://www.youtube.com/watch?v=xyz'));
    expect(find.text('ประเมินแล้ว 1/2 หัวข้อ · 🟢 1'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('lesson-kpi-progress')), matching: find.text('50%')), findsOneWidget);

    // ▶ ระหว่างเทส = คัดลอกลิงก์
    await tester.tap(find.byKey(ValueKey('lesson-play-${t1.id}')));
    await tester.pumpAndSettle();
    expect(copied, 'https://www.youtube.com/watch?v=xyz');
    expect(find.textContaining('คัดลอกลิงก์แล้ว'), findsOneWidget);

    // บันทึกรอบ → เลือกหัวข้อ + คะแนน
    await tester.tap(find.byKey(const Key('skill-log')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('log-topic')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบพื้นหลัง').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('log-topic-score')), '65');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect((await repo.topics()).last.score, 65);
    expect(find.byKey(ValueKey('lesson-review-${topics.last.id}')), findsOneWidget); // ต้องทวน
    expect(tester.takeException(), isNull);
  });
}
