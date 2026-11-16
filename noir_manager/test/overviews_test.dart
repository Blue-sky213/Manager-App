// รอบ 9C: งาน › ภาพรวม · เงิน › ต้องจัดการ · สถิติ 6 แท็บ
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/skills/skill_models.dart';
import 'package:noir_manager/work/money_calc.dart';
import 'package:noir_manager/work/money_models.dart';
import 'package:noir_manager/work/project_calc.dart';
import 'package:noir_manager/work/project_models.dart';

final today = DateTime(2026, 11, 16);
DateTime d(int add) => today.add(Duration(days: add));

void main() {
  group('คิดภาพรวมงาน', () {
    const a = Project(id: 1, name: 'โรงงาน A', status: ProjectStatus.doing, price: 100000);
    const q = Project(id: 2, name: 'ใบเสนอ B', status: ProjectStatus.quote, price: 50000);
    const done = Project(id: 3, name: 'ปั๊ม D', status: ProjectStatus.paid, price: 20000);
    final tasks = {
      1: [
        ProjectTask(id: 11, projectId: 1, title: 'เดินท่อ', due: d(-1)),
        ProjectTask(id: 12, projectId: 1, title: 'ทดสอบแรงดัน', due: d(3)),
        ProjectTask(id: 13, projectId: 1, title: 'ส่งแบบ', due: d(20)),
        const ProjectTask(id: 14, projectId: 1, title: 'เก็บงาน'),
        ProjectTask(id: 15, projectId: 1, title: 'สำรวจ', due: d(-9), done: true),
      ],
      3: [ProjectTask(id: 31, projectId: 3, title: 'ส่งมอบ', due: d(-30))],
    };
    final pays = {
      1: [
        ProjectPayment(id: 21, projectId: 1, label: 'งวด 1', amount: 30000, due: d(-20), entryId: 900),
        ProjectPayment(id: 22, projectId: 1, label: 'งวด 2', amount: 40000, due: d(5)),
        const ProjectPayment(id: 23, projectId: 1, label: 'งวด 3', amount: 30000),
      ],
      2: [ProjectPayment(id: 41, projectId: 2, label: 'มัดจำ', amount: 10000, due: d(2))],
      3: [ProjectPayment(id: 51, projectId: 3, label: 'ทั้งหมด', amount: 20000, due: d(-40), entryId: 901)],
    };
    final entries = [
      MoneyEntry(id: 900, day: d(-20), kind: MoneyKind.income, amount: 30000, category: 'งวดงาน', projectId: 1),
      MoneyEntry(id: 901, day: d(-40), kind: MoneyKind.income, amount: 20000, category: 'งวดงาน', projectId: 3),
      MoneyEntry(id: 902, day: d(-45), kind: MoneyKind.expense, amount: 7600, category: 'วัสดุ / ค่าแรง', projectId: 3),
    ];

    test('ขั้นงาน: แบ่งตามกำหนด · เรียงใกล้ → ไกล · ไม่มีกำหนดท้าย · ไม่นับงานเสร็จ / งานที่เก็บเงินแล้ว', () {
      expect([for (final t in tasks[1]!) taskBucket(t, today)],
          [TaskBucket.overdue, TaskBucket.week, TaskBucket.later, TaskBucket.none, TaskBucket.overdue]);
      expect(openTasks(const [a, q, done], tasks).map((x) => x.$2.title), ['เดินท่อ', 'ทดสอบแรงดัน', 'ส่งแบบ', 'เก็บงาน']);
    });

    test('งวดรอรับ: ไม่นับใบเสนอราคา / งวดที่รับแล้ว · สรุปตัวเลข', () {
      expect(pendingPayments(const [a, q, done], pays).map((x) => x.$2.label), ['งวด 2', 'งวด 3']);
      final s = workSummary(const [a, q, done], tasks, pays, entries, today);
      expect((s.doing, s.pending, s.nextPay!.$2.label), (1, 70000.0, 'งวด 2'));
      expect((s.profitYear, s.closedYear), (12400.0, 1));
      expect((s.tasksDone, s.tasksTotal, s.overdue), (1, 5, 1));
    });

    test('ค่าบริการที่ต้องจัดการ: เลยวันตัดก่อน · ใกล้ตัด · จ่ายแล้ว / ยังไม่ถึง ไม่ขึ้น', () {
      const subs = [
        Subscription(id: 1, name: 'AI', amount: 700, billDay: 18),
        Subscription(id: 2, name: 'Workspace', amount: 200, billDay: 10),
        Subscription(id: 3, name: 'Adobe', amount: 969, billDay: 25),
        Subscription(id: 4, name: 'โดเมน', amount: 500, billDay: 12),
        Subscription(id: 5, name: 'ปิดแล้ว', amount: 99, billDay: 10, active: false),
      ];
      final paid = [MoneyEntry(day: DateTime(2026, 11, 12), kind: MoneyKind.expense, amount: 500, category: 'ค่าบริการ', subscriptionId: 4)];
      expect(billsToHandle(subs, paid, DateTime(2026, 11), today).map((x) => (x.$1.name, x.$2)),
          [('Workspace', BillState.overdue), ('AI', BillState.dueSoon)]);
    });
  });

  testWidgets('งาน › ภาพรวม · เงิน › ต้องจัดการ · สถิติ 6 แท็บ: ติ๊กจากภาพรวมได้เลย', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final t = DateTime(now.year, now.month, now.day);
    final cal = MemoryCalendarRepository();
    final w = cal.workRepo;
    final pj = await w.saveProject(Project(name: 'ท่อไอน้ำ โรงงาน A', type: 'steam', status: ProjectStatus.doing, price: 100000, due: t.add(const Duration(days: 30))));
    final task = await w.saveTask(ProjectTask(projectId: pj, title: 'เดินท่อชั้น 2', due: t.subtract(const Duration(days: 1))));
    await w.saveTask(ProjectTask(projectId: pj, title: 'ทดสอบแรงดัน', due: t.add(const Duration(days: 20))));
    final pay = await w.savePayment(ProjectPayment(projectId: pj, label: 'งวด 2', amount: 40000, due: t.add(const Duration(days: 5))));
    final sub = await w.saveSubscription(Subscription(name: 'บริการ AI', amount: 700, billDay: t.day));
    await w.saveEntry(MoneyEntry(day: t, kind: MoneyKind.expense, amount: 120, category: 'อาหาร'));
    final sk = await cal.skillRepo.saveSkill(Skill(name: 'DaVinci', icon: '🎬', startedAt: t.subtract(const Duration(days: 40))));
    await cal.skillRepo.saveLog(SkillLog(skillId: sk, day: t.subtract(const Duration(days: 2)), minutes: 90));
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();

    // งาน › ภาพรวม
    await tester.tap(find.text('งาน').first);
    await tester.pumpAndSettle();
    expect((tester.widget(find.byKey(const Key('work-kpi-doing'))) as Text).data, '1');
    expect((tester.widget(find.byKey(const Key('work-kpi-pending'))) as Text).data, '฿40,000');
    expect((tester.widget(find.byKey(const Key('work-kpi-tasks'))) as Text).data, '0/2');
    await tester.tap(find.byKey(ValueKey('ov-task-$task')));
    await tester.pumpAndSettle();
    expect((await w.tasks(pj)).firstWhere((x) => x.id == task).done, isTrue);
    await tester.tap(find.byKey(const Key('work-all-tasks')));
    await tester.pumpAndSettle();
    expect(find.text('ทีหลัง · 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('all-done-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(ValueKey('all-task-$task')), findsOneWidget);
    // คลิกงาน → ไปบอร์ด เปิดการ์ดนั้น
    await tester.tap(find.text('ทดสอบแรงดัน'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pj-kpi-price')), findsOneWidget);

    // เงิน › ต้องจัดการ
    await tester.tap(find.text('เงิน').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('money-todo')), findsOneWidget);
    expect(find.byKey(ValueKey('todo-sub-$sub')), findsOneWidget); // วันตัด = วันนี้ → ใกล้ตัด
    await tester.tap(find.byKey(ValueKey('todo-pay-$pay')));
    await tester.pumpAndSettle();
    expect((await w.payments(pj)).single.received, isTrue);
    expect(find.byKey(ValueKey('todo-pay-$pay')), findsNothing);
    expect((tester.widget(find.byKey(const Key('kpi-in'))) as Text).data, '฿40,000');
    for (final tab in ['รายการ', 'ค่าบริการ', 'ลงทุน', 'เดือนนี้']) {
      await tester.tap(find.byKey(ValueKey('tab-$tab')));
      await tester.pumpAndSettle();
    }

    // สถิติ › ภาพรวม → การ์ด → แท็บ
    await tester.tap(find.text('สถิติ').first);
    await tester.pumpAndSettle();
    expect((tester.widget(find.byKey(const ValueKey('stats-value-skill'))) as Text).data, '1.5 ชม.');
    expect((tester.widget(find.byKey(const ValueKey('stats-value-work'))) as Text).data, '1 กำลังทำ');
    await tester.tap(find.byKey(const ValueKey('stats-card-skill')));
    await tester.pumpAndSettle();
    expect(find.text('🎬 DaVinci'), findsOneWidget);
    for (final tab in ['เรียน', 'งาน', 'เงิน', 'ชีวิต']) {
      await tester.tap(find.byKey(ValueKey('tab-$tab')));
      await tester.pumpAndSettle();
    }
    expect(find.text('ทำตามแผนรายวัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
