/// หัวหน้าแบบเดียวกันทุกเมนู (รอบ 9A): กลุ่ม (เล็ก) → ชื่อหน้า (ใหญ่) → แท็บย่อย · ปุ่มหลักมุมขวา
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';

class MenuHeader extends StatelessWidget {
  const MenuHeader({super.key, required this.group, required this.title, this.tabs, this.action});

  final String group;
  final String title;

  /// แท็บย่อย (แท็บแรก = ภาพรวม)
  final Widget? tabs;

  /// ปุ่มหลักของหน้า (เช่น ＋ โปรเจกต์)
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group, style: TextStyle(fontSize: 12, color: c.muted)),
              Text(title, style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.text)),
            ]),
          ),
          ?action,
        ]),
        if (tabs != null) ...[const SizedBox(height: 10), tabs!],
      ]),
    );
  }
}

/// แท็บย่อยแบบเม็ด (เลื่อนแนวนอนได้บนจอแคบ)
class MenuTabs<T> extends StatelessWidget {
  const MenuTabs({super.key, required this.value, required this.items, required this.onChanged});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (final (v, label) in items)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Material(
                color: v == value ? c.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(9),
                child: InkWell(
                  key: ValueKey('tab-$label'),
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => onChanged(v),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    child: Text(label,
                        style: TextStyle(
                            fontSize: 13, color: v == value ? c.text : c.muted, fontWeight: v == value ? FontWeight.w600 : FontWeight.w400)),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
