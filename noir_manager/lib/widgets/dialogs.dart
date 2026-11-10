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

/// ปุ่มข้างของเมาส์: ปุ่ม 4 = ย้อนกลับ · ปุ่ม 5 = ไปข้างหน้า (ค่าเดียวกับ kBack/kForwardMouseButton)
const int _mouseBackButton = 0x08;
const int _mouseForwardButton = 0x10;

/// ฟังปุ่มเมาส์ 4 / 5 · null = ไม่ทำอะไร (ปล่อยให้ตัวนอกจัดการ)
/// [onPointer] = ทุกครั้งที่กดเมาส์ (เก็บตำแหน่งไว้เปิดเมนูตรงเมาส์)
class MouseBack extends StatelessWidget {
  const MouseBack({super.key, required this.onBack, this.onForward, this.onPointer, required this.child});

  final VoidCallback? onBack;
  final VoidCallback? onForward;
  final ValueChanged<Offset>? onPointer;
  final Widget child;

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: (e) {
          onPointer?.call(e.position);
          if (e.buttons & _mouseBackButton != 0) onBack?.call();
          if (e.buttons & _mouseForwardButton != 0) onForward?.call();
        },
        child: child,
      );
}

/// 1 ตัวเลือกในเมนูคลิกขวา · [danger] = สีแดง แยกด้วยเส้นคั่น (เช่น ลบ)
typedef ContextItem<T> = ({T value, IconData icon, String label, bool danger});

ContextItem<T> ctxItem<T>(T value, IconData icon, String label, {bool danger = false}) =>
    (value: value, icon: icon, label: label, danger: danger);

/// เมนูคลิกขวาแบบ Windows: เด้งตรงตำแหน่งเมาส์ [at] (พิกัดบนจอ)
Future<T?> showContextMenuAt<T>(BuildContext context, Offset at, List<ContextItem<T>> items) {
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  final local = overlay.globalToLocal(at);
  final danger = Theme.of(context).colorScheme.error;
  Widget row(ContextItem<T> i) => Row(children: [
        Icon(i.icon, size: 18, color: i.danger ? danger : null),
        const SizedBox(width: 12),
        Flexible(child: Text(i.label, style: i.danger ? TextStyle(color: danger) : null)),
      ]);
  return showMenu<T>(
    context: context,
    position: RelativeRect.fromRect(local & const Size(1, 1), Offset.zero & overlay.size),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    // เมนูเริ่มต้นของ Flutter แคบ (≤ 280) → ข้อความไทยยาวล้น
    constraints: const BoxConstraints(minWidth: 200, maxWidth: 360),
    items: [
      for (final i in items.where((i) => !i.danger)) PopupMenuItem<T>(value: i.value, height: 40, child: row(i)),
      if (items.any((i) => i.danger) && items.any((i) => !i.danger)) const PopupMenuDivider(),
      for (final i in items.where((i) => i.danger)) PopupMenuItem<T>(value: i.value, height: 40, child: row(i)),
    ],
  );
}
