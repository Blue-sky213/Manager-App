// รอบ 9D: ข้อมูลตัวอย่างทุกเมนู · ตัวตรวจกฎ · ทุกหน้า/ทุกแท็บเปิดได้ตอนข้อมูลเยอะ
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/demo_life.dart';
import 'package:noir_manager/data/demo_year.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/skills/skill_models.dart';
import 'package:noir_manager/skills/skill_tree.dart';
import 'package:noir_manager/work/money_models.dart';
import 'package:noir_manager/work/project_models.dart';

final today = DateTime(2026, 11, 16);

/// ชุดเล็ก (ไม่มีปฏิทิน 1 ปี) ไว้ทดสอบตัวตรวจกฎเร็ว ๆ
Future<MemoryCalendarRepository> small() async {
  final cal = MemoryCalendarRepository();
  await fillDemoLife(cal, today);
  return cal;
}

void main() {
  test('ข้อมูลตัวอย่างทั้งชุด: ผ่านตัวตรวจกฎทุกข้อ · ครบทุกเมนู · seed เดิมได้ผลเดิม', () async {
    final y = await buildDemoYear(today: today);
    final cal = y.calendar;
    expect(await checkDemoYear(cal, today, y.sessions), isEmpty);
    expect(await checkDemoLife(cal, today), isEmpty);
    expect(await checkPracticeSlots(cal, today.subtract(const Duration(days: 60)), today.add(const Duration(days: 30))), isEmpty);

    // สกิล: 4 สาย · 7 สกิล · มีทุกสถานะ · Thumbnail ล็อก
    final r = cal.skillRepo;
    expect((await r.branches()).length, 4);
    final skills = await r.skills();
    expect(skills.length, 7);
    expect(skills.map((s) => s.status).toSet(), SkillStatus.values.toSet());
    expect((await r.needs()).length, 1);
    var files = 0;
    for (final s in skills) {
      files += (await r.files(s.id)).length;
    }
    expect(files, 6);

    // งาน: 5 โปรเจกต์ ครบทุกสถานะ · มีขั้นงานเลยกำหนด 1
    final w = cal.workRepo;
    final pjs = await w.projects();
    expect(pjs.map((p) => p.status).toSet(), ProjectStatus.values.toSet());
    var overdue = 0;
    for (final p in pjs) {
      overdue += (await w.tasks(p.id)).where((t) => !t.done && t.due != null && t.due!.isBefore(today)).length;
    }
    expect(overdue, 1);

    // เงิน: 12 เดือนมีรายการทุกเดือน · ค่าบริการ 4 (รายปี 1 · ไม่มียอด 1) · ลงทุน 1 คืน ~22%
    final all = await w.entries(DateTime(2000), DateTime(2100));
    for (var i = 0; i < 12; i++) {
      final m = DateTime(today.year, today.month - i);
      expect(all.any((e) => e.day.year == m.year && e.day.month == m.month), isTrue, reason: '${m.year}-${m.month}');
    }
    final subs = await w.subscriptions();
    expect((subs.length, subs.where((s) => s.cycle == BillCycle.yearly).length, subs.where((s) => s.amount == null).length), (4, 1, 1));
    final inv = (await w.investments()).single;
    final back = all.where((e) => e.investmentId == inv.id).fold<double>(0, (a, e) => a + e.amount);
    expect(back / inv.amount, closeTo(0.22, 0.001));

    // ชีวิต: เช็กอิน 60 วัน
    expect((await cal.checkins(today.subtract(const Duration(days: 61)), today)).length, 60);

    // seed เดิม = ผลเดิม
    final again = await small();
    final a = await (await small()).workRepo.entries(DateTime(2000), DateTime(2100));
    final b = await again.workRepo.entries(DateTime(2000), DateTime(2100));
    expect(a.map((e) => '${e.day}${e.amount}${e.category}'), b.map((e) => '${e.day}${e.amount}${e.category}'));
  });

  test('ตัวตรวจกฎจับผิดได้ทุกข้อ', () async {
    final cal = await small();
    final r = cal.skillRepo, w = cal.workRepo;
    final skills = await r.skills();
    final dv = skills.firstWhere((s) => s.name.startsWith('DaVinci'));
    final th = skills.firstWhere((s) => s.name == 'Thumbnail');
    final dvLog = (await r.logs(dv.id)).first;
    await r.saveLog(SkillLog(skillId: dv.id, day: dvLog.day, minutes: 30)); // ซ้ำวัน
    await r.saveLog(SkillLog(skillId: dv.id, day: today.add(const Duration(days: 2)), minutes: 30)); // อนาคต
    await r.saveLog(SkillLog(skillId: th.id, day: today.subtract(const Duration(days: 1)), minutes: 30)); // ล็อกแต่มีบันทึก
    final nodes = [for (final n in await r.nodes()) if (n.skillId == dv.id) n];
    await r.saveNode(nodes.last.copyWith(done: true)); // ข้ามด่าน

    final pjs = await w.projects();
    final quote = pjs.firstWhere((p) => p.status == ProjectStatus.quote);
    await w.savePayment(ProjectPayment(projectId: quote.id, label: 'เกิน', amount: 1000)); // งวดรวม ≠ ราคา
    final paid = pjs.firstWhere((p) => p.status == ProjectStatus.paid);
    await w.savePayment(ProjectPayment(projectId: paid.id, label: 'ค้าง', amount: 0)); // เก็บเงินแล้วแต่ค้าง
    await w.saveTask(ProjectTask(projectId: paid.id, title: 'เสร็จล่วงหน้า', due: today.add(const Duration(days: 5)), done: true));

    await w.saveEntry(MoneyEntry(day: today.add(const Duration(days: 3)), kind: MoneyKind.expense, amount: 10, category: 'อาหาร'));
    final sub = (await w.subscriptions()).first;
    await w.saveEntry(MoneyEntry(
        day: DateTime(today.year, today.month, sub.billDay + 1), kind: MoneyKind.expense, amount: 1, category: 'ค่าบริการ', subscriptionId: sub.id));
    await w.saveEntry(MoneyEntry(day: DateTime(today.year, today.month, 2), kind: MoneyKind.expense, amount: 500000, category: 'อุปกรณ์'));

    await cal.saveCheckin(Checkin(
        day: today.subtract(const Duration(days: 70)),
        sleptAt: DateTime(2026, 9, 6, 23),
        wokeAt: DateTime(2026, 9, 7, 3),
        energy: 9));

    final e = (await checkDemoLife(cal, today)).join('\n');
    for (final want in [
      'บันทึกซ้ำวันเดียวกัน',
      'บันทึกสกิลในอนาคต',
      'สกิลที่ยังล็อกมีบันทึก',
      'ทักษะย่อยข้ามด่าน',
      'งวดรวมไม่เท่าราคา',
      'เก็บเงินแล้วแต่ยังมีงวดค้าง',
      'ขั้นงานเสร็จในอนาคต',
      'รายการเงินในอนาคต',
      'ค่าบริการไม่ตรงวันตัด',
      '≥ รายรับเฉลี่ย',
      'นอน 4.0 ชม.',
      'พลังเช้า 9',
    ]) {
      expect(e, contains(want));
    }
  });

  test('ตัวตรวจกฎ: เป้าเร็วขึ้นต้องดีขึ้นแบบมีขึ้นลง · ต้องผ่านก่อนห้ามวน', () async {
    final cal = MemoryCalendarRepository();
    final r = cal.skillRepo;
    final a = await r.saveSkill(Skill(name: 'A', startedAt: DateTime(2026, 10, 1)));
    final b = await r.saveSkill(Skill(name: 'B', startedAt: DateTime(2026, 10, 1)));
    final g = await r.saveGoal(SkillGoal(skillId: a, kind: GoalKind.faster, title: 'เร็ว', unit: 'นาที', target: 60));
    for (final (i, v) in [100.0, 90.0, 80.0, 70.0].indexed) {
      await r.saveLog(SkillLog(skillId: a, goalId: g, day: DateTime(2026, 11, 1 + i), value: v, minutes: 60));
    }
    await r.addNeed(a, b);
    await r.addNeed(b, a); // repo ไม่กัน (UI กัน) → ตัวตรวจต้องเจอ
    final e = (await checkDemoLife(cal, today)).join('\n');
    expect(e, contains('ลดลงตรงเป๊ะ'));
    expect(e, contains('วนกัน'));
    expect(needMakesLoop(const [SkillNeed(1, 2)], 2, 1), isTrue);
  });

  test('ลบค่าบริการ → รายการที่จ่ายแล้วยังอยู่ (โจทย์ เงิน › ลบ)', () async {
    final cal = await small();
    final w = cal.workRepo;
    final sub = (await w.subscriptions()).first;
    final paid = (await w.entries(DateTime(2000), DateTime(2100))).where((e) => e.subscriptionId == sub.id).length;
    expect(paid, greaterThan(0));
    await w.deleteSubscription(sub.id);
    final left = (await w.entries(DateTime(2000), DateTime(2100))).where((e) => e.category == 'ค่าบริการ' && e.note == sub.name);
    expect(left.length, paid);
  });

  for (final size in const [Size(1400, 900), Size(393, 852)]) {
    testWidgets('ข้อมูลตัวอย่างทั้งชุด: ทุกเมนู ทุกแท็บ เปิดได้ ไม่ล้น ที่ ${size.width.toInt()}×${size.height.toInt()}', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      late DemoYear y;
      await tester.runAsync(() async => y = await buildDemoYear(today: DateTime.now()));
      await tester.pumpWidget(NoirManagerApp(studyRepository: y.study, calendarRepository: y.calendar));
      await tester.pumpAndSettle();
      const tabs = {
        'การเรียน': ['ภาพรวม', 'รายวิชา', 'แผน 4 ปี', 'ตารางเรียน', 'เกรด'],
        'สกิล': ['แผนผัง', 'รายการ'],
        'งาน': ['ภาพรวม', 'บอร์ด', 'ขั้นงานทั้งหมด'],
        'เงิน': ['เดือนนี้', 'รายการ', 'ค่าบริการ', 'ลงทุน'],
        'สถิติ': ['ภาพรวม', 'เรียน', 'สกิล', 'งาน', 'เงิน', 'ชีวิต'],
        'วันนี้': <String>[],
        'ปฏิทิน': <String>[],
        'ไฟล์': <String>[],
      };
      for (final MapEntry(key: menu, value: list) in tabs.entries) {
        if (find.text(menu).hitTestable().evaluate().isEmpty) {
          await tester.tap(find.byKey(const Key('nav-more')));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text(menu).hitTestable().first);
        await tester.pumpAndSettle();
        for (final t in list) {
          final k = find.byKey(ValueKey('tab-$t'));
          await tester.ensureVisible(k);
          await tester.tap(k);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$menu › $t');
        }
        expect(tester.takeException(), isNull, reason: menu);
      }
    });
  }
}
