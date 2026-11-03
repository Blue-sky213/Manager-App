import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';

void main() {
  testWidgets('จอกว้าง: มี Sidebar, กดเมนูแล้วเปลี่ยนหน้า, สลับธีมได้',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 820);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NoirManagerApp());

    // ชื่อแอปอยู่บน Sidebar และเริ่มที่โหมดมืด
    expect(find.text('Noir Manager'), findsOneWidget);
    expect(find.text('โหมดสว่าง'), findsOneWidget);

    // กดเมนู "วิชา" → เห็นข้อความของหน้าวิชา
    await tester.tap(find.text('วิชา').first);
    await tester.pumpAndSettle();
    expect(find.text('Study Tree'), findsOneWidget);

    // กดสลับธีม → ปุ่มเปลี่ยนเป็น "โหมดมืด"
    await tester.tap(find.text('โหมดสว่าง'));
    await tester.pumpAndSettle();
    expect(find.text('โหมดมืด'), findsOneWidget);
  });

  testWidgets('จอแคบ: ใช้ Bottom bar แทน Sidebar', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const NoirManagerApp());

    expect(find.byType(NavigationBar), findsOneWidget);
  });
}
