import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';

/// แถบเลือกแบบ minimal: แถวเดียว ช่องกว้างเท่ากัน · ช่องที่เลือก = พื้นเข้มขึ้น (ไม่มี ✓)
/// ใช้แทนชิปหลายอันที่ตกบรรทัดบนจอแคบ
class MiniSegments<T> extends StatelessWidget {
  const MiniSegments({super.key, required this.value, required this.items, required this.onChanged});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        for (final (v, label) in items)
          Expanded(
            child: Material(
              color: v == value ? c.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => onChanged(v),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: v == value ? FontWeight.w600 : FontWeight.w400,
                        color: v == value ? c.text : c.muted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
