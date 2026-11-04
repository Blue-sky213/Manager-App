import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
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

    await tester.tap(find.text('วิชา').first);
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
    setScreen(tester, const Size(1280, 1400));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('วิชา').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา')); // หน้าวิชาเปิดที่แผนผังก่อน → สลับไปรายละเอียด
    await tester.pumpAndSettle();

    expect(find.text('DaVinci Resolve'), findsWidgets);
    expect(find.text('บท 1 · Interface & Media'), findsOneWidget);
    expect(find.text('ประเมินแล้ว 0/4 หัวข้อ'), findsOneWidget);

    // แตะหัวข้อย่อย → กรอก 55 → บันทึก
    await tester.tap(find.text('1.4 Keyboard Shortcut'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('score-field')), '55');
    await tester.tap(find.text('บันทึก'));
    await tester.pumpAndSettle();

    expect(find.text('55%'), findsOneWidget);
    // กล่องทวน: หัวข้อแยกบรรทัด ไม่มีคะแนน → ชื่อหัวข้อขึ้น 2 ที่ (การ์ดบท + กล่องทวน)
    expect(find.text('ต้องทวนก่อนสอบ · 1 หัวข้อ'), findsOneWidget);
    expect(find.text('1.4 Keyboard Shortcut'), findsNWidgets(2));
    expect(find.text('เช็กซ้ำ'), findsOneWidget); // ต่ำกว่า 60 → ป้ายเช็กซ้ำ
    expect(find.text('ประเมินแล้ว 1/4 หัวข้อ'), findsOneWidget);
  });

  testWidgets('หน้าวิชาใช้งานได้ที่ขนาดหน้าต่างเล็กสุด 420x640', (tester) async {
    setScreen(tester, const Size(420, 640));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.tap(find.text('วิชา').last); // ปุ่มใน Bottom bar
    await tester.pumpAndSettle();

    expect(find.text('Study Tree'), findsOneWidget);
    expect(tester.takeException(), isNull); // ไม่มี error ล้นจอ
  });

  testWidgets('แตะหัวบท = ยุบ / ขยาย และปุ่มยุบทุกบท', (tester) async {
    setScreen(tester, const Size(1280, 1400));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('วิชา').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา')); // หน้าวิชาเปิดที่แผนผังก่อน → สลับไปรายละเอียด
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

    await tester.tap(find.text('วิ่ง 5K'));
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
    expect(find.text('Reminder Inbox'), findsOneWidget);
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

    await tester.tap(find.text('RE4'));
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
    await tester.tap(find.text('เดือน'));
    await tester.pumpAndSettle();
    expect(find.text(thaiMonthYear(now)), findsOneWidget);

    await tester.tap(find.text('ปี'));
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

    await tester.tap(find.text('วัน'));
    await tester.pumpAndSettle();
    expect(find.text('เพิ่มงาน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('มุมมองสัปดาห์: เลือกแบบ A / B / C ได้ (จอกว้าง)', (tester) async {
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

    expect(find.text('A ตารางเวลา'), findsOneWidget);
    await tester.tap(find.text('B ลิสต์'));
    await tester.pumpAndSettle();
    expect(find.text('17:00–17:45 · วิ่ง'), findsOneWidget);
    expect(find.text('45 นาที'), findsOneWidget); // ชั่วโมงรวมของวัน

    await tester.tap(find.text('C การ์ด'));
    await tester.pumpAndSettle();
    expect(find.text('วิ่ง'), findsOneWidget);
    expect(find.text('17:45'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('แผนผังแผนการเรียน: ใส่แผน 4 ปี → เห็นทุกปี + 125 หน่วยกิต → แตะเปิดวิชา',
      (tester) async {
    setScreen(tester, const Size(1280, 1000));
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
    await tester.tap(find.text('วิชา').first);
    await tester.pumpAndSettle();

    expect(find.text('แผนการเรียน'), findsOneWidget);
    await tester.tap(find.byTooltip('ตัวเลือก'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ใส่ตัวอย่าง: แผน 4 ปี'));
    await tester.pumpAndSettle();

    expect(find.text('ปีการศึกษาที่ 1'), findsOneWidget);
    expect(find.text('ปีการศึกษาที่ 4'), findsOneWidget);
    expect(find.text('จำนวนหน่วยกิตตลอดหลักสูตร 125 หน่วยกิต'), findsOneWidget);

    await tester.tap(find.text('การเขียนโปรแกรมคอมพิวเตอร์'));
    await tester.pumpAndSettle();
    expect(find.text('บท 1 · อัลกอริทึมและผังงาน [กลางภาค]'), findsOneWidget);
    expect(find.text('ตารางเรียน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
