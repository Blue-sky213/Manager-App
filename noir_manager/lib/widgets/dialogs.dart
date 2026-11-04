import 'package:flutter/material.dart';

/// กล่องถามชื่อ (ใช้ตอนเพิ่มวิชา / บท / หัวข้อย่อย)
/// คืนค่าข้อความที่พิมพ์ หรือ null ถ้ากดยกเลิก / เว้นว่าง
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
  String initial = '', // ใส่ชื่อเดิมไว้ก่อน (ตอนเปลี่ยนชื่อ)
  String confirmLabel = 'เพิ่ม',
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label, hintText: hint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  // ไม่ dispose controller ตรงนี้ เพราะกล่องยังเล่นแอนิเมชันปิดอยู่ (ใช้ controller ต่ออีกนิด)
  final text = result?.trim() ?? '';
  return text.isEmpty ? null : text;
}

/// กล่องเลือกความสำคัญของวิชา: คืน 3 (สูง) / 2 (กลาง) / 1 (น้อย) หรือ null ถ้ายกเลิก
Future<int?> askImportance(BuildContext context, {int? current}) {
  Widget option(BuildContext ctx, int value, String label, String detail) =>
      SimpleDialogOption(
        onPressed: () => Navigator.pop(ctx, value),
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(value == current
              ? Icons.radio_button_checked
              : Icons.radio_button_unchecked),
          title: Text(label),
          subtitle: Text(detail),
        ),
      );

  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('ความสำคัญของวิชา'),
      children: [
        option(ctx, 3, 'สูง', 'ติว 3–7 รอบ/สัปดาห์ (เริ่มที่ 3)'),
        option(ctx, 2, 'กลาง', 'ติว 2–3 รอบ/สัปดาห์ (เริ่มที่ 2)'),
        option(ctx, 1, 'น้อย', 'ติว 1–2 รอบ/สัปดาห์ (เริ่มที่ 2)'),
      ],
    ),
  );
}

/// กล่องยืนยันก่อนลบ คืน true ถ้ากด "ลบ"
Future<bool> confirmDelete(BuildContext context, String what) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('ยืนยันการลบ'),
      content: Text('ลบ "$what" และข้อมูลข้างในทั้งหมด? ย้อนกลับไม่ได้'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
            foregroundColor: Theme.of(context).colorScheme.onError,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('ลบ'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
