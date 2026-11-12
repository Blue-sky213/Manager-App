import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/study/mastery.dart' show GradingMode;
import 'package:noir_manager/theme/app_theme.dart';
import 'package:noir_manager/theme/noir_colors.dart';
import 'package:noir_manager/widgets/dialogs.dart';

/// เปิดหน้าเปล่าที่มีปุ่มเดียว · กดแล้วเรียก [open]
Future<void> pumpHost(WidgetTester tester, Size size, Future<void> Function(BuildContext) open) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.of(themeChoices.first),
    home: Scaffold(
      body: Builder(builder: (ctx) => TextButton(onPressed: () => open(ctx), child: const Text('เปิด'))),
    ),
  ));
  await tester.tap(find.text('เปิด'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('ฟอร์ม minimal: มือถือ = แผ่นล่าง · คอม = กล่องกลาง · Enter = ยืนยัน', (tester) async {
    String? got;
    await pumpHost(tester, const Size(393, 852), (ctx) async {
      got = await askText(ctx, title: 'เพิ่มวิชา', label: 'ชื่อวิชา', hint: 'เช่น DataCOM');
    });
    expect(find.byType(BottomSheet), findsOneWidget);
    expect(find.byKey(const Key('mini-form')), findsOneWidget);
    expect(find.text('ชื่อวิชา เช่น DataCOM'), findsOneWidget); // ช่องตัวใหญ่ใช้ชื่อเป็น hint
    await tester.enterText(find.byType(TextField), 'DataCOM');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(got, 'DataCOM');
    expect(tester.takeException(), isNull);

    await pumpHost(tester, const Size(1280, 800), (ctx) async {
      got = await askText(ctx, title: 'เพิ่มวิชา', label: 'ชื่อวิชา');
    });
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byType(Dialog), findsOneWidget);
    await tester.tap(find.byTooltip('ปิด'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('mini-form')), findsNothing);
  });

  testWidgets('แผ่นเลือก: แตะแถว = เลือกแล้วปิด · ยืนยันลบปุ่มแดง', (tester) async {
    int? picked;
    await pumpHost(tester, const Size(393, 852), (ctx) async {
      picked = await askImportance(ctx, current: 2);
    });
    expect(find.byIcon(Icons.check_circle), findsOneWidget); // ค่าปัจจุบัน
    await tester.tap(find.text('สูง'));
    await tester.pumpAndSettle();
    expect(picked, 3);

    bool? ok;
    await pumpHost(tester, const Size(393, 852), (ctx) async {
      ok = await confirmDelete(ctx, 'บท 1');
    });
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(ok, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('EZ / Advanced: หน้าวิชามีแค่สวิตช์ · กฎ Advanced อยู่หน้าตั้งค่า', (tester) async {
    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final study = MemoryStudyRepository.seeded();
    await tester.pumpWidget(NoirManagerApp(studyRepository: study, calendarRepository: MemoryCalendarRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('การเรียน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บทเรียน').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('grading-switch')), findsOneWidget);
    expect(find.byTooltip('ตั้งค่าโหมด Advanced'), findsNothing);
    expect(find.textContaining('EZ: สีและ %'), findsNothing);

    // ตั้งค่า: เลือก EZ → ไม่มีแถวกฎ · Advanced → มี 2 แถว
    await tester.tap(find.text('ตั้งค่า').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('rule-green_twice_rule')), findsNothing);
    await tester.tap(find.text('Advanced').first);
    await tester.pumpAndSettle();
    expect(await study.gradingMode(), GradingMode.advanced);
    await tester.ensureVisible(find.byKey(const Key('rule-red_twice_rule')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('rule-red_twice_rule')));
    await tester.pumpAndSettle();
    // ตก 2 รอบติด: ห้ามใช้ค่าเฉลี่ย → แถวนั้นกดไม่ได้
    await tester.tap(find.byKey(const Key('choice-RuleChoice.recent')));
    await tester.pumpAndSettle();
    expect(await study.getSetting('red_twice_rule'), 'recent');
    expect(find.text('นับ 2 รอบล่าสุด'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
