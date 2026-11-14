import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/work/money_models.dart';
import 'package:noir_manager/work/project_calc.dart';
import 'package:noir_manager/work/project_models.dart';
import 'package:noir_manager/work/work_repository.dart';

Future<void> repoRules(WorkRepository repo) async {
  final id = await repo.saveProject(Project(
      name: 'ท่อไอน้ำ โรงงาน A', client: 'บริษัท A', type: 'steam', price: 180000, start: DateTime(2026, 11, 3), due: DateTime(2026, 12, 20), travelMinutes: 45));
  final pj = (await repo.projects()).single;
  expect((pj.type, pj.price, pj.travelMinutes, pj.due), ('steam', 180000.0, 45, DateTime(2026, 12, 20)));
  await repo.saveProject(pj.copyWith(status: ProjectStatus.doing));
  expect((await repo.projects()).single.status, ProjectStatus.doing);
  await repo.saveMember(ProjectMember(projectId: id, name: 'ช่าง ก', role: 'ช่างเชื่อม', duty: 'เดินท่อ ชั้น 2'));
  final t = await repo.saveTask(ProjectTask(projectId: id, title: 'เดินท่อ ชั้น 2', owner: 'ช่าง ก', due: DateTime(2026, 11, 28)));
  final task = (await repo.tasks(id)).single;
  await repo.saveTask(task.copyWith(done: true, activityId: 99));
  expect(((await repo.tasks(id)).single.done, (await repo.tasks(id)).single.activityId), (true, 99));
  final pay = await repo.savePayment(ProjectPayment(projectId: id, label: '1 · 30%', amount: 54000, condition: 'เซ็นสัญญา'));
  final entry = await repo.saveEntry(MoneyEntry(day: DateTime(2026, 11, 3), kind: MoneyKind.income, amount: 54000, category: 'งวดงาน', projectId: id));
  await repo.savePayment((await repo.payments(id)).single.withEntry(entry));
  expect((await repo.payments(id)).single.received, isTrue);
  await repo.saveProjectFile(ProjectFile(projectId: id, kind: ProjectFileKind.link, path: 'https://x', title: 'แบบ', addedAt: DateTime(2026, 11, 3)));
  expect(await repo.projectFiles(id), hasLength(1));
  expect(t, isPositive);
  expect(pay, isPositive);
  // ลบโปรเจกต์ → ของในโปรเจกต์หาย · รายการเงินอยู่ (ไม่ผูก)
  await repo.deleteProject(id);
  expect(await repo.projects(), isEmpty);
  expect(await repo.members(id), isEmpty);
  expect(await repo.payments(id), isEmpty);
  final left = await repo.entries(DateTime(2000), DateTime(2100));
  expect(left, hasLength(1));
  expect(left.single.projectId, isNull);
}

void main() {
  test('ตัวเลขโปรเจกต์ · งวด 30/40/30 รวมพอดีราคา · ขั้นงานถัดไป', () {
    const pj = Project(id: 1, name: 'A', price: 180000);
    final entries = [
      MoneyEntry(day: DateTime(2026, 11, 3), kind: MoneyKind.income, amount: 54000, category: 'งวดงาน', projectId: 1),
      MoneyEntry(day: DateTime(2026, 11, 7), kind: MoneyKind.expense, amount: 96300, category: 'วัสดุ / ค่าแรง', projectId: 1),
      MoneyEntry(day: DateTime(2026, 11, 7), kind: MoneyKind.expense, amount: 500, category: 'อาหาร'), // ไม่ผูก
    ];
    final m = projectMoney(pj, entries, const [
      ProjectPayment(projectId: 1, label: '1', amount: 54000, entryId: 5),
      ProjectPayment(projectId: 1, label: '2', amount: 72000),
      ProjectPayment(projectId: 1, label: '3', amount: 54000),
    ]);
    expect((m.price, m.cost, m.profit, m.received, m.remaining), (180000.0, 96300.0, 83700.0, 54000.0, 126000.0));
    expect((m.paidCount, m.paymentCount), (1, 3));
    expect(splitByPercent(100001, const [30, 40, 30]), [30000, 40000, 30001]);
    final next = nextTask([
      ProjectTask(projectId: 1, title: 'ทดสอบ', due: DateTime(2026, 12, 15)),
      ProjectTask(projectId: 1, title: 'สำรวจ', due: DateTime(2026, 11, 3), done: true),
      ProjectTask(projectId: 1, title: 'เดินท่อ', due: DateTime(2026, 11, 28)),
      const ProjectTask(projectId: 1, title: 'ไม่มีกำหนด'),
    ]);
    expect(next!.title, 'เดินท่อ');
  });

  test('RAM: โปรเจกต์', () => repoRules(MemoryWorkRepository()));

  test('SQLite v21: โปรเจกต์ · รันซ้ำได้', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createMoneyV20(db);
    await createProjectV21(db);
    await createProjectV21(db);
    await repoRules(SqliteWorkRepository(db));
    await db.close();
  });

  testWidgets('งาน › โปรเจกต์: สร้าง (งวด 30/40/30) → ติ๊กรับงวด = ลงรายรับ · เพิ่มคน · ขั้นงาน', (tester) async {
    tester.view.physicalSize = const Size(1400, 2200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('งาน').first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('pj-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('pj-name')), 'ท่อไอน้ำ โรงงาน A');
    await tester.enterText(find.byKey(const Key('pj-price')), '180000');
    await tester.pump();
    expect(find.byKey(const Key('pj-split')), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'สร้าง'));
    await tester.pumpAndSettle();
    final pj = (await cal.workRepo.projects()).single;
    final pays = await cal.workRepo.payments(pj.id);
    expect(pays.map((p) => p.amount), [54000, 72000, 54000]);
    expect(find.text('เสนอราคา'), findsWidgets);
    expect((tester.widget(find.byKey(const Key('pj-kpi-price'))) as Text).data, '฿180,000');

    // รับเงินงวด 1 → การเงินได้รายรับ · กำไร/รับแล้วอัปเดต
    await tester.tap(find.byKey(ValueKey('pay-${pays.first.id}')));
    await tester.pumpAndSettle();
    final income = await cal.workRepo.entries(DateTime(2000), DateTime(2100));
    expect(income.single.amount, 54000);
    expect(income.single.projectId, pj.id);
    expect((tester.widget(find.byKey(const Key('pj-kpi-received'))) as Text).data, '฿54,000');
    // ติ๊กออก = ลบรายรับนั้น
    await tester.tap(find.byKey(ValueKey('pay-${pays.first.id}')));
    await tester.pumpAndSettle();
    expect(await cal.workRepo.entries(DateTime(2000), DateTime(2100)), isEmpty);

    await tester.tap(find.byKey(const Key('mb-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('mb-name')), 'ช่าง ก');
    await tester.enterText(find.byKey(const Key('mb-role')), 'ช่างเชื่อม');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(find.text('ช่างเชื่อม'), findsOneWidget);

    await tester.tap(find.byKey(const Key('task-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('task-title')), 'เดินท่อ ชั้น 2');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    final task = (await cal.workRepo.tasks(pj.id)).single;
    await tester.tap(find.byKey(ValueKey('task-${task.id}')));
    await tester.pumpAndSettle();
    expect((await cal.workRepo.tasks(pj.id)).single.done, isTrue);
    expect(tester.takeException(), isNull);
  });
}
