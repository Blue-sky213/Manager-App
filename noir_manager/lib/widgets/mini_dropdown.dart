import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';

/// ดรอปดาวน์เล็กมีกรอบ — ใช้แทนแถวปุ่มหลายปุ่ม ให้หัวหน้าดูโล่ง
class MiniDropdown<T> extends StatelessWidget {
  const MiniDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
    this.tooltip,
  });

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final box = Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 4),
      decoration: BoxDecoration(
        border: Border.all(color: c.line2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          borderRadius: BorderRadius.circular(10),
          style: TextStyle(fontSize: 14, color: c.text),
          items: [
            for (final (v, label) in items) DropdownMenuItem<T>(value: v, child: Text(label)),
          ],
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
    return tooltip == null ? box : Semantics(label: tooltip, child: box);
  }
}
