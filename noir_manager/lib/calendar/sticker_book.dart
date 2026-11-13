/// สมุดสติกเกอร์ (รอบ 7 · H): ลากสติกเกอร์จากแผงขวาไปแปะในช่องวันของปฏิทินเดือน
/// ลากผ่านช่อง = ช่องใต้เมาส์ขึ้นกรอบ · ค้างไว้ ~0.5 วิ = ช่องซูมขึ้นให้วางตรงไหนก็ได้ในช่อง
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import 'calendar_listener.dart';
import 'sticker_ui.dart';
import 'stickers.dart';

/// กำลังลากสติกเกอร์อยู่ไหม (ช่องซูมปิดเองเมื่อปล่อย)
final ValueNotifier<bool> stickerDragging = ValueNotifier(false);

/// ขนาดภาพที่ติดเมาส์ตอนลาก
const _feedback = 52.0;

/// แผงสมุดสติกเกอร์: แท็บชุด + ตารางสติกเกอร์ที่ลากได้ · แตะ = แปะวันที่เลือกอยู่
class StickerBook extends StatefulWidget {
  const StickerBook({super.key, required this.onTapSticker});

  final ValueChanged<Sticker> onTapSticker;

  @override
  State<StickerBook> createState() => _StickerBookState();
}

class _StickerBookState extends State<StickerBook> with CalendarListener<StickerBook> {
  List<StickerPack> _packs = const [];
  int _pack = 0;

  @override
  Future<void> reload() async {
    final packs = (await calendar!.stickerPacks()).where((p) => p.enabled && p.stickers.isNotEmpty).toList();
    if (mounted) {
      setState(() {
        _packs = packs;
        if (_pack >= packs.length) _pack = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final pack = _packs.isEmpty ? null : _packs[_pack];
    return Card(
      key: const Key('sticker-book'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('สมุดสติกเกอร์', style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final (i, p) in _packs.indexed)
              ChoiceChip(
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                label: Text(p.name),
                selected: i == _pack,
                onSelected: (_) => setState(() => _pack = i),
              ),
          ]),
          const SizedBox(height: 8),
          if (pack != null)
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in pack.stickers)
                Draggable<Sticker>(
                  key: ValueKey('book-${s.id}'),
                  data: s,
                  dragAnchorStrategy: pointerDragAnchorStrategy,
                  onDragStarted: () => stickerDragging.value = true,
                  onDragEnd: (_) => stickerDragging.value = false,
                  onDraggableCanceled: (_, _) => stickerDragging.value = false,
                  feedback: Transform.translate(
                    offset: const Offset(-_feedback / 2, -_feedback / 2),
                    child: Material(color: Colors.transparent, child: StickerGlyph(s, size: _feedback)),
                  ),
                  childWhenDragging: Opacity(opacity: 0.3, child: _tile(c, s)),
                  child: Tooltip(
                    message: s.name,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => widget.onTapSticker(s),
                      child: _tile(c, s),
                    ),
                  ),
                ),
            ])
          else
            Text('ทุกชุดถูกซ่อนอยู่ · เปิดได้ในตั้งค่า → สติกเกอร์', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 8),
          Text('ลากไปวางในช่องวัน · ค้างไว้ = ช่องซูม วางตรงไหนก็ได้ · แตะ = แปะวันที่เลือก',
              style: TextStyle(fontSize: 11, color: c.muted)),
        ]),
      ),
    );
  }

  Widget _tile(NoirColors c, Sticker s) => Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
        child: Center(child: StickerGlyph(s, size: 32)),
      );
}

/// ช่องวันที่รับสติกเกอร์: ลากผ่าน = กรอบ · ค้าง 0.5 วิ = ช่องซูม · ปล่อย = แปะตรงจุดนั้น (x, y 0–1)
class StickerDropCell extends StatefulWidget {
  const StickerDropCell({
    super.key,
    required this.day,
    required this.child,
    required this.onDrop,
    this.locked,
    this.zoomBuilder,
  });

  final DateTime day;
  final Widget child;

  /// แปะที่ตำแหน่ง (0–1) ในช่อง
  final void Function(Sticker s, double x, double y) onDrop;

  /// ยังแปะไม่ได้ (เช่น งานสำคัญยังไม่ครบ) → ข้อความบอกเหตุผล · null = แปะได้
  final String? Function()? locked;

  /// หน้าตาช่องตอนซูม (ใหญ่ขึ้น) · null = ใช้ [child]
  final WidgetBuilder? zoomBuilder;

  @override
  State<StickerDropCell> createState() => _StickerDropCellState();
}

class _StickerDropCellState extends State<StickerDropCell> {
  bool _hover = false;
  Timer? _hold;
  OverlayEntry? _zoom;

  @override
  void initState() {
    super.initState();
    stickerDragging.addListener(_onDragging);
  }

  @override
  void dispose() {
    stickerDragging.removeListener(_onDragging);
    _hold?.cancel();
    _closeZoom();
    super.dispose();
  }

  void _onDragging() {
    if (!stickerDragging.value) {
      _hold?.cancel();
      _closeZoom();
      if (mounted && _hover) setState(() => _hover = false);
    }
  }

  void _closeZoom() {
    _zoom?.remove();
    _zoom = null;
  }

  (double, double) _rel(RenderBox box, Offset global) {
    final p = box.globalToLocal(global);
    return ((p.dx / box.size.width).clamp(0.08, 0.92), (p.dy / box.size.height).clamp(0.12, 0.92));
  }

  void _openZoom() {
    if (!mounted || _zoom != null || widget.locked?.call() != null) return;
    final box = context.findRenderObject() as RenderBox?;
    final overlay = Overlay.of(context);
    final ob = overlay.context.findRenderObject() as RenderBox?;
    if (box == null || ob == null) return;
    final cell = box.localToGlobal(Offset.zero, ancestor: ob) & box.size;
    final size = Size(box.size.width * 2.4, box.size.height * 2.4);
    final left = (cell.center.dx - size.width / 2).clamp(8.0, ob.size.width - size.width - 8);
    final top = (cell.center.dy - size.height / 2).clamp(8.0, ob.size.height - size.height - 8);
    _zoom = OverlayEntry(
      builder: (ctx) {
        final c = ctx.noir;
        return Positioned(
          left: left,
          top: top,
          width: size.width,
          height: size.height,
          child: DragTarget<Sticker>(
            onAcceptWithDetails: (d) {
              final zb = ctx.findRenderObject() as RenderBox;
              final (x, y) = _rel(zb, d.offset);
              widget.onDrop(d.data, x, y);
              _closeZoom();
            },
            onLeave: (_) => _closeZoom(),
            builder: (ctx, _, _) => Material(
              key: ValueKey('zoom-${widget.day.month}-${widget.day.day}'),
              elevation: 12,
              color: c.surface,
              borderRadius: BorderRadius.circular(16),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: c.accent, width: 2.5),
                  borderRadius: BorderRadius.circular(16),
                  // เส้นตารางจาง ๆ ช่วยเล็งตำแหน่ง
                  gradient: LinearGradient(colors: [c.accent.withValues(alpha: 0.10), c.accent.withValues(alpha: 0.04)]),
                ),
                // ช่องเดิมขยาย 2.4 เท่า (เห็นสติกเกอร์ที่มีอยู่ เลือกที่ว่างได้)
                child: widget.zoomBuilder?.call(ctx) ??
                    IgnorePointer(child: FittedBox(fit: BoxFit.fill, child: SizedBox.fromSize(size: box.size, child: widget.child))),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_zoom!);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return DragTarget<Sticker>(
      onWillAcceptWithDetails: (_) {
        setState(() => _hover = true);
        _hold?.cancel();
        _hold = Timer(const Duration(milliseconds: 500), _openZoom);
        return widget.locked?.call() == null;
      },
      onLeave: (_) {
        _hold?.cancel();
        setState(() => _hover = false);
      },
      onAcceptWithDetails: (d) {
        _hold?.cancel();
        setState(() => _hover = false);
        final box = context.findRenderObject() as RenderBox;
        final (x, y) = _rel(box, d.offset);
        widget.onDrop(d.data, x, y);
      },
      builder: (ctx, _, _) {
        final reason = _hover ? widget.locked?.call() : null;
        return Stack(children: [
          widget.child,
          if (_hover)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  key: ValueKey('drop-hover-${widget.day.month}-${widget.day.day}'),
                  decoration: BoxDecoration(
                    color: (reason == null ? c.accent : c.bad).withValues(alpha: 0.12),
                    border: Border.all(color: reason == null ? c.accent : c.bad, width: 2.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: reason == null
                      ? null
                      : Center(
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Text(reason, textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: c.bad)),
                          ),
                        ),
                ),
              ),
            ),
        ]);
      },
    );
  }
}

/// วาดสติกเกอร์ในช่องวัน: ⭐ ใหญ่กลางช่อง · ชิ้นอื่นเล็กตามตำแหน่งที่วาง (ไม่มีตำแหน่ง = มุมตามลำดับ) · เกิน 4 = +n
class PlacedStickers extends StatelessWidget {
  const PlacedStickers({super.key, required this.items, required this.big, this.tilt = 0});

  final List<DaySticker> items;
  final double big;
  final double tilt;

  static const _slots = [(0.82, 0.82), (0.18, 0.82), (0.82, 0.3), (0.18, 0.3)];

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final hl = highlightOf(items)!;
    final rest = items.where((d) => d.id != hl.id).toList();
    final shown = rest.take(3).toList();
    final small = big * 0.42;
    return LayoutBuilder(builder: (context, box) {
      Widget at(double x, double y, Widget w, double s) =>
          Positioned(left: box.maxWidth * x - s / 2, top: box.maxHeight * y - s / 2, width: s, height: s, child: Center(child: w));
      var slot = 0;
      return Stack(clipBehavior: Clip.none, children: [
        // ⭐ อยู่กลางช่องเสมอ (ตัวที่เห็นชัดที่สุดของวัน)
        at(0.5, 0.55, Transform.rotate(angle: tilt, child: StickerGlyph(hl.sticker, size: big)), big),
        for (final d in shown)
          () {
            final (x, y) = d.x != null && d.y != null ? (d.x!, d.y!) : _slots[slot++ % _slots.length];
            return at(x, y, StickerGlyph(d.sticker, size: small), small);
          }(),
        if (rest.length > 3)
          Positioned(
            right: 2,
            top: 2,
            child: Text('+${rest.length - 3}', style: TextStyle(fontSize: 10, color: context.noir.muted)),
          ),
      ]);
    });
  }
}
