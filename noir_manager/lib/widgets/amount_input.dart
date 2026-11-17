/// ช่องจำนวนเงิน: ใส่ได้แค่ตัวเลข + เครื่องหมายคิดเลข · ใส่ , ให้เอง · คิดเลขได้ เช่น 411+945 = 1,356
library;

import 'package:flutter/services.dart';

const _ops = '+-×÷';

/// ตัวเลขมี , คั่นหลักพัน · ทศนิยมเก็บไว้ไม่เกิน 2 ตำแหน่ง (ไม่มีทศนิยม = ไม่โชว์)
String formatAmount(double v) {
  final neg = v < 0;
  final a = v.abs();
  final whole = a.truncate();
  final cents = ((a - whole) * 100).round();
  final w = _group(cents == 100 ? '${whole + 1}' : '$whole');
  final out = cents == 0 || cents == 100 ? w : '$w.${cents.toString().padLeft(2, '0')}';
  return neg ? '-$out' : out;
}

String _group(String digits) {
  final b = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) b.write(',');
    b.write(digits[i]);
  }
  return b.toString();
}

/// ช่องว่างใส่ได้ = null · คิดตามลำดับ × ÷ ก่อน + − · ลงท้ายด้วยเครื่องหมาย = ไม่สนตัวท้าย
double? parseAmount(String text) {
  final s = text.replaceAll(RegExp(r'[,฿\s]'), '').replaceAll('*', '×').replaceAll('x', '×').replaceAll('/', '÷');
  if (s.isEmpty) return null;
  final nums = <double>[];
  final ops = <String>[];
  var cur = '';
  var sign = 1.0;
  for (var i = 0; i < s.length; i++) {
    final ch = s[i];
    if (_ops.contains(ch)) {
      if (cur.isEmpty) {
        if (nums.isEmpty && ch == '-') sign = -sign; // ลบนำหน้า
        continue; // เครื่องหมายซ้อน → ใช้ตัวแรก
      }
      final n = double.tryParse(cur);
      if (n == null) return null;
      nums.add(n * sign);
      sign = 1;
      ops.add(ch);
      cur = '';
    } else {
      cur += ch;
    }
  }
  if (cur.isNotEmpty) {
    final n = double.tryParse(cur);
    if (n == null) return null;
    nums.add(n * sign);
  } else if (ops.isNotEmpty) {
    ops.removeLast();
  }
  if (nums.isEmpty) return null;
  // × ÷ ก่อน
  final n2 = [nums.first];
  final o2 = <String>[];
  for (var i = 0; i < ops.length; i++) {
    final op = ops[i], b = nums[i + 1];
    if (op == '×') {
      n2.last = n2.last * b;
    } else if (op == '÷') {
      if (b == 0) return null;
      n2.last = n2.last / b;
    } else {
      n2.add(b);
      o2.add(op);
    }
  }
  var r = n2.first;
  for (var i = 0; i < o2.length; i++) {
    r = o2[i] == '+' ? r + n2[i + 1] : r - n2[i + 1];
  }
  return r;
}

/// มีเครื่องหมายคิดเลขไหม (ไว้โชว์ "= ผลลัพธ์")
bool isExpression(String text) => RegExp(r'\d\s*[+\-×÷*/x]\s*\d').hasMatch(text);

/// จัดรูปตอนพิมพ์: ทิ้งตัวอักษร · ใส่ , · เครื่องหมายซ้อนเหลือตัวเดียว · เคอร์เซอร์ไม่กระโดด
class AmountInputFormatter extends TextInputFormatter {
  const AmountInputFormatter();

  static String format(String raw) {
    final s = raw.replaceAll('*', '×').replaceAll('x', '×').replaceAll('/', '÷').replaceAll(RegExp(r'[^0-9.+\-×÷]'), '');
    final out = StringBuffer();
    var token = '';
    void flush() {
      if (token.isEmpty) return;
      final dot = token.indexOf('.');
      final intPart = (dot < 0 ? token : token.substring(0, dot)).replaceFirst(RegExp(r'^0+(?=\d)'), '');
      final dec = dot < 0 ? '' : '.${token.substring(dot + 1).replaceAll('.', '')}';
      out.write('${_group(intPart)}${dec.length > 3 ? dec.substring(0, 3) : dec}');
      token = '';
    }

    for (var i = 0; i < s.length; i++) {
      final ch = s[i];
      if (_ops.contains(ch)) {
        flush();
        final t = out.toString();
        if (t.isEmpty) {
          if (ch == '-') out.write(ch);
          continue;
        }
        if (_ops.contains(t[t.length - 1])) {
          // 411++945 → 411+945 (ตัวหลังแทนตัวก่อน)
          final keep = t.substring(0, t.length - 1);
          out
            ..clear()
            ..write(keep);
        }
        out.write(ch);
      } else {
        token += ch;
      }
    }
    flush();
    return out.toString();
  }

  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    final text = format(newValue.text);
    if (text == newValue.text) return newValue;
    // จำจำนวน "ตัวที่มีความหมาย" หลังเคอร์เซอร์ แล้ววางเคอร์เซอร์ตรงเดิม
    final end = newValue.selection.end.clamp(0, newValue.text.length);
    final after = RegExp(r'[0-9.+\-×÷*/x]').allMatches(newValue.text.substring(end)).length;
    var pos = text.length, seen = 0;
    while (pos > 0 && seen < after) {
      pos--;
      if (text[pos] != ',') seen++;
    }
    return TextEditingValue(text: text, selection: TextSelection.collapsed(offset: pos));
  }
}
