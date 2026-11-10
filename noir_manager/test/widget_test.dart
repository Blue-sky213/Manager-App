import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/shell/app_nav.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_repository.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/pages/calendar_page.dart' show addMonths, monthGridDays;
import 'package:noir_manager/utils/thai_date.dart';

/// เปิดแอปด้วยข้อมูลใน RAM (ไม่แตะไฟล์ฐานข้อมูลจริง)
Widget buildApp({CalendarRepository? calendar}) => NoirManagerApp(
      studyRepository: MemoryStudyRepository.seeded(),
      calendarRepository: calendar ?? MemoryCalendarRepository(),
    );

void setScreen(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('จอกว้าง: มี Sidebar, กดเมนูแล้วเปลี่ยนหน้า, สลับธีมได้',
      (tester) async {
    setScreen(tester, const Size(1280, 820));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Noir Manager'), findsOneWidget);
    expect(find.text('โหมดสว่าง'), findsOneWidget);

    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    expect(find.text('Study Tree'), findsOneWidget);

    await tester.tap(find.text('โหมดสว่าง'));
    await tester.pumpAndSettle();
    expect(find.text('โหมดมืด'), findsOneWidget);
  });

  testWidgets('จอแคบ: ใช้ Bottom bar แทน Sidebar', (tester) async {
    setScreen(tester, const Size(420, 640));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
  });

  testWidgets('หน้าวิชา: แสดง DaVinci และบันทึกคะแนนหัวข้อย่อยได้',
      (tester) async {
    setScreen(tester, const Size(1280, 2600)); // หน้าวิชายาวขึ้น (การ์ดตารางเรียน + รอบติว)
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา')); // หน้าวิชาเปิดที่แผนผังก่อน → สลับไปรายละเอียด
    await tester.pumpAndSettle();

    expect(find.text('DaVinci Resolve'), findsWidgets);
    // หน้าวิชาเปิดที่แท็บภาพรวม → ไปแท็บบทเรียน
    expect(find.text('ภาพรวม'), findsOneWidget);
    await tester.tap(find.text('บทเรียน').first);
    await tester.pumpAndSettle();
    expect(find.text('บท 1 · Interface & Media'), findsOneWidget);
    expect(find.text('ประเมินแล้ว 0/4 หัวข้อ'), findsOneWidget);

    // แตะหัวข้อย่อย → กรอก 55 → บันทึก
    await tester.tap(find.text('1.4 Keyboard Shortcut'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('score-field')), '55');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();

    expect(find.text('55%'), findsWidgets); // แถวหัวข้อ + วงกลมบนหัววิชา
    expect(find.text('ประเมินแล้ว 1/4 หัวข้อ'), findsOneWidget);
    expect(find.text('เช็กซ้ำ'), findsOneWidget); // ต่ำกว่า 60 → ป้ายเช็กซ้ำ
    // แท็บภาพรวม: กล่องทวน
    await tester.tap(find.text('ภาพรวม'));
    await tester.pumpAndSettle();
    expect(find.text('ต้องทวนก่อนสอบ · 1 หัวข้อ'), findsOneWidget);
    expect(find.text('1.4 Keyboard Shortcut'), findsOneWidget);
  });

  testWidgets('หน้าวิชาใช้งานได้ที่ขนาดหน้าต่างเล็กสุด 420x640', (tester) async {
    setScreen(tester, const Size(420, 640));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('การเรียน').last); // ปุ่มใน Bottom bar
    await tester.pumpAndSettle();

    expect(find.text('Study Tree'), findsOneWidget);
    expect(tester.takeException(), isNull); // ไม่มี error ล้นจอ
  });

  testWidgets('แตะหัวบท = ยุบ / ขยาย และปุ่มยุบทุกบท', (tester) async {
    setScreen(tester, const Size(1280, 2600)); // หน้าวิชายาวขึ้น (การ์ดตารางเรียน + รอบติว)
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา')); // หน้าวิชาเปิดที่แผนผังก่อน → สลับไปรายละเอียด
    await tester.pumpAndSettle();
    await tester.tap(find.text('บทเรียน').first);
    await tester.pumpAndSettle();

    expect(find.text('1.4 Keyboard Shortcut'), findsOneWidget);
    await tester.tap(find.text('บท 1 · Interface & Media'));
    await tester.pumpAndSettle();
    expect(find.text('1.4 Keyboard Shortcut'), findsNothing); // ยุบแล้ว

    await tester.tap(find.text('บท 1 · Interface & Media'));
    await tester.pumpAndSettle();
    expect(find.text('1.4 Keyboard Shortcut'), findsOneWidget); // ขยายกลับ

    await tester.tap(find.text('ยุบทุกบท'));
    await tester.pumpAndSettle();
    expect(find.text('1.4 Keyboard Shortcut'), findsNothing);
    expect(find.text('ขยายทุกบท'), findsOneWidget);
  });

  testWidgets('หน้าวันนี้: เห็นงาน + ชั่วโมงนอน · ยกเลิกต้องใส่เหตุผล', (tester) async {
    setScreen(tester, const Size(1280, 1400));
    final calendar = MemoryCalendarRepository();
    await calendar.addActivity(NewActivity(
      name: 'วิ่ง 5K',
      categoryId: 2,
      importance: 3,
      timed: true,
      day: DateTime.now(),
      startMinute: 17 * 60,
      durationMin: 45,
    ));

    await tester.pumpWidget(buildApp(calendar: calendar));
    await tester.pumpAndSettle();

    expect(find.text('วิ่ง 5K'), findsOneWidget);
    expect(find.text('7.5 ชม.'), findsOneWidget); // นอน 23:30 → ตื่น 07:00
    expect(find.text('ไม่มีงานค้าง'), findsOneWidget);

    await tester.longPress(find.text('วิ่ง 5K')); // ตัวเลือกอยู่ที่คลิกขวา / กดค้าง
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยกเลิก (ต้องใส่เหตุผล)'));
    await tester.pumpAndSettle();

    // ยังไม่ใส่เหตุผล → ปุ่มยืนยันกดไม่ได้
    final confirm = find.widgetWithText(FilledButton, 'ยืนยันยกเลิก');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);

    await tester.enterText(find.byKey(const Key('reason-field')), 'ฝนตก');
    await tester.pump();
    await tester.tap(confirm);
    await tester.pumpAndSettle();

    expect(find.textContaining('ยกเลิก: ฝนตก'), findsOneWidget);
  });

  testWidgets('หน้าวันนี้ใช้งานได้ที่ 420x640', (tester) async {
    setScreen(tester, const Size(420, 640));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    expect(find.text('Updates'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('แก้ไขงาน: เปลี่ยนชื่อแล้วหน้าวันนี้เห็นชื่อใหม่', (tester) async {
    setScreen(tester, const Size(1280, 1400));
    final calendar = MemoryCalendarRepository();
    await calendar.addActivity(NewActivity(
      name: 'RE4',
      categoryId: 3,
      importance: 3,
      timed: true,
      day: DateTime.now(),
      startMinute: 20 * 60,
      durationMin: 240,
    ));
    await tester.pumpWidget(buildApp(calendar: calendar));
    await tester.pumpAndSettle();

    await tester.longPress(find.text('RE4'));
    await tester.pumpAndSettle();
    expect(find.text('แก้เวลาเฉพาะวันนี้'), findsOneWidget);
    await tester.tap(find.text('แก้ไขงาน'));
    await tester.pumpAndSettle();

    expect(find.text('เวลาจบ'), findsOneWidget);
    expect(find.text('00:00'), findsWidgets); // 20:00 + 4 ชม.
    await tester.enterText(find.byKey(const Key('activity-name')), 'Minecraft');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();

    expect(find.text('Minecraft'), findsWidgets);
    expect(find.text('RE4'), findsNothing);
  });

  testWidgets('ฟอร์มเพิ่มงาน + เลือกวันเอง ใช้ได้ที่ 420x640', (tester) async {
    setScreen(tester, const Size(420, 640));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มงาน').first);
    await tester.pumpAndSettle();
    // จอเตี้ย 640: ปุ่มอยู่ใต้ขอบ ต้องเลื่อนฟอร์มลงก่อน (ไม่งั้นแตะพลาด)
    await tester.ensureVisible(find.text('เลือกวันเอง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เลือกวันเอง'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มวัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('ตารางเดือน: เริ่มจันทร์ จบอาทิตย์ · เลื่อนเดือนไม่ล้นวัน', () {
    final days = monthGridDays(DateTime(2026, 11, 4));
    expect(days.first, DateTime(2026, 10, 26)); // จันทร์
    expect(days.last, DateTime(2026, 12, 6)); // อาทิตย์
    expect(days.length % 7, 0);
    expect(addMonths(DateTime(2026, 1, 31), 1), DateTime(2026, 2, 28));
    expect(addMonths(DateTime(2026, 11, 4), -12), DateTime(2025, 11, 4));
  });

  testWidgets('ปฏิทิน: สลับ วัน / สัปดาห์ / เดือน / ปี ได้ที่ 420x640', (tester) async {
    setScreen(tester, const Size(420, 640));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน').first);
    await tester.pumpAndSettle();

    final now = DateTime.now();
    // มุมมองเป็นดรอปดาวน์: แตะค่าปัจจุบัน → เลือกค่าใหม่
    await tester.tap(find.text('สัปดาห์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('เดือน').last);
    await tester.pumpAndSettle();
    expect(find.text(thaiMonthYear(now)), findsOneWidget);

    await tester.tap(find.text('เดือน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปี').last);
    await tester.pumpAndSettle();
    expect(find.text('พ.ศ. ${buddhistYear(now)}'), findsOneWidget);

    // แตะหัว พ.ศ. → ตารางปี → เลือกปีถัดไป
    await tester.tap(find.text('พ.ศ. ${buddhistYear(now)}'));
    await tester.pumpAndSettle();
    final from = buddhistYear(now) ~/ 10 * 10;
    expect(find.text('พ.ศ. $from – ${from + 15}'), findsOneWidget);
    await tester.tap(find.text('${buddhistYear(now) + 1}'));
    await tester.pumpAndSettle();
    expect(find.text('พ.ศ. ${buddhistYear(now) + 1}'), findsOneWidget);
    await tester.tap(find.text('มกราคม'));
    await tester.pumpAndSettle();
    expect(find.text(thaiMonthYear(DateTime(now.year + 1, 1))), findsOneWidget);

    await tester.tap(find.text('เดือน').first); // แตะมกราคม → กลับมามุมมองเดือน
    await tester.pumpAndSettle();
    await tester.tap(find.text('วัน').last);
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มงาน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('มุมมองสัปดาห์: เลือกแบบ ตารางเวลา / ลิสต์ / การ์ด จากดรอปดาวน์ (จอกว้าง)', (tester) async {
    setScreen(tester, const Size(1280, 1000));
    final calendar = MemoryCalendarRepository();
    await calendar.addActivity(NewActivity(
      name: 'วิ่ง',
      categoryId: 2,
      importance: 2,
      timed: true,
      day: DateTime.now(),
      startMinute: 17 * 60,
      durationMin: 45,
    ));
    await tester.pumpWidget(buildApp(calendar: calendar));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ปฏิทิน').first);
    await tester.pumpAndSettle();

    expect(find.text('ตารางเวลา'), findsOneWidget);
    await tester.tap(find.text('ตารางเวลา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลิสต์').last);
    await tester.pumpAndSettle();
    expect(find.text('17:00–17:45 · วิ่ง'), findsOneWidget);
    expect(find.text('45 นาที'), findsOneWidget); // ชั่วโมงรวมของวัน

    await tester.tap(find.text('ลิสต์').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('การ์ด').last);
    await tester.pumpAndSettle();
    expect(find.text('วิ่ง'), findsOneWidget);
    expect(find.text('17:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('แผนผังแผนการเรียน: ใส่แผน 4 ปี → เห็นทุกปี + 125 หน่วยกิต → แตะเปิดวิชา',
      (tester) async {
    // จอสูง: ListView สร้างเฉพาะส่วนที่อยู่ในจอ บทที่ 1 อยู่ใต้การ์ดตารางเรียน
    setScreen(tester, const Size(1280, 2400));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();

    expect(find.text('การเรียน'), findsWidgets);
    await tester.tap(find.byTooltip('ตัวเลือก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใส่ตัวอย่าง: แผน 4 ปี'));
    await tester.pumpAndSettle();

    expect(find.text('ปีการศึกษาที่ 1'), findsOneWidget);
    expect(find.text('ปีการศึกษาที่ 4'), findsOneWidget);
    expect(find.text('จำนวนหน่วยกิตตลอดหลักสูตร 125 หน่วยกิต'), findsOneWidget);

    // กดค้าง (= คลิกขวา) → เมนูตัวเลือก → ไฮไลต์สาย (ยังอยู่หน้าแผนผัง)
    final prog = find.text('การเขียนโปรแกรมคอมพิวเตอร์');
    await tester.longPress(prog);
    await tester.pumpAndSettle();
    expect(find.text('ลบวิชา'), findsOneWidget);
    await tester.tap(find.text('ไฮไลต์สายวิชานี้'));
    await tester.pumpAndSettle();
    expect(find.text('ปีการศึกษาที่ 1'), findsOneWidget);
    expect(find.textContaining('ไฮไลต์สาย "การเขียนโปรแกรมคอมพิวเตอร์"'), findsOneWidget);
    // คลิกซ้าย = เปิดทันที · มีปุ่มกลับแผน 4 ปี
    await tester.tap(prog);
    await tester.pumpAndSettle();
    expect(find.text('กลับแผน 4 ปี'), findsOneWidget);

    // หน้ารายวิชาเปิดที่ปี 1 → เห็นเฉพาะวิชาปี 1 ไม่มีวิชาปี 2 ปนมา
    expect(find.textContaining('ปี 1 ·'), findsOneWidget);
    expect(find.text('คณิตศาสตร์วิศวกรรม 1'), findsNothing);
    await tester.tap(find.textContaining('ปี 2 ·'));
    await tester.pumpAndSettle();
    expect(find.text('คณิตศาสตร์วิศวกรรม 1'), findsOneWidget);
    await tester.tap(find.textContaining('ปี 1 ·'));
    await tester.pumpAndSettle();
    // แท็บบทเรียน → เลื่อนหาบทแรก (รายชื่อวิชาซ้ายก็เลื่อนได้ → ใช้ตัวเลื่อนของเนื้อหา = ตัวสุดท้าย)
    await tester.tap(find.text('บทเรียน').first);
    await tester.pumpAndSettle();
    final chapter1 = find.text('บท 1 · อัลกอริทึมและผังงาน [กลางภาค]');
    await tester.scrollUntilVisible(
      chapter1,
      300,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .last,
    );
    expect(chapter1, findsOneWidget);
    expect(find.text('ตารางเรียน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('แผนผัง: แตะหัวปี → ดูทั้งปี · แตะหัวภาค → ดูภาคเดียว · ชิปพากลับ',
      (tester) async {
    setScreen(tester, const Size(1280, 2400));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตัวเลือก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใส่ตัวอย่าง: แผน 4 ปี'));
    await tester.pumpAndSettle();

    // หัวปี → ปี 2 อย่างเดียว เห็นทั้ง 2 เทอม ไม่มีวิชาปี 1
    await tester.tap(find.text('ปีการศึกษาที่ 2'));
    await tester.pumpAndSettle();
    expect(find.text('การเรียน · ปี 2'), findsOneWidget);
    expect(find.textContaining('ปีการศึกษาที่ 2 ·'), findsOneWidget);
    expect(find.text('ปีการศึกษาที่ 1'), findsNothing);
    expect(find.text('ภาคเรียนที่ 1'), findsOneWidget);
    expect(find.text('ภาคเรียนที่ 2'), findsOneWidget);
    expect(find.text('คณิตศาสตร์วิศวกรรม 1'), findsOneWidget);
    expect(find.text('คณิตศาสตร์วิศวกรรม 2'), findsOneWidget);
    expect(find.text('กระบวนการคิดเชิงออกแบบ'), findsNothing); // ปี 1 ไม่มีเส้นต่อ → ไม่โผล่
    // วิชาปีอื่นที่มีเส้นต่อ → คอลัมน์เงา ซ้าย = ต้องเรียนก่อน · ขวา = ต่อยอด
    expect(find.text('← ต้องเรียนก่อน'), findsOneWidget);
    expect(find.text('การเขียนโปรแกรมคอมพิวเตอร์'), findsOneWidget);
    expect(find.text('ต่อยอดไป →'), findsOneWidget);
    expect(find.text('การฝึกงาน'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // ในปี 2 แตะหัวภาค 2 → เหลือภาค 2 อย่างเดียว
    await tester.tap(find.text('ภาคเรียนที่ 2'));
    await tester.pumpAndSettle();
    expect(find.text('การเรียน · ปี 2 · ภาค 2'), findsOneWidget);
    expect(find.text('คณิตศาสตร์วิศวกรรม 2'), findsOneWidget);
    // คณิต 1 (ภาค 1) เหลือแค่กล่องเงาบอกว่าอยู่ภาคไหน
    expect(find.text('ปี 2 · ภาค 1'), findsWidgets);
    expect(find.text('สถาปัตยกรรมคอมพิวเตอร์และระบบปฏิบัติการ'), findsOneWidget);
    expect(find.text('เครือข่ายขั้นสูงและโปรโตคอล'), findsNothing); // ภาค 1 ไม่มีเส้นมาภาค 2
    // ชิป "ทั้งปี" → กลับมาเห็น 2 ภาค
    await tester.tap(find.widgetWithText(ChoiceChip, 'ทั้งปี'));
    await tester.pumpAndSettle();
    expect(find.text('การเรียน · ปี 2'), findsOneWidget);
    expect(find.text('คณิตศาสตร์วิศวกรรม 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // แตะกล่องเงา "การฝึกงาน" (ปี 3) → ไปดูปี 3
    await tester.tap(find.text('การฝึกงาน'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('การเรียน · ปี 3'), findsOneWidget);

    // กลับทุกปี → แตะหัวภาคแรกสุด (ปี 1 ภาค 1) → ไปภาคนั้นตรง ๆ
    await tester.tap(find.widgetWithText(ChoiceChip, 'ทุกปี'));
    await tester.pumpAndSettle();
    expect(find.text('ปีการศึกษาที่ 4'), findsOneWidget);
    await tester.tap(find.text('ภาคเรียนที่ 1').first);
    await tester.pumpAndSettle();
    expect(find.text('การเรียน · ปี 1 · ภาค 1'), findsOneWidget);
    expect(find.text('การเขียนโปรแกรมคอมพิวเตอร์'), findsOneWidget);
    expect(find.text('การแก้ปัญหาและขั้นตอนวิธี'), findsNothing); // ปี 1 ภาค 2

    // คลิกเปิดวิชาในมุมมองภาคเดียว → กลับแผน 4 ปีแล้วยังอยู่ที่ปี 1 ภาค 1
    await tester.tap(find.text('การเขียนโปรแกรมคอมพิวเตอร์'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ปี 1 ·'), findsOneWidget);
    await tester.tap(find.text('กลับแผน 4 ปี'));
    await tester.pumpAndSettle();
    expect(find.text('การเรียน · ปี 1 · ภาค 1'), findsOneWidget);
  });

  testWidgets('แตะวันสอบในหน้าวิชา → ไปวันนั้นในปฏิทิน', (tester) async {
    setScreen(tester, const Size(1280, 2400));
    final cal = MemoryCalendarRepository();
    final examDay = DateTime(2026, 12, 21);
    await cal.addActivity(NewActivity(
      name: 'สอบกลางภาค · DaVinci',
      categoryId: 1,
      importance: 3,
      timed: true,
      day: examDay,
      startMinute: 13 * 60,
      durationMin: 180,
      subjectId: 1,
      kind: ActivityKind.exam,
    ));
    await tester.pumpWidget(buildApp(calendar: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('เวลาเรียน').first); // แท็บเวลาเรียน
    await tester.pumpAndSettle();
    final exam = find.textContaining('สอบกลางภาค · ${thaiShortDate(examDay)}').last;
    await tester.scrollUntilVisible(
      exam,
      300,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .last,
    );
    // คลิกขวา (กดค้าง) = เมนู
    await tester.longPress(exam);
    await tester.pumpAndSettle();
    expect(find.text('แก้วัน / เวลาสอบ'), findsOneWidget);
    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    // คลิกซ้าย = ไปวันนั้นในปฏิทินเลย
    await tester.tap(exam);
    await tester.pumpAndSettle();

    // สลับมาเมนูปฏิทิน มุมมองวัน ที่วันสอบ
    final dayTitle = find.text('${thaiShortDate(examDay)} ${buddhistYear(examDay)}');
    expect(dayTitle, findsWidgets);

    // คลิกวันสอบในปฏิทิน (ผูกวิชา) → ไปหน้าวิชา · ย้อนกลับ (เมาส์ปุ่ม 4) → กลับปฏิทิน
    await tester.tap(find.textContaining('สอบกลางภาค · DaVinci').first);
    await tester.pumpAndSettle();
    expect(find.text('กลับหน้าเดิม'), findsOneWidget);
    appBack.handle();
    await tester.pumpAndSettle();
    expect(dayTitle, findsWidgets);
    expect(find.text('กลับหน้าเดิม'), findsNothing);
    // ย้อนอีกครั้ง → กลับหน้าวิชาที่มาตอนแรก
    appBack.handle();
    await tester.pumpAndSettle();
    expect(find.text('รายวิชา'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('แผนผัง: กล่องวิชาสูงเท่ากัน · เลือกวิชา → แก้เส้นเชื่อม เห็นวิชาที่ต้องเรียนก่อน',
      (tester) async {
    setScreen(tester, const Size(1280, 2400));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตัวเลือก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใส่ตัวอย่าง: แผน 4 ปี'));
    await tester.pumpAndSettle();

    // ทุกกล่องสูงเท่ากัน ไม่ว่าชื่อยาว 1 หรือ 2 บรรทัด
    final boxes = find.byWidgetPredicate((w) => w.runtimeType.toString() == '_SubjectBox');
    final heights = {for (final e in boxes.evaluate()) tester.getSize(find.byWidget(e.widget)).height};
    expect(boxes.evaluate().length, greaterThan(10));
    expect(heights, hasLength(1));

    // ปี 2 ภาค 2 · เลือก "คณิตศาสตร์วิศวกรรม 2" → ปุ่มแก้เส้น → คณิต 1 ถูกติ๊กเป็นวิชาที่ต้องเรียนก่อน
    await tester.tap(find.text('ปีการศึกษาที่ 2'));
    await tester.pumpAndSettle();
    Future<void> openLinks() async {
      await tester.longPress(find.text('คณิตศาสตร์วิศวกรรม 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('แก้เส้นเชื่อม'));
      await tester.pumpAndSettle();
    }

    await openLinks();
    expect(find.text('ต้องเรียนก่อนวิชานี้'), findsOneWidget);
    final m1 = find.ancestor(
        of: find.descendant(of: find.byType(AlertDialog), matching: find.text('คณิตศาสตร์วิศวกรรม 1')),
        matching: find.byType(CheckboxListTile));
    expect(tester.widget<CheckboxListTile>(m1).value, isTrue);

    // เอาติ๊กออก → บันทึก → เปิดใหม่ไม่ติ๊กแล้ว
    await tester.tap(m1);
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();
    await openLinks();
    expect(tester.widget<CheckboxListTile>(m1).value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('หน้าวันนี้: คลิกซ้าย = แผ่นรายละเอียด · กดค้าง (คลิกขวา) = เมนูตรงตำแหน่ง', (tester) async {
    setScreen(tester, const Size(1280, 1400));
    final calendar = MemoryCalendarRepository();
    await calendar.addActivity(NewActivity(
      name: 'อ่านหนังสือ',
      categoryId: 1,
      importance: 2,
      timed: true,
      day: DateTime.now(),
      startMinute: 20 * 60,
      durationMin: 60,
    ));
    await tester.pumpWidget(buildApp(calendar: calendar));
    await tester.pumpAndSettle();

    // กดค้าง → เมนู (ไม่มีแผ่นล่างที่มีชื่องานเป็นหัว)
    await tester.longPress(find.text('อ่านหนังสือ'));
    await tester.pumpAndSettle();
    expect(find.text('ทำแล้ว'), findsOneWidget);
    expect(find.text('ลบงานนี้'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    await tester.tap(find.text('ทำแล้ว'));
    await tester.pumpAndSettle();
    expect(find.textContaining('ทำแล้ว 1/1'), findsOneWidget);

    // คลิกซ้าย → แผ่นรายละเอียด
    await tester.tap(find.text('อ่านหนังสือ'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('หน้าวิชาใหม่: รายชื่อซ้าย เทอมนี้ / ปี / ทั้งหมด · 4 แท็บ · แผนผังเลือกสีกล่อง', (tester) async {
    setScreen(tester, const Size(1400, 2000));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ตัวเลือก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใส่ตัวอย่าง: แผน 4 ปี'));
    await tester.pumpAndSettle();

    // แผนผัง: สลับเป็นสีวิชา (จำไว้)
    await tester.tap(find.text('สีวิชา'));
    await tester.pumpAndSettle();
    expect(tester.widget<SegmentedButton<bool>>(find.byType(SegmentedButton<bool>).last).selected, {true});

    // เปิดวิชาจากแผนผัง → รายชื่อซ้ายเป็น "ปีการศึกษา" ของวิชานั้น
    await tester.tap(find.text('การเขียนโปรแกรมคอมพิวเตอร์'));
    await tester.pumpAndSettle();
    expect(find.text('ภาค 1'), findsOneWidget);
    expect(find.text('ภาค 2'), findsOneWidget);
    expect(find.text('คณิตศาสตร์วิศวกรรม 1'), findsNothing); // ปี 2

    // เทอมนี้ (ตัวอย่างตั้งเทอม ปี 1 ภาค 1 ไว้แล้ว)
    await tester.tap(find.text('เทอมนี้'));
    await tester.pumpAndSettle();
    expect(find.text('ปี 1 · ภาค 1 (เทอมนี้)'), findsOneWidget);
    expect(find.text('การแก้ปัญหาและขั้นตอนวิธี'), findsNothing); // ปี 1 ภาค 2

    // ทั้งหมด → แบ่งกลุ่มตามปี·ภาค (รายชื่อยาว สร้างเฉพาะที่อยู่บนจอ → เช็กกลุ่มต้น ๆ)
    await tester.tap(find.text('ทั้งหมด'));
    await tester.pumpAndSettle();
    expect(find.text('ปี 1 · ภาค 2'), findsOneWidget);
    expect(find.text('ปี 1 · ภาค 1 (เทอมนี้)'), findsNothing);

    // 4 แท็บ
    for (final tab in ['บทเรียน', 'ตารางเรียน', 'ติว', 'ภาพรวม']) {
      await tester.tap(find.text(tab).first);
      await tester.pumpAndSettle();
    }
    expect(find.text('หน่วยกิต'), findsOneWidget); // ช่องสรุปในภาพรวม
    expect(tester.takeException(), isNull);
  });
}
