import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/calendar_models.dart';
import 'package:noir_manager/calendar/calendar_ui.dart';
import 'package:noir_manager/theme/app_theme.dart';
import 'package:noir_manager/theme/noir_colors.dart';

void main() {
  testWidgets('Preset: ชื่อซ้ำไม่ได้ · คลิกขวา = เมนู (ไม่ลบทันที) · ลบต้องยืนยัน', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final saved = <String>[];
    final deleted = <int>[];
    final updated = <String>[];
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.of(themeChoices.first),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showActivityDialog(
              ctx,
              day: DateTime(2026, 11, 13),
              categories: const [ActivityCategory(id: 1, name: 'สตรีม', colorKey: 'purple')],
              presets: const [
                Preset(id: 7, name: 'Drawing', categoryId: 1, importance: 2, startMinute: 19 * 60, durationMin: 90),
              ],
              onSavePreset: (name, _) async {
                saved.add(name);
                return 8;
              },
              onUpdatePreset: (id, name, _) async => updated.add(name),
              onDeletePreset: (id) async => deleted.add(id),
            ),
            child: const Text('เปิด'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('เปิด'));
    await tester.pumpAndSettle();

    // บันทึกชื่อซ้ำ (ตัวพิมพ์ต่าง + เว้นวรรค) → ไม่บันทึก · บอกเหตุผล
    await tester.tap(find.text('บันทึก preset'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('preset-name')), ' drawing ');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(find.textContaining('มีชื่อ "drawing" แล้ว'), findsOneWidget);
    expect(saved, isEmpty);
    await tester.enterText(find.byKey(const Key('preset-name')), 'Drawing 2');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(saved, ['Drawing 2']);

    // คลิกขวา → เมนู · ยังไม่ลบ
    await tester.tap(find.byKey(const Key('preset-7')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.text('ดูข้อมูล'), findsOneWidget);
    expect(find.text('แก้ไข'), findsOneWidget);
    expect(deleted, isEmpty);

    // ดูข้อมูล
    await tester.tap(find.text('ดูข้อมูล'));
    await tester.pumpAndSettle();
    expect(find.text('19:00–20:30 · 1 ชม. 30 นาที'), findsOneWidget);
    await tester.tap(find.byTooltip('ปิด').last);
    await tester.pumpAndSettle();

    // ลบ → ถามก่อน → ยืนยัน
    await tester.tap(find.byKey(const Key('preset-7')), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('ลบ'));
    await tester.pumpAndSettle();
    expect(find.text('ลบ Preset "Drawing"?'), findsOneWidget);
    expect(deleted, isEmpty);
    await tester.tap(find.widgetWithText(FilledButton, 'ลบ'));
    await tester.pumpAndSettle();
    expect(deleted, [7]);
    expect(find.byKey(const Key('preset-7')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
