import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/app_database.dart';
import 'package:noir_manager/theme/app_theme.dart';
import 'package:noir_manager/theme/noir_colors.dart';
import 'package:noir_manager/work/checkin_page.dart';
import 'package:noir_manager/work/pay_calc.dart';
import 'package:noir_manager/work/work_repository.dart';

int hm(String s) {
  final [h, m] = s.split(':').map(int.parse).toList();
  return h * 60 + m;
}

/// 1 รอบเข้า–ออก (พ.ย. 2569)
WorkSession ws(int day, String a, String b, {int? comp, int? pieces}) => WorkSession(
      day: DateTime(2026, 11, day),
      startMin: hm(a),
      endMin: hm(b),
      compFor: comp == null ? null : DateTime(2026, 11, comp),
      pieces: pieces,
    );

const cfg = PayConfig(); // รายเดือน 15,000 · จ.–ส. · 8 ชม. · OT ×1.5 · ช่วงละ 30 นาที
final today = DateTime(2026, 11, 30);

MonthResult month(List<WorkSession> ss, {Map<int, AbsenceKind> abs = const {}, PayConfig c = cfg}) =>
    calcMonth(c, 2026, 11, ss, {for (final e in abs.entries) DateTime(2026, 11, e.key): e.value}, today: today);

void main() {
  test('อัตรา: 15,000 ÷ 30 = 500/วัน · 62.50/ชม. · OT 93.75 · OT วันหยุด 187.50', () {
    expect(cfg.dayRate, 500);
    expect(cfg.hourRate, 62.5);
    expect(cfg.otHour, 93.75);
    expect(cfg.holOtHour, 187.5);
    expect(money2(15421.875), '15,421.88');
    expect(hrsText(270), '4:30 ชม.');
  });

  test('ขาด จ. 16 → ทำ อา. 22 03:30–17:00 แทน (สลับวันหยุด) = ไม่หัก 500 · เกิน 8 ชม. = OT ×1.5', () {
    final d = calcDay(cfg, DateTime(2026, 11, 22), [ws(22, '03:30', '17:00', comp: 16)]);
    expect(d.worked, 750); // 13.5 ชม. − พัก 1 ชม.
    expect(d.swap, isTrue);
    expect(d.normal, 480);
    expect(d.ot, 270);
    final m = month([ws(22, '03:30', '17:00', comp: 16)], abs: {16: AbsenceKind.absent});
    expect(m.absent, isEmpty);
    expect(m.compensated, [DateTime(2026, 11, 16)]);
    expect(m.pay, closeTo(15000 + 4.5 * 93.75, 0.001)); // 15,421.88
  });

  test('ทำวันหยุดเพิ่มเฉย ๆ (ไม่ได้แทนวันไหน) = อัตราวันหยุด ×1 · OT วันหยุด ×3', () {
    final m = month([ws(22, '03:30', '17:00')], abs: {16: AbsenceKind.absent});
    expect(m.absent, [DateTime(2026, 11, 16)]);
    expect(m.holN, 480);
    expect(m.holOT, 270);
    expect(m.pay, closeTo(15000 - 500 + 500 + 843.75, 0.001)); // 15,843.75
  });

  test('เข้าสาย 09:00: เลิก 18:00 = ไม่หัก · เลิก 17:00 = หัก 1 ชม. · ขาดไม่ถึง 30 นาที = ไม่หัก', () {
    expect(finishAt(cfg, hm('09:00')), hm('18:00'));
    expect(finishAt(cfg, hm('09:00'), extraMin: 60), hm('19:00'));
    expect(month([ws(24, '09:00', '18:00')]).pay, 15000);
    expect(month([ws(24, '09:00', '17:00')]).pay, closeTo(15000 - 62.5, 0.001));
    expect(month([ws(24, '09:00', '17:50')]).pay, 15000);
    expect(month([ws(24, '09:00', '17:30')]).pay, closeTo(15000 - 31.25, 0.001));
  });

  test('OT นับช่วงละ 30 นาที ปัดลง: เกิน 20 นาที = 0 · เกิน 40 นาที = 30 นาที', () {
    expect(calcDay(cfg, DateTime(2026, 11, 24), [ws(24, '08:00', '17:20')]).ot, 0);
    expect(calcDay(cfg, DateTime(2026, 11, 24), [ws(24, '08:00', '17:40')]).ot, 30);
    expect(calcDay(cfg, DateTime(2026, 11, 24), [ws(24, '08:00', '17:40')]).otRaw, 40);
  });

  test('OT ชดเชยชั่วโมงที่ขาดของอีกวันได้ (1:1) · เหลือค่อยจ่าย ×1.5', () {
    // จ. ขาด 1 ชม. · อ. OT 1 ชม. → ลบกันเป็น 0
    expect(month([ws(23, '08:00', '16:00'), ws(24, '08:00', '18:00')]).pay, 15000);
    // ขาด 30 นาที · OT 1:30 → เหลือ OT 1 ชม.
    final m = month([ws(23, '08:00', '16:30'), ws(24, '08:00', '18:30')]);
    expect(m.bank, 60);
    expect(m.pay, closeTo(15093.75, 0.001));
  });

  test('วันทำงานที่ไม่มีเช็คอิน = ยังไม่ระบุ (ไม่หักเงินเงียบ ๆ) · ลาได้เงิน / วันหยุดพิเศษ = ไม่หัก', () {
    final m = month([], abs: {2: AbsenceKind.leave, 3: AbsenceKind.off, 4: AbsenceKind.absent});
    expect(m.unresolved, isNot(contains(DateTime(2026, 11, 2))));
    expect(m.unresolved, contains(DateTime(2026, 11, 5)));
    expect(m.unresolved, isNot(contains(DateTime(2026, 11, 1)))); // อาทิตย์ = วันหยุด
    expect(m.unresolved, isNot(contains(today))); // วันนี้ยังไม่จบ
    expect(m.pay, 14500);
  });

  test('รายวัน / รายชั่วโมง / ตามชิ้นงาน / เงินเพิ่ม-หัก', () {
    final daily = cfg.copyWith(type: PayType.daily);
    // 8 ชม. + OT 1 ชม. · อา. 8 ชม. (วันหยุด ×2)
    final m = month([ws(24, '08:00', '18:00'), ws(22, '08:00', '17:00')], c: daily);
    expect(m.pay, closeTo(500 + 93.75 + 1000, 0.001));
    final hourly = cfg.copyWith(type: PayType.hourly, hourly: 50);
    expect(month([ws(24, '08:00', '13:00')], c: hourly).pay, 250);
    final piece = cfg.copyWith(type: PayType.piece, piece: 30);
    expect(month([ws(23, '08:00', '17:00', pieces: 10), ws(24, '08:00', '12:00', pieces: 4)], c: piece).pay, 420);
    final ex = cfg.copyWith(extras: const [PayExtra('เบี้ยขยัน', 500), PayExtra('ประกันสังคม', -750)]);
    expect(month([], c: ex).pay, 15000 + 500 - 750);
  });

  test('ตั้งค่าค่าจ้าง: เก็บ → อ่านกลับได้ครบ · อ่านไม่ได้ = ค่าตั้งต้น', () {
    final c = cfg.copyWith(type: PayType.daily, daily: 520, workDays: {1, 2, 3, 4, 5}, extras: const [PayExtra('ค่าเดินทาง', 300)]);
    final back = PayConfig.decode(c.encode());
    expect(back.type, PayType.daily);
    expect(back.daily, 520);
    expect(back.workDays, {1, 2, 3, 4, 5});
    expect(back.extras.single.name, 'ค่าเดินทาง');
    expect(PayConfig.decode('{พัง').type, PayType.monthly);
    expect(PayConfig.decode(null).monthly, 15000);
  });

  Future<void> repoRules(WorkRepository r) async {
    final id = await r.saveWorkSession(WorkSession(day: DateTime(2026, 11, 24), startMin: hm('09:00')));
    var ss = await r.workSessions(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    expect(ss.single.open, isTrue);
    await r.saveWorkSession(ss.single.copyWith(endMin: hm('18:00')));
    await r.saveWorkSession(ws(22, '03:30', '17:00', comp: 16));
    ss = await r.workSessions(DateTime(2026, 11, 1), DateTime(2026, 11, 30));
    expect(ss.map((s) => s.day.day), [22, 24]);
    expect(ss.firstWhere((s) => s.id == id).endMin, hm('18:00'));
    expect(ss.first.compFor, DateTime(2026, 11, 16));
    await r.setAbsence(DateTime(2026, 11, 16), AbsenceKind.absent);
    await r.setAbsence(DateTime(2026, 11, 17), AbsenceKind.leave);
    await r.setAbsence(DateTime(2026, 11, 17), null);
    expect(await r.absences(DateTime(2026, 11, 1), DateTime(2026, 11, 30)), {DateTime(2026, 11, 16): AbsenceKind.absent});
    await r.deleteWorkSession(id);
    expect((await r.workSessions(DateTime(2026, 11, 1), DateTime(2026, 11, 30))).length, 1);
    expect((await r.payConfig()).type, PayType.monthly);
    await r.savePayConfig(cfg.copyWith(type: PayType.hourly, hourly: 80));
    expect((await r.payConfig()).hourly, 80);
  }

  test('RAM: เช็คอิน', () => repoRules(MemoryWorkRepository()));

  test('SQLite v25: เช็คอิน · ตารางใหม่ + ตั้งค่าใน setting', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await createAllTables(db);
    await createCheckinV25(db); // รันซ้ำได้
    await repoRules(SqliteWorkRepository(db));
    await db.close();
  });

  testWidgets('งาน › เข้างาน: กดเข้างาน 09:00 → บอกเวลาเลิก 18:00 → กดเลิก 18:00 → ค่าจ้างเท่าเงินเดือน', (tester) async {
    tester.view.physicalSize = const Size(1300, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    var now = DateTime(2026, 11, 24, 9, 0);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(themeChoices.first),
      home: CalendarScope(repository: cal, child: Scaffold(body: CheckinView(clock: () => now))),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkin-in')), findsOneWidget);
    expect(find.byKey(const Key('checkin-list')), findsOneWidget); // คอม: 2 ฝั่ง
    expect(find.byKey(const Key('checkin-unresolved')), findsOneWidget); // ต้นเดือนยังไม่มีเช็คอิน

    await tester.tap(find.byKey(const Key('checkin-in')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkin-out')), findsOneWidget);
    expect(find.textContaining('เลิกได้ '), findsOneWidget);
    expect(find.textContaining('18:00', findRichText: true), findsWidgets);

    now = DateTime(2026, 11, 24, 18, 0);
    await tester.tap(find.byKey(const Key('checkin-out')));
    await tester.pumpAndSettle();
    final s = (await cal.workRepo.workSessions(DateTime(2026, 11, 24), DateTime(2026, 11, 24))).single;
    expect(s.endMin, hm('18:00'));
    expect(find.byKey(const Key('checkin-in')), findsOneWidget); // เข้างานอีกรอบได้

    // ตอบวันที่ไม่มีเช็คอิน 1 วัน = ลาได้เงิน
    await tester.tap(find.byKey(const Key('abs-23-leave')));
    await tester.pumpAndSettle();
    expect((await cal.workRepo.absences(DateTime(2026, 11, 23), DateTime(2026, 11, 23))).values.single, AbsenceKind.leave);

    // ตั้งค่า → เปลี่ยนเป็นรายชั่วโมง
    await tester.tap(find.text('ตั้งค่า'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkin-settings')), findsOneWidget);
    await tester.tap(find.text('รายชั่วโมง'));
    await tester.pumpAndSettle();
    expect((await cal.workRepo.payConfig()).type, PayType.hourly);
    await tester.pump(const Duration(seconds: 8)); // ให้แจ้งเตือนหายเอง
    expect(tester.takeException(), isNull);
  });

  testWidgets('มือถือ: แท็บ วันนี้ / เดือนนี้ / ตั้งค่า · ปุ่มเข้างานใหญ่กดง่าย', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(themeChoices.first),
      home: CalendarScope(repository: cal, child: Scaffold(body: CheckinView(clock: () => DateTime(2026, 11, 24, 8, 20)))),
    ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const Key('checkin-in'))).height, greaterThanOrEqualTo(56));
    expect(find.byKey(const Key('checkin-list')), findsNothing);
    await tester.tap(find.text('เดือนนี้'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('checkin-list')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
