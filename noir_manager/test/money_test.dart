import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/shell/app_nav.dart';
import 'package:noir_manager/work/money_calc.dart';
import 'package:noir_manager/work/money_models.dart';
import 'package:noir_manager/work/work_repository.dart';

MoneyEntry e(DateTime d, MoneyKind k, double a, {String cat = 'อื่น ๆ', int? inv, int? sub}) =>
    MoneyEntry(day: d, kind: k, amount: a, category: cat, investmentId: inv, subscriptionId: sub);

Future<void> repoRules(WorkRepository repo) async {
  final sub = await repo.saveSubscription(const Subscription(name: 'Adobe', amount: 969, billDay: 5));
  await repo.saveSubscription(const Subscription(name: 'โดเมน', cycle: BillCycle.yearly, billDay: 10, billMonth: 3));
  final inv = await repo.saveInvestment(Investment(name: 'คอมสตรีม', amount: 45000, startDay: DateTime(2026, 6, 1)));
  await repo.saveEntry(e(DateTime(2026, 11, 5), MoneyKind.expense, 969, cat: 'ค่าบริการ', sub: sub));
  await repo.saveEntry(e(DateTime(2026, 11, 8), MoneyKind.income, 3000, cat: 'งานรับจ้าง', inv: inv));
  await repo.saveEntry(e(DateTime(2026, 10, 30), MoneyKind.expense, 120, cat: 'อาหาร'));
  final nov = await repo.entries(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
  expect(nov.map((x) => x.day.day), [8, 5]); // ใหม่ → เก่า · ไม่รวม ต.ค.
  expect(nov.last.subscriptionId, sub);
  expect(nov.first.investmentId, inv);
  final subs = await repo.subscriptions();
  expect(subs.map((s) => s.name), ['Adobe', 'โดเมน']); // เรียงตามวันตัด
  expect(subs.last.cycle, BillCycle.yearly);
  expect(subs.last.amount, isNull);
  // ลบเงินลงทุน → รายรับยังอยู่ แค่ไม่ผูก
  await repo.deleteInvestment(inv);
  final after = await repo.entries(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
  expect(after, hasLength(2));
  expect(after.first.investmentId, isNull);
  await repo.deleteEntry(after.first.id);
  expect(await repo.entries(DateTime(2026, 11, 1), DateTime(2026, 11, 30)), hasLength(1));
}

void main() {
  final today = DateTime(2026, 11, 14);
  final nov = DateTime(2026, 11);

  test('สรุปเดือน · หมวดจ่ายมากสุด', () {
    final s = monthSummary([
      e(DateTime(2026, 11, 1), MoneyKind.income, 28500),
      e(DateTime(2026, 11, 2), MoneyKind.expense, 1680, cat: 'ค่าบริการ'),
      e(DateTime(2026, 11, 3), MoneyKind.expense, 3000, cat: 'อาหาร'),
      e(DateTime(2026, 11, 9), MoneyKind.expense, 160, cat: 'อาหาร'),
      e(DateTime(2026, 10, 31), MoneyKind.expense, 999), // เดือนอื่น
    ], nov);
    expect(s.income, 28500);
    expect(s.expense, 4840);
    expect(s.net, 23660);
    expect(s.byCategory.first, ('อาหาร', 3160));
    expect(baht(s.net), '฿23,660');
    expect(baht(-1234567), '-฿1,234,567');
  });

  test('ค่าบริการ: จ่ายแล้ว · ยอดเปลี่ยน · ใกล้ตัด · เลยกำหนด · รายปี', () {
    const adobe = Subscription(id: 1, name: 'Adobe', amount: 969, billDay: 5);
    const ai = Subscription(id: 2, name: 'AI', amount: 700, billDay: 16);
    const late = Subscription(id: 3, name: 'X', billDay: 10);
    const later = Subscription(id: 4, name: 'Y', billDay: 28);
    const yearly = Subscription(id: 5, name: 'โดเมน', amount: 600, cycle: BillCycle.yearly, billDay: 10, billMonth: 3);
    final paid = [e(DateTime(2026, 11, 5), MoneyKind.expense, 969, sub: 1)];
    expect(billState(adobe, paid, nov, today).$1, BillState.paid);
    expect(billState(adobe, [e(DateTime(2026, 11, 5), MoneyKind.expense, 1069, sub: 1)], nov, today).$1, BillState.changed);
    expect(billState(ai, paid, nov, today).$1, BillState.dueSoon);
    expect(billState(late, paid, nov, today).$1, BillState.overdue);
    expect(billState(later, paid, nov, today).$1, BillState.later);
    expect(billState(yearly, paid, nov, today).$1, BillState.notThisMonth);
    expect(billDateIn(const Subscription(name: 'z', billDay: 31), DateTime(2026, 2)), DateTime(2026, 2, 28));
    expect(subscriptionsPerMonth([adobe, ai, yearly]), 969 + 700 + 50);
  });

  test('คืนทุน: สัดส่วน · คาดเดือนคืนทุนจากรายรับ 3 เดือนล่าสุด', () {
    final inv = Investment(id: 7, name: 'คอมสตรีม', amount: 45000, startDay: DateTime(2026, 6, 1));
    final pb = paybackOf(inv, [
      e(DateTime(2026, 9, 10), MoneyKind.income, 3000, inv: 7),
      e(DateTime(2026, 10, 10), MoneyKind.income, 3000, inv: 7),
      e(DateTime(2026, 11, 10), MoneyKind.income, 3000, inv: 7),
      e(DateTime(2026, 11, 11), MoneyKind.income, 9999), // ไม่ผูก
    ], today);
    expect(pb.returned, 9000);
    expect(pb.ratio, closeTo(0.2, 1e-9));
    expect(pb.eta, DateTime(2027, 11, 1)); // เหลือ 36,000 ÷ 3,000/เดือน = 12 เดือน
    final done = paybackOf(inv, [e(DateTime(2026, 11, 1), MoneyKind.income, 50000, inv: 7)], today);
    expect(done.ratio, 1);
    expect(done.eta, isNull);
  });

  test('CSV', () {
    final csv = moneyCsv([e(DateTime(2026, 11, 2), MoneyKind.expense, 350, cat: 'เดินทาง')]);
    expect(csv.split('\n')[1], '2026-11-02,expense,350.00,เดินทาง,');
  });

  test('RAM: การเงิน', () => repoRules(MemoryWorkRepository()));

  test('SQLite v20: การเงิน · รันซ้ำได้', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
        options: OpenDatabaseOptions(onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON')));
    await createMoneyV20(db);
    await createMoneyV20(db);
    await repoRules(SqliteWorkRepository(db));
    await db.close();
  });

  testWidgets('งาน › การเงิน: จดรายจ่าย → สรุป · ค่าบริการติ๊กตัดเงินแล้ว = ลงรายจ่าย · ซ่อนเมนูในตั้งค่า', (tester) async {
    tester.view.physicalSize = const Size(1400, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('งาน').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('money-add')), findsOneWidget); // เปิดมาที่การเงิน

    await tester.tap(find.byKey(const Key('money-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('money-amount')), '350');
    await tester.tap(find.byKey(const Key('money-cat-เดินทาง')));
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('money-amount')), findsNothing, reason: 'ฟอร์มต้องปิดหลังบันทึก');
    expect(await cal.workRepo.entries(DateTime(2000), DateTime(2100)), hasLength(1));
    await tester.pumpAndSettle();
    expect((tester.widget(find.byKey(const Key('kpi-out'))) as Text).data, '฿350');

    await tester.tap(find.byKey(const Key('sub-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('sub-name')), 'Adobe');
    await tester.enterText(find.byKey(const Key('sub-amount')), '969');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    final sub = (await cal.workRepo.subscriptions()).single;
    await tester.tap(find.byKey(ValueKey('sub-paid-${sub.id}')));
    await tester.pumpAndSettle();
    expect((tester.widget(find.byKey(const Key('kpi-out'))) as Text).data, '฿1,319');
    final now = DateTime.now();
    final rows = await cal.workRepo.entries(DateTime(now.year, now.month, 1), DateTime(now.year, now.month + 1, 0));
    expect(rows.where((r) => r.subscriptionId == sub.id), hasLength(1));

    // ตั้งค่า › ปิดเมนู "งาน" → หายจากแถบเมนู · กลับหน้าแรก
    hiddenMenus.value = {'งาน'};
    await tester.pumpAndSettle();
    expect(find.text('งาน'), findsNothing);
    expect(currentTab.value, 'วันนี้');
    hiddenMenus.value = const {};
    await tester.pumpAndSettle();
    expect(find.text('งาน'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
