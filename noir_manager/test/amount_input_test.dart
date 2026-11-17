// ช่องจำนวนเงิน: เลขอย่างเดียว · มี , · คิดเลขได้ (นัวร์เจอ 411++945กดหกด แล้วบันทึกไม่ได้)
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/app.dart';
import 'package:noir_manager/calendar/memory_calendar_repository.dart';
import 'package:noir_manager/data/memory_study_repository.dart';
import 'package:noir_manager/widgets/amount_input.dart';
import 'package:noir_manager/work/money_models.dart' show subBudgetKey;

TextEditingValue type(String text) =>
    const AmountInputFormatter().formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length)));

void main() {
  test('คิดเลข: + − × ÷ ตามลำดับ · มี , ได้ · ลงท้ายด้วยเครื่องหมายไม่พัง', () {
    expect(parseAmount('411+945'), 1356);
    expect(parseAmount('1,200 + 300'), 1500);
    expect(parseAmount('100+20×3'), 160);
    expect(parseAmount('1000-250÷5'), 950);
    expect(parseAmount('969*12'), 11628);
    expect(parseAmount('500+'), 500);
    expect(parseAmount('฿2,500.50'), 2500.5);
    expect(parseAmount(''), isNull);
    expect(parseAmount('10÷0'), isNull);
  });

  test('จัดรูปตอนพิมพ์: ตัวอักษรไม่ติด · ใส่ , · เครื่องหมายซ้อนเหลือตัวเดียว', () {
    expect(type('411++945กดหกด').text, '411+945');
    expect(type('1000000').text, '1,000,000');
    expect(type('12500+3000*2').text, '12,500+3,000×2');
    expect(type('0050').text, '50');
    expect(type('99.999').text, '99.99');
    expect(type('abc').text, '');
    expect(formatAmount(1356), '1,356');
    expect(formatAmount(2500.5), '2,500.50');
    expect(isExpression('411+945'), isTrue);
    expect(isExpression('1,356'), isFalse);
  });

  test('เคอร์เซอร์ไม่กระโดดไปท้ายตอนแก้ตรงกลาง', () {
    // พิมพ์ 0 หลัง 1 ของ "1,234" → "10234" → "10,234" เคอร์เซอร์อยู่หลัง 0
    final v = const AmountInputFormatter()
        .formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '10,234', selection: TextSelection.collapsed(offset: 2)));
    expect(v.text, '10,234');
    expect(v.text.substring(0, v.selection.end).replaceAll(',', ''), '10');
  });

  testWidgets('จดรายการด้วยสูตร 411++945 → โชว์ = 1,356 → บันทึกได้ · งบ 1,000 เก็บได้', (tester) async {
    tester.view.physicalSize = const Size(1400, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final cal = MemoryCalendarRepository();
    await tester.pumpWidget(NoirManagerApp(studyRepository: MemoryStudyRepository.seeded(), calendarRepository: cal));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เงิน').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('money-add')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('money-amount')), '411++945กดหกด');
    await tester.pump();
    final field = tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('money-amount')), matching: find.byType(EditableText)));
    expect(field.controller.text, '411+945');
    expect(find.text('= 1,356'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect((await cal.workRepo.entries(DateTime(2000), DateTime(2100))).single.amount, 1356);

    await tester.tap(find.byKey(const ValueKey('tab-ค่าบริการ')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('budget-chip')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('budget')), '1000');
    await tester.pump();
    expect(tester.widget<EditableText>(find.descendant(of: find.byKey(const Key('budget')), matching: find.byType(EditableText))).controller.text,
        '1,000');
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(await cal.getSetting(subBudgetKey), '1000.0');
    expect(tester.takeException(), isNull);
  });

  test('ช่องจำนวนเต็ม (วันตัด · นาที) รับแค่ตัวเลข', () {
    final v = FilteringTextInputFormatter.digitsOnly
        .formatEditUpdate(TextEditingValue.empty, const TextEditingValue(text: '2ก5'));
    expect(v.text, '25');
  });
}
