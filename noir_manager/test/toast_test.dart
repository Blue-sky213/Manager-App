import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/shell/app_nav.dart' show lastPointerDown;
import 'package:noir_manager/theme/app_theme.dart';
import 'package:noir_manager/widgets/info_card.dart';
import 'package:noir_manager/widgets/toast.dart';

Future<BuildContext> host(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  late BuildContext ctx;
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(),
    home: Scaffold(body: Builder(builder: (c) {
      ctx = c;
      return const SizedBox.expand();
    })),
  ));
  return ctx;
}

void main() {
  test('เดาประเภทจากข้อความ', () {
    expect(guessToastKind('🔒 ทำงานสำคัญให้ครบก่อน'), ToastKind.warn);
    expect(guessToastKind('ส่งออกไม่ได้: x'), ToastKind.error);
    expect(guessToastKind('ย้ายไปเสาร์แล้ว'), ToastKind.success);
    expect(guessToastKind('จำลอง 12 คาบ'), ToastKind.info);
  });

  testWidgets('แจ้งเตือนขึ้นบนกลาง · หายเองใน 2.5 วิ · ซ้อนได้ 3 อัน · ผิดพลาดค้าง', (tester) async {
    final ctx = await host(tester, const Size(1200, 800));
    showToast(ctx, 'บันทึกแล้ว');
    await tester.pump(const Duration(milliseconds: 300));
    final r = tester.getRect(find.byKey(const Key('toast')));
    expect(r.top, lessThan(80)); // บน
    expect((r.center.dx - 600).abs(), lessThan(2)); // กลาง
    expect(r.width, lessThanOrEqualTo(440)); // ไม่เต็มจอ

    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('toast')), findsNothing);

    for (var i = 0; i < 5; i++) {
      showToast(ctx, 'แจ้ง $i');
    }
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const Key('toast')), findsNWidgets(3));
    expect(find.text('แจ้ง 4'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();

    showToast(ctx, 'ส่งออกไม่ได้: ดิสก์เต็ม');
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('ส่งออกไม่ได้: ดิสก์เต็ม'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('toast')), findsNothing);
  });

  testWidgets('ปุ่มท้ายแจ้งเตือน (เลิกทำ) ทำงาน', (tester) async {
    final ctx = await host(tester, const Size(1200, 800));
    var undone = false;
    showToast(ctx, 'ย้ายแล้ว', action: 'เลิกทำ', onAction: () => undone = true);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('เลิกทำ'));
    await tester.pumpAndSettle();
    expect(undone, isTrue);
  });

  testWidgets('รายละเอียด: คอม = การ์ดลอยข้างจุดที่คลิก · มือถือ = แผ่นล่าง', (tester) async {
    var ctx = await host(tester, const Size(1200, 800));
    lastPointerDown = const Offset(300, 200);
    showInfoCard(ctx, builder: (_) => const Text('รายละเอียดงาน'));
    await tester.pumpAndSettle();
    final r = tester.getRect(find.byKey(const Key('info-card')));
    expect(r.left, closeTo(312, 1)); // ขวาของเมาส์
    expect(r.width, 340);
    await tester.tapAt(const Offset(1000, 700)); // คลิกที่ว่าง = ปิด
    await tester.pumpAndSettle();
    expect(find.text('รายละเอียดงาน'), findsNothing);

    ctx = await host(tester, const Size(400, 800));
    showInfoCard(ctx, builder: (_) => const Text('รายละเอียดงาน'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('info-card')), findsNothing);
    expect(find.byType(BottomSheet), findsOneWidget);
  });
}
