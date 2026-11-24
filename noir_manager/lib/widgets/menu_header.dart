/// หัวหน้าแบบเดียวกันทุกเมนู (รอบ 9A): กลุ่ม (เล็ก) → ชื่อหน้า (ใหญ่) → แท็บย่อย · ปุ่มหลักมุมขวา
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderAbstractViewport;

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
/// รอบ 23 (นัวร์ขอ): กดแท็บ = เลื่อนแท็บนั้นมาไว้กลาง (จนสุดขอบ) · หมุนลูกกลิ้ง / ลากเมาส์ / ลากนิ้ว = เลื่อนได้
class MenuTabs<T> extends StatefulWidget {
  const MenuTabs({super.key, required this.value, required this.items, required this.onChanged});

  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  @override
  State<MenuTabs<T>> createState() => _MenuTabsState<T>();
}

class _MenuTabsState<T> extends State<MenuTabs<T>> {
  final _scroll = ScrollController();
  final _keys = <Object?, GlobalKey>{};

  GlobalKey _keyOf(T v) => _keys.putIfAbsent(v, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _center(widget.value, animate: false));
  }

  @override
  void didUpdateWidget(MenuTabs<T> old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) WidgetsBinding.instance.addPostFrameCallback((_) => _center(widget.value));
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _center(T v, {bool animate = true}) {
    final ctx = _keys[v]?.currentContext;
    if (!mounted || ctx == null || !_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
    // คิดเฉพาะแถบแท็บนี้ (ไม่ใช้ ensureVisible เพราะจะลากหน้าที่อยู่รอบนอกเลื่อนตามด้วย)
    final box = ctx.findRenderObject();
    if (box == null) return;
    final p = _scroll.position;
    final to = RenderAbstractViewport.of(box).getOffsetToReveal(box, 0.5).offset.clamp(0.0, p.maxScrollExtent);
    if (animate) {
      _scroll.animateTo(to, duration: const Duration(milliseconds: 250), curve: Curves.easeOutCubic);
    } else {
      _scroll.jumpTo(to);
    }
  }

  void _wheel(PointerSignalEvent e) {
    if (e is! PointerScrollEvent || !_scroll.hasClients) return;
    final p = _scroll.position;
    final d = e.scrollDelta.dx != 0 ? e.scrollDelta.dx : e.scrollDelta.dy;
    if (p.maxScrollExtent <= 0 || d == 0) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (_) => _scroll.jumpTo((p.pixels + d).clamp(0.0, p.maxScrollExtent)));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Listener(
      onPointerSignal: _wheel,
      child: ScrollConfiguration(
        // ลากด้วยเมาส์ได้ด้วย (ค่าตั้งต้นของคอมลากได้แค่นิ้ว)
        behavior: ScrollConfiguration.of(context).copyWith(dragDevices: PointerDeviceKind.values.toSet(), scrollbars: false),
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: c.line)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final (v, label) in widget.items)
                Padding(
                  key: _keyOf(v),
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Material(
                    color: v == widget.value ? c.surface2 : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      key: ValueKey('tab-$label'),
                      borderRadius: BorderRadius.circular(9),
                      onTap: () {
                        widget.onChanged(v);
                        _center(v);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        child: Text(label,
                            style: TextStyle(
                                fontSize: 13,
                                color: v == widget.value ? c.text : c.muted,
                                fontWeight: v == widget.value ? FontWeight.w600 : FontWeight.w400)),
                      ),
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
