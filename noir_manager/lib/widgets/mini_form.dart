import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';

/// ชุดฟอร์มแบบ minimal (แม่แบบ = หน้า "เพิ่มงาน")
/// หัวเล็ก + ✕ · ช่องหลักตัวใหญ่ไม่มีกรอบ · ที่เหลือเป็นแถว แตะเพื่อเลือก · ปุ่มล่าง 2 ปุ่ม
/// มือถือ (< 600) = แผ่นจากด้านล่าง · คอม = กล่องกลางจอ

bool isNarrow(BuildContext context) => MediaQuery.sizeOf(context).width < 600;

/// เปิดฟอร์ม: [builder] ได้ context ของกล่อง + บอกว่าเป็นแผ่นล่างไหม
Future<T?> showMiniForm<T>(BuildContext context, Widget Function(BuildContext ctx) builder) {
  if (isNarrow(context)) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => _SheetFlag(sheet: true, child: Builder(builder: builder)),
    );
  }
  return showDialog<T>(
    context: context,
    builder: (ctx) => Dialog(child: _SheetFlag(sheet: false, child: Builder(builder: builder))),
  );
}

class _SheetFlag extends InheritedWidget {
  const _SheetFlag({required this.sheet, required super.child});
  final bool sheet;
  @override
  bool updateShouldNotify(_SheetFlag old) => old.sheet != sheet;
}

/// 1 ตัวเลือกในเมนู ⋮ ของฟอร์ม
typedef MiniMenuItem = ({String label, VoidCallback onTap, bool danger});

MiniMenuItem miniMenu(String label, VoidCallback onTap, {bool danger = false}) =>
    (label: label, onTap: onTap, danger: danger);

/// โครงฟอร์ม: หัวเล็ก (+ ⋮) + ✕ · เนื้อหา · ปุ่มรอง | ปุ่มหลัก
class MiniForm extends StatelessWidget {
  const MiniForm({
    super.key,
    required this.title,
    required this.children,
    this.primaryLabel,
    this.onPrimary,
    this.secondaryLabel = 'ยกเลิก',
    this.onSecondary,
    this.menu = const [],
    this.maxWidth = 520,
    this.danger = false,
  });

  final String title;
  final List<Widget> children;

  /// null = ไม่มีปุ่มล่าง (เช่น แผ่นเลือกที่แตะแล้วปิดเอง)
  final String? primaryLabel;

  /// null = ปุ่มหลักจาง (ยังกรอกไม่ครบ)
  final VoidCallback? onPrimary;
  final String secondaryLabel;

  /// null = ปิดกล่อง
  final VoidCallback? onSecondary;
  final List<MiniMenuItem> menu;
  final double maxWidth;

  /// ปุ่มหลักสีแดง (ลบ)
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final sheet = context.dependOnInheritedWidgetOfExactType<_SheetFlag>()?.sheet ?? false;
    final red = Theme.of(context).colorScheme.error;
    final body = Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.muted)),
        ),
        if (menu.isNotEmpty)
          PopupMenuButton<int>(
            key: const Key('mini-form-menu'),
            tooltip: 'ตัวเลือก',
            icon: Icon(Icons.more_vert, size: 20, color: c.muted),
            onSelected: (i) => menu[i].onTap(),
            itemBuilder: (_) => [
              for (var i = 0; i < menu.length; i++)
                PopupMenuItem(
                  value: i,
                  height: 40,
                  child: Text(menu[i].label, style: menu[i].danger ? TextStyle(color: red) : null),
                ),
            ],
          ),
        IconButton(
          tooltip: 'ปิด',
          visualDensity: VisualDensity.compact,
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close, size: 20),
        ),
      ]),
      ...children,
      if (primaryLabel != null) ...[
        const SizedBox(height: 16),
        // ปุ่มรองยาว (เช่น "แค่ทำแล้ว ไม่บันทึก") ต้องหดได้บนจอแคบ
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Flexible(
            child: TextButton(
              onPressed: onSecondary ?? () => Navigator.pop(context),
              child: Text(secondaryLabel, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const Key('mini-form-primary'),
            style: danger
                ? FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error, foregroundColor: Theme.of(context).colorScheme.onError)
                : null,
            onPressed: onPrimary,
            child: Text(primaryLabel!),
          ),
        ]),
      ],
    ]);
    return Padding(
      key: const Key('mini-form'),
      padding: EdgeInsets.fromLTRB(20, sheet ? 0 : 12, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: SingleChildScrollView(child: body),
      ),
    );
  }
}

/// ช่องหลักตัวใหญ่ ไม่มีกรอบ (ชื่อ / คะแนน)
class MiniBigField extends StatelessWidget {
  const MiniBigField({
    super.key,
    required this.controller,
    required this.hint,
    this.autofocus = true,
    this.onSubmitted,
    this.onChanged,
    this.keyboardType,
    this.suffix,
    this.fontSize = 20,
  });

  final TextEditingController controller;
  final String hint;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onChanged;
  final TextInputType? keyboardType;
  final String? suffix;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return TextField(
      controller: controller,
      autofocus: autofocus,
      keyboardType: keyboardType,
      style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w600, color: c.text),
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: fontSize > 22 ? 18 : null, fontWeight: FontWeight.w500, color: c.muted),
        suffixText: suffix,
        border: InputBorder.none,
        enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.line)),
        focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.accent)),
      ),
      onChanged: onChanged,
      onSubmitted: onSubmitted,
    );
  }
}

/// ป้ายหัวข้อเล็กสีจาง
class MiniLabel extends StatelessWidget {
  const MiniLabel(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 6),
        child: Text(text, style: TextStyle(fontSize: 12, color: context.noir.muted)),
      );
}

/// 1 แถว = ไอคอน · ชื่อ · ค่าปัจจุบัน (ขวา) · แตะ = เปิดตัวเลือก
class MiniRow extends StatelessWidget {
  const MiniRow({
    super.key,
    this.icon,
    required this.label,
    this.value,
    this.valueText,
    this.onTap,
    this.trailing,
    this.last = false,
  });

  final IconData? icon;
  final String label;
  final Widget? value;
  final String? valueText;
  final VoidCallback? onTap;

  /// แทนลูกศร (เช่น สวิตช์)
  final Widget? trailing;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final v = value ??
        (valueText == null
            ? null
            : Text(valueText!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: FontWeight.w600, color: c.text)));
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
        decoration: BoxDecoration(border: last ? null : Border(bottom: BorderSide(color: c.line))),
        child: Row(children: [
          if (icon != null) ...[Icon(icon, size: 20, color: c.muted), const SizedBox(width: 12)],
          // ชื่อยาว (เช่น ชื่อวิชา) ตัดบรรทัดได้ · ค่าทางขวาไม่ดันจนล้น
          Expanded(flex: 4, child: Text(label, style: TextStyle(color: v == null ? c.text : c.muted))),
          if (v != null) ...[
            const SizedBox(width: 12),
            Expanded(flex: 5, child: Align(alignment: Alignment.centerRight, child: v)),
          ],
          if (trailing != null) trailing! else if (onTap != null) Icon(Icons.chevron_right, size: 20, color: c.muted),
        ]),
      ),
    );
  }
}

/// แถวมีสวิตช์ (แตะทั้งแถวได้)
class MiniSwitchRow extends StatelessWidget {
  const MiniSwitchRow({super.key, this.icon, required this.label, this.detail, required this.value, required this.onChanged, this.last = false});

  final IconData? icon;
  final String label;
  final String? detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return MiniRow(
      icon: icon,
      label: label,
      last: last,
      value: detail == null ? null : Text(detail!, textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: c.muted)),
      onTap: () => onChanged(!value),
      trailing: Switch(value: value, onChanged: onChanged),
    );
  }
}

/// ช่องกรอกเล็กในแถว (ไม่มีเส้นใต้ · ชิดขวา)
class MiniInlineField extends StatelessWidget {
  const MiniInlineField({super.key, required this.controller, this.hint = '—', this.keyboardType, this.onChanged, this.width = 140});

  final TextEditingController controller;
  final String hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return SizedBox(
      width: width,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textAlign: TextAlign.right,
        style: TextStyle(fontWeight: FontWeight.w600, color: c.text),
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: TextStyle(color: c.muted, fontWeight: FontWeight.w400),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
        ),
        onChanged: onChanged,
      ),
    );
  }
}

/// วันในสัปดาห์เป็นวงกลม 7 วง (1 = จันทร์ … 7 = อาทิตย์)
class WeekdayCircles extends StatelessWidget {
  const WeekdayCircles({super.key, required this.selected, required this.onToggle});

  final Set<int> selected;
  final ValueChanged<int> onToggle;

  static const _names = ['จ', 'อ', 'พ', 'พฤ', 'ศ', 'ส', 'อา'];

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Row(children: [
      for (var d = 1; d <= 7; d++)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: AspectRatio(
              aspectRatio: 1,
              child: Material(
                key: Key('weekday-$d'),
                shape: const CircleBorder(),
                color: selected.contains(d) ? c.accent : c.surface,
                child: InkWell(
                  customBorder: const CircleBorder(),
                  onTap: () => onToggle(d),
                  child: Center(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_names[d - 1],
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: selected.contains(d) ? FontWeight.w700 : FontWeight.w400,
                            color: selected.contains(d) ? c.onAccent : c.text,
                          )),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
    ]);
  }
}

/// 1 ตัวเลือกในแผ่นเลือก
typedef MiniChoice<T> = ({T value, String label, String? detail, bool enabled});

MiniChoice<T> miniChoice<T>(T value, String label, {String? detail, bool enabled = true}) =>
    (value: value, label: label, detail: detail, enabled: enabled);

/// แผ่นเลือก 1 ข้อ (แทน SimpleDialog / radio) · แตะ = เลือกแล้วปิด
Future<T?> showMiniChoice<T>(BuildContext context, {required String title, required List<MiniChoice<T>> items, T? current}) {
  return showMiniForm<T>(context, (ctx) {
    final c = ctx.noir;
    return MiniForm(title: title, children: [
      for (var i = 0; i < items.length; i++)
        MiniRow(
          key: Key('choice-${items[i].value}'),
          label: items[i].label,
          last: i == items.length - 1,
          value: items[i].detail == null
              ? null
              : Text(items[i].detail!,
                  textAlign: TextAlign.right, style: TextStyle(fontSize: 12, color: items[i].enabled ? c.muted : c.line)),
          trailing: Icon(
            items[i].value == current ? Icons.check_circle : Icons.circle_outlined,
            size: 20,
            color: items[i].value == current ? c.accent : (items[i].enabled ? c.muted : c.line),
          ),
          onTap: items[i].enabled ? () => Navigator.pop(ctx, items[i].value) : null,
        ),
    ]);
  });
}

/// แผ่นตัวเลือกย่อย (เปิดจากแถว) · [build] ได้ฟังก์ชัน set ที่อัปเดตทั้งแผ่นและฟอร์มแม่
Future<void> showMiniSubSheet(
  BuildContext context, {
  required String title,
  required void Function(VoidCallback) parentSetState,
  required Widget Function(BuildContext ctx, void Function(VoidCallback) set) build,
}) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        void set(VoidCallback f) {
          parentSetState(f);
          setLocal(() {});
        }

        final c = ctx.noir;
        return Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + MediaQuery.viewInsetsOf(ctx).bottom),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text))),
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('เสร็จ')),
            ]),
            const SizedBox(height: 8),
            Flexible(child: SingleChildScrollView(child: build(ctx, set))),
          ]),
        );
      }),
    );

/// กล่องยืนยันแบบ minimal: หัวเล็ก · ข้อความ · ยกเลิก | ปุ่มหลัก
Future<bool> confirmMini(BuildContext context,
    {required String title, required String message, String okLabel = 'ตกลง', String cancelLabel = 'ยกเลิก', bool danger = false}) async {
  final ok = await showMiniForm<bool>(
    context,
    (ctx) => MiniForm(
      title: title,
      primaryLabel: okLabel,
      secondaryLabel: cancelLabel,
      onSecondary: () => Navigator.pop(ctx, false),
      danger: danger,
      onPrimary: () => Navigator.pop(ctx, true),
      children: [Text(message, style: TextStyle(color: ctx.noir.text, height: 1.5))],
    ),
  );
  return ok ?? false;
}
