/// ปรับสติกเกอร์ให้พอดี (รอบ 8B): ซูม + ลากเลื่อน + พอดีอัตโนมัติ · เห็นหน้าตาจริงในช่องวันทันที
/// ใช้ตอนเพิ่มรูป (ครั้งแรก) และปรับทีหลัง (ตั้งค่า › สติกเกอร์ · สมุดสติกเกอร์ คลิกขวา)
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'calendar_repository.dart';
import 'sticker_images.dart';
import 'sticker_ui.dart';

const _stage = 220.0;

/// เปิดตัวปรับ · บันทึกแล้วคืน true
Future<bool> showStickerFitEditor(BuildContext context, CalendarRepository repo, Sticker sticker) async {
  var scale = sticker.scale, dx = sticker.dx, dy = sticker.dy;
  final saved = await showMiniForm<bool>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      final s = sticker.withFit(scale, dx, dy);
      return MiniForm(
        title: 'ปรับ "${sticker.name}" ให้พอดี',
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, true),
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          Center(
            child: GestureDetector(
              key: const Key('fit-stage'),
              onPanUpdate: (d) => setLocal(() {
                dx = (dx + d.delta.dx / _stage).clamp(-0.5, 0.5);
                dy = (dy + d.delta.dy / _stage).clamp(-0.5, 0.5);
              }),
              child: Container(
                width: _stage,
                height: _stage,
                decoration: BoxDecoration(
                  color: c.surface2,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: c.line),
                ),
                child: Stack(alignment: Alignment.center, children: [
                  StickerGlyph(s, size: _stage),
                  // วงประ = พื้นที่ที่ควรอยู่ (ช่องวันโชว์ทั้งกรอบ แต่ขอบอาจถูกไอคอนอื่นทับ)
                  IgnorePointer(
                    child: Container(
                      margin: const EdgeInsets.all(_stage * 0.1),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: c.accent.withValues(alpha: 0.7), width: 1.5),
                      ),
                    ),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Center(child: Text('ลากภาพเพื่อเลื่อน', style: TextStyle(fontSize: 12, color: c.muted))),
          const SizedBox(height: 8),
          Row(children: [
            Text('ซูม', style: TextStyle(color: c.text)),
            Expanded(
              child: Slider(
                key: const Key('fit-zoom'),
                min: 0.5,
                max: 2.5,
                value: scale.clamp(0.5, 2.5),
                onChanged: (v) => setLocal(() => scale = v),
              ),
            ),
            SizedBox(width: 48, child: Text('${(scale * 100).round()}%', textAlign: TextAlign.right, style: TextStyle(color: c.muted))),
          ]),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              key: const Key('fit-auto'),
              onPressed: sticker.imagePath == null
                  ? null
                  : () async {
                      final f = await autoFitImage(sticker.imagePath!);
                      if (f != null) setLocal(() => (scale, dx, dy) = f);
                    },
              icon: const Icon(Icons.auto_fix_high, size: 18),
              label: const Text('พอดีอัตโนมัติ'),
            ),
            OutlinedButton(
              key: const Key('fit-reset'),
              onPressed: () => setLocal(() => (scale, dx, dy) = (1.0, 0.0, 0.0)),
              child: const Text('คืนค่าเดิม'),
            ),
          ]),
          const SizedBox(height: 12),
          const MiniLabel('หน้าตาในช่องวัน'),
          Row(children: [
            _cell(c, '14', StickerGlyph(s, size: 64)),
            const SizedBox(width: 10),
            _cell(c, '15', Align(alignment: const Alignment(0.75, 0.75), child: StickerGlyph(s, size: 30))),
          ]),
        ],
      );
    }),
  );
  if (saved != true) return false;
  await repo.updateStickerFit(sticker.id, scale: scale, dx: dx, dy: dy);
  return true;
}

Widget _cell(NoirColors c, String day, Widget child) => Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.line),
      ),
      child: Stack(children: [
        Positioned(left: 4, top: 2, child: Text(day, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text))),
        Positioned.fill(child: Center(child: child)),
      ]),
    );

/// พอดีอัตโนมัติให้ทุกรูปใน [stickers] (ข้ามอีโมจิ) · คืนจำนวนที่ปรับ
Future<int> autoFitAll(CalendarRepository repo, Iterable<Sticker> stickers) async {
  var n = 0;
  for (final s in stickers) {
    if (s.imagePath == null) continue;
    final f = await autoFitImage(s.imagePath!);
    if (f == null) continue;
    await repo.updateStickerFit(s.id, scale: f.$1, dx: f.$2, dy: f.$3);
    n++;
  }
  return n;
}

/// หลังเพิ่มรูปหลายชิ้น: พอดีอัตโนมัติให้ทุกรูป แล้วเปิดหน้าตรวจ (แตะรูป = ปรับเอง)
/// 1 ชิ้น = เปิดตัวปรับเลย (ปรับได้ตั้งแต่ครั้งแรก)
Future<void> fitNewStickers(BuildContext context, CalendarRepository repo, List<int> ids) async {
  if (ids.isEmpty) return;
  Future<List<Sticker>> load() async =>
      [for (final p in await repo.stickerPacks()) ...p.stickers.where((s) => ids.contains(s.id))];
  await autoFitAll(repo, await load());
  if (!context.mounted) return;
  var items = await load();
  if (!context.mounted) return;
  if (items.length == 1) {
    await showStickerFitEditor(context, repo, items.single);
    return;
  }
  await showMiniForm<void>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      return MiniForm(
        title: 'ตรวจ ${items.length} ชิ้น',
        primaryLabel: 'เสร็จ',
        onPrimary: () => Navigator.pop(ctx),
        children: [
          Text('พอดีอัตโนมัติให้แล้ว · แตะรูปที่ยังไม่พอดี = ปรับเอง', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in items)
              InkWell(
                key: ValueKey('fit-review-${s.id}'),
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                  if (await showStickerFitEditor(ctx, repo, s)) {
                    items = await load();
                    setLocal(() {});
                  }
                },
                child: Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
                  child: StickerGlyph(s, size: 52),
                ),
              ),
          ]),
        ],
      );
    }),
  );
  if (context.mounted) showToast(context, 'เพิ่ม ${items.length} ชิ้นแล้ว · ปรับอีกได้ที่คลิกขวาที่รูป');
}
