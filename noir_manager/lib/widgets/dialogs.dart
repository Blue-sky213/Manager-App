import 'package:flutter/material.dart';

/// กล่องถามชื่อ (ใช้ตอนเพิ่มวิชา / บท / หัวข้อย่อย)
/// คืนค่าข้อความที่พิมพ์ หรือ null ถ้ากดยกเลิก / เว้นว่าง
Future<String?> askText(
  BuildContext context, {
  required String title,
  required String label,
  String? hint,
}) async {
  final controller = TextEditingController();
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
          child: const Text('เพิ่ม'),
        ),
      ],
    ),
  );
  // ไม่ dispose controller ตรงนี้ เพราะกล่องยังเล่นแอนิเมชันปิดอยู่ (ใช้ controller ต่ออีกนิด)
  final text = result?.trim() ?? '';
  return text.isEmpty ? null : text;
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
