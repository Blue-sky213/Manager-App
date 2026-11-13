import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/widgets/thai_backspace.dart';

void main() {
  test('ลบสระ/วรรณยุกต์ไทยทีละตัว · ตัวอื่นปล่อยให้ระบบลบ', () {
    TextEditingValue v(String t, [int? at]) =>
        TextEditingValue(text: t, selection: TextSelection.collapsed(offset: at ?? t.length));
    expect(thaiBackspace(v('กิ'))!.text, 'ก');
    expect(thaiBackspace(v('ก้'))!.text, 'ก');
    expect(thaiBackspace(v('กี่'))!.text, 'กี'); // วรรณยุกต์ก่อน แล้วค่อยสระ
    expect(thaiBackspace(v('กั'))!.text, 'ก');
    expect(thaiBackspace(v('กิน', 2))!.text, 'กน'); // เคอร์เซอร์กลางคำ
    expect(thaiBackspace(v('กิน', 2))!.selection.baseOffset, 1);
    expect(thaiBackspace(v('ก')), isNull); // พยัญชนะ → ระบบลบเอง
    expect(thaiBackspace(v('กา')), isNull); // สระอา ไม่ซ้อน
    expect(thaiBackspace(v('')), isNull);
    expect(
        thaiBackspace(const TextEditingValue(text: 'กิ', selection: TextSelection(baseOffset: 0, extentOffset: 2))),
        isNull); // เลือกไว้หลายตัว → ลบที่เลือกตามปกติ
  });

  testWidgets('กด Backspace ในช่องพิมพ์: "กิน" → "กิ" → "ก" → ""', (tester) async {
    final ctl = TextEditingController();
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ThaiBackspace(child: child!),
      home: Scaffold(body: TextField(controller: ctl, autofocus: true)),
    ));
    await tester.pump();
    await tester.enterText(find.byType(TextField), 'กิน');
    await tester.pump();
    Future<void> back() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
    }

    await back();
    expect(ctl.text, 'กิ');
    await back();
    expect(ctl.text, 'ก'); // เดิมหายทั้ง "กิ"
    await back();
    expect(ctl.text, '');
    expect(tester.takeException(), isNull);
  });
}
