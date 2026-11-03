import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/data/memory_study_repository.dart';

/// เปิดแอปด้วยข้อมูลใน RAM (ไม่แตะไฟล์ฐานข้อมูลจริง)
Widget buildApp() =>
    NoirManagerApp(studyRepository: MemoryStudyRepository.seeded());

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
}
