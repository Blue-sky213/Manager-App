/// แจ้งเตือนแบบเม็ดเล็ก บนกลางจอ (รอบ 8 · A) — แทนแถบ SnackBar เต็มจอด้านล่าง
/// หายเองใน 2.5 วิ · ชี้เมาส์ค้าง = ไม่หาย · ซ้อนได้ 3 อัน · ผิดพลาด = ค้างจนกดปิด
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';

enum ToastKind { success, info, warn, error }

/// เดาประเภทจากข้อความ (จุดสีหน้าข้อความ) · ส่ง [kind] เองได้
ToastKind guessToastKind(String text) {
  if (text.startsWith('🔒') || text.startsWith('⚠')) return ToastKind.warn;
  if (text.contains('ไม่ได้') || text.contains('ผิดพลาด')) return ToastKind.error;
  if (text.contains('แล้ว') || text.startsWith('ครบ')) return ToastKind.success;
  return ToastKind.info;
}

class _ToastData {
  _ToastData(this.text, this.kind, this.action, this.onAction);
  final String text;
  final ToastKind kind;
  final String? action;
  final VoidCallback? onAction;
  final Key key = UniqueKey();
}

final ValueNotifier<List<_ToastData>> _toasts = ValueNotifier(const []);
OverlayEntry? _host;
OverlayState? _hostOverlay;

/// โชว์แจ้งเตือน · [action] = ปุ่มสั้น ๆ ท้ายข้อความ (เช่น "เลิกทำ")
void showToast(BuildContext context, String text,
    {ToastKind? kind, String? action, VoidCallback? onAction}) {
  if (!context.mounted) return;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  if (_host == null || !_host!.mounted || _hostOverlay != overlay) {
    _toasts.value = const [];
    _host = OverlayEntry(builder: (_) => const _ToastHost());
    _hostOverlay = overlay;
    overlay.insert(_host!);
  }
  final list = [..._toasts.value, _ToastData(text, kind ?? guessToastKind(text), action, onAction)];
  _toasts.value = list.length > 3 ? list.sublist(list.length - 3) : list;
}

void _remove(_ToastData d) => _toasts.value = [for (final t in _toasts.value) if (t != d) t];

class _ToastHost extends StatelessWidget {
  const _ToastHost();

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top + 12;
    return Positioned(
      top: top,
      left: 16,
      right: 16,
      child: ValueListenableBuilder(
        valueListenable: _toasts,
        builder: (ctx, list, _) => Column(
          mainAxisSize: MainAxisSize.min,
          children: [for (final t in list) _ToastPill(key: t.key, data: t)],
        ),
      ),
    );
  }
}

class _ToastPill extends StatefulWidget {
  const _ToastPill({super.key, required this.data});
  final _ToastData data;

  @override
  State<_ToastPill> createState() => _ToastPillState();
}

class _ToastPillState extends State<_ToastPill> with SingleTickerProviderStateMixin {
  late final AnimationController _in =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  Timer? _timer;
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    _later();
  }

  // ผิดพลาด = ค้างไว้จนกดปิด (ไม่อยากให้พลาดข้อความ)
  void _later() {
    _timer?.cancel();
    if (widget.data.kind == ToastKind.error) return;
    _timer = Timer(const Duration(milliseconds: 2500), () {
      if (!_hover) _close();
    });
  }

  Future<void> _close() async {
    _timer?.cancel();
    if (!mounted) return;
    await _in.reverse();
    _remove(widget.data);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final d = widget.data;
    final dot = switch (d.kind) {
      ToastKind.success => c.good,
      ToastKind.info => c.accent,
      ToastKind.warn => c.warn,
      ToastKind.error => c.bad,
    };
    return FadeTransition(
      opacity: _in,
      child: SlideTransition(
        position: Tween(begin: const Offset(0, -0.3), end: Offset.zero)
            .animate(CurvedAnimation(parent: _in, curve: Curves.easeOut)),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: MouseRegion(
            onEnter: (_) => _hover = true,
            onExit: (_) {
              _hover = false;
              _later();
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Material(
                key: const Key('toast'),
                color: c.surface2,
                elevation: 6,
                shadowColor: Colors.black54,
                shape: StadiumBorder(side: BorderSide(color: c.line)),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(14, 6, d.action == null && d.kind != ToastKind.error ? 16 : 4, 6),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(d.text,
                          maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.text)),
                    ),
                    if (d.action != null)
                      TextButton(
                        onPressed: () {
                          d.onAction?.call();
                          _close();
                        },
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        child: Text(d.action!, style: TextStyle(color: c.accent, fontWeight: FontWeight.w600)),
                      )
                    else if (d.kind == ToastKind.error)
                      IconButton(
                        tooltip: 'ปิด',
                        visualDensity: VisualDensity.compact,
                        iconSize: 16,
                        onPressed: _close,
                        icon: Icon(Icons.close, color: c.muted),
                      ),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
