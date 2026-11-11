import 'dart:io';

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import 'calendar_listener.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'sticker_images.dart';

/// วาดสติกเกอร์ 1 ชิ้น: รูป (ถ้ามี) หรืออีโมจิ · ขนาดสี่เหลี่ยม [size]
class StickerGlyph extends StatelessWidget {
  const StickerGlyph(this.sticker, {super.key, this.size = 28});
  final Sticker sticker;
  final double size;

  @override
  Widget build(BuildContext context) {
    final emoji = Text(sticker.glyph, style: TextStyle(fontSize: size * 0.85, height: 1.1));
    final path = sticker.imagePath;
    if (path == null) return emoji;
    return SizedBox(
      width: size,
      height: size,
      child: Image.file(
        File(path),
        fit: BoxFit.contain,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).ceil(),
        // ไฟล์หาย (เช่น ย้ายเครื่อง) → ใช้ตัวอักษรแทน ไม่พัง
        errorBuilder: (_, _, _) => emoji,
      ),
    );
  }
}

/// การ์ด "วันนี้รู้สึกยังไง?" — สมุดแปะสติกเกอร์ของวัน
/// คลิกสติกเกอร์ที่แปะ = เขียนโน้ต · คลิกขวา / กดค้าง = เขียนโน้ต / ลอกออก
class DayStickerCard extends StatefulWidget {
  const DayStickerCard({super.key, required this.day});
  final DateTime day;

  @override
  State<DayStickerCard> createState() => _DayStickerCardState();
}

class _DayStickerCardState extends State<DayStickerCard> with CalendarListener<DayStickerCard> {
  List<DaySticker> _items = const [];

  @override
  Future<void> reload() async {
    final items = await calendar!.daySticker(widget.day, widget.day);
    if (mounted) setState(() => _items = items);
  }

  @override
  void didUpdateWidget(DayStickerCard old) {
    super.didUpdateWidget(old);
    if (old.day != widget.day) reload();
  }

  Future<void> _note(DaySticker d) async {
    final repo = calendar!;
    final text = await askText(context,
        title: '${d.sticker.name} · เพราะอะไร?',
        label: 'โน้ตสั้น ๆ (ไม่ใส่ก็ได้)',
        initial: d.note ?? '',
        confirmLabel: 'บันทึก');
    if (text == null) return;
    // แก้โน้ต = แปะใหม่แทนอันเดิม (ลำดับเดิมไม่สำคัญ)
    await repo.unstickDay(d.id);
    await repo.stickDay(widget.day, d.sticker.id, note: text.trim().isEmpty ? null : text.trim());
  }

  Future<void> _menu(DaySticker d, Offset at) async {
    final repo = calendar!;
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('note', Icons.edit_note, 'เขียนโน้ต'),
      ctxItem('remove', Icons.close, 'ลอกออก', danger: true),
    ]);
    if (!mounted) return;
    if (v == 'note') {
      await _note(d);
    } else if (v == 'remove') {
      await repo.unstickDay(d.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('วันนี้รู้สึกยังไง?', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
            ),
            TextButton.icon(
              onPressed: () => showStickerPicker(context, calendar!, widget.day),
              icon: const Icon(Icons.add_reaction_outlined),
              label: const Text('แปะ'),
            ),
          ]),
          if (_items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 4),
              child: Text('ยังไม่ได้แปะ · เลือกสติกเกอร์ที่ตรงกับวันนี้', style: TextStyle(fontSize: 13, color: c.muted)),
            )
          else
            Wrap(spacing: 10, runSpacing: 8, children: [
              for (final d in _items)
                GestureDetector(
                  onSecondaryTapUp: (e) => _menu(d, e.globalPosition),
                  onLongPressStart: (e) => _menu(d, e.globalPosition),
                  child: Tooltip(
                    // มีโน้ตเท่านั้นถึงขึ้น (ชื่ออยู่ใต้สติกเกอร์แล้ว ไม่ซ้ำ)
                    message: d.note ?? '',
                    // กดค้าง = เมนู (ไม่ให้ tooltip แย่ง) · เมาส์ชี้ยังเห็นโน้ต
                    triggerMode: TooltipTriggerMode.manual,
                    child: InkWell(
                      onTap: () => _note(d),
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          StickerGlyph(d.sticker, size: 34),
                          Text(d.sticker.name, style: TextStyle(fontSize: 12, color: c.muted)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
        ]),
      ),
    );
  }
}

/// เลือกสติกเกอร์จากทุกชุดที่เปิดอยู่ แล้วแปะในวัน [day]
Future<void> showStickerPicker(BuildContext context, CalendarRepository repo, DateTime day) async {
  final packs = (await repo.stickerPacks()).where((p) => p.enabled && p.stickers.isNotEmpty).toList();
  if (!context.mounted) return;
  final picked = await showDialog<Sticker>(
    context: context,
    builder: (ctx) {
      final c = ctx.noir;
      return AlertDialog(
        title: Text('แปะสติกเกอร์ · ${thaiShortDate(day)}'),
        content: SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final p in packs) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 6),
                  child: Text(p.name, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.muted)),
                ),
                Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final s in p.stickers)
                    Tooltip(
                      message: s.name,
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, s),
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          width: 72,
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: c.surface2,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(children: [
                            StickerGlyph(s, size: 32),
                            Text(s.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 11, color: c.text)),
                          ]),
                        ),
                      ),
                    ),
                ]),
              ],
              if (packs.isEmpty) Text('ทุกชุดถูกซ่อนอยู่ · เปิดได้ในตั้งค่า → สติกเกอร์', style: TextStyle(color: c.muted)),
            ]),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ปิด'))],
      );
    },
  );
  if (picked != null) await repo.stickDay(dayOnly(day), picked.id);
}

/// ตั้งค่า → สติกเกอร์: เปิด/ซ่อนชุด · ชุดใหม่ · เพิ่มทีละชิ้น · ลบของที่สร้างเอง
class StickerSettings extends StatefulWidget {
  const StickerSettings({super.key});

  @override
  State<StickerSettings> createState() => _StickerSettingsState();
}

class _StickerSettingsState extends State<StickerSettings> with CalendarListener<StickerSettings> {
  List<StickerPack> _packs = const [];

  @override
  Future<void> reload() async {
    final packs = await calendar!.stickerPacks();
    if (mounted) setState(() => _packs = packs);
  }

  Future<void> _addPack() async {
    final repo = calendar!;
    final name = await askText(context, title: 'ชุดสติกเกอร์ใหม่', label: 'ชื่อชุด', confirmLabel: 'สร้าง');
    if (name == null || name.trim().isEmpty) return;
    await repo.addStickerPack(name.trim());
  }

  /// เพิ่มทีละชิ้น: อีโมจิ หรือรูปของตัวเอง · ไม่ระบุชุด → ลง "สติกเกอร์ของฉัน" (สร้างให้ถ้ายังไม่มี)
  Future<void> _addSticker([StickerPack? pack]) async {
    final repo = calendar!;
    final emoji = TextEditingController();
    final name = TextEditingController();
    String? image; // รูปที่เลือก (ยังไม่ย่อ)
    var showErr = false;
    String? emojiErr() {
      if (image != null) return null;
      final t = emoji.text.trim();
      if (t.isEmpty) return showErr ? 'ใส่อีโมจิ 1 ตัว หรือเลือกรูป' : null;
      return t.characters.length == 1 ? null : 'ใส่ได้ 1 ตัว';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(pack == null ? 'เพิ่มสติกเกอร์ 1 ชิ้น' : 'เพิ่มสติกเกอร์ในชุด "${pack.name}"'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: TextField(
                    controller: emoji,
                    enabled: image == null,
                    style: const TextStyle(fontSize: 28),
                    onChanged: (_) => setLocal(() {}),
                    decoration: InputDecoration(
                      labelText: 'อีโมจิ',
                      hintText: '🐱',
                      helperText: 'Windows กด Win + .',
                      errorText: emojiErr(),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Column(children: [
                  if (image != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(File(image!), width: 56, height: 56, fit: BoxFit.contain),
                    ),
                  TextButton.icon(
                    onPressed: () async {
                      final picked = await pickImages();
                      if (picked.isEmpty) return;
                      setLocal(() {
                        image = picked.first;
                        if (name.text.trim().isEmpty) name.text = stickerNameFromFile(picked.first);
                      });
                    },
                    icon: const Icon(Icons.image_outlined),
                    label: Text(image == null ? 'เลือกรูป' : 'เปลี่ยนรูป'),
                  ),
                ]),
              ]),
              TextField(
                controller: name,
                onChanged: (_) => setLocal(() {}),
                decoration: InputDecoration(
                  labelText: 'ชื่อ *',
                  hintText: 'เช่น อยากนอน',
                  errorText: showErr && name.text.trim().isEmpty ? 'ใส่ชื่อ' : null,
                ),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () {
                showErr = true;
                if (emojiErr() != null || (image == null && emoji.text.trim().isEmpty) || name.text.trim().isEmpty) {
                  setLocal(() {});
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: const Text('เพิ่ม'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    var packId = pack?.id;
    if (packId == null) {
      final mine = _packs.where((p) => !p.builtin && p.name == myStickerPackName).firstOrNull;
      packId = mine?.id ?? await repo.addStickerPack(myStickerPackName);
    }
    final saved = image == null ? null : await saveStickerImage(image!, await stickerFolder());
    await repo.addSticker(packId, name.text.trim(), emoji: saved == null ? emoji.text.trim() : null, imagePath: saved);
  }

  /// ชุดจากรูป: เลือกหลายรูป → ตั้งชื่อชุด → ทุกรูปเป็นสติกเกอร์ (ชื่อ = ชื่อไฟล์)
  Future<void> _packFromImages() async {
    final repo = calendar!;
    final picked = await pickImages(many: true);
    if (picked.isEmpty || !mounted) return;
    final name = await askText(context,
        title: 'ชุดใหม่จาก ${picked.length} รูป', label: 'ชื่อชุด', confirmLabel: 'สร้างชุด');
    if (name == null || name.trim().isEmpty) return;
    final dir = await stickerFolder();
    final packId = await repo.addStickerPack(name.trim());
    for (final f in picked) {
      final saved = await saveStickerImage(f, dir);
      await repo.addSticker(packId, stickerNameFromFile(f), imagePath: saved);
    }
  }

  Future<void> _packMenu(StickerPack p, Offset at) async {
    final repo = calendar!;
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('add', Icons.add, 'เพิ่มสติกเกอร์ในชุดนี้'),
      if (!p.builtin) ctxItem('delete', Icons.delete_outline, 'ลบชุดนี้', danger: true),
    ]);
    if (!mounted) return;
    if (v == 'add') {
      await _addSticker(p);
    } else if (v == 'delete' && await confirmDelete(context, p.name)) {
      await repo.deleteStickerPack(p.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _addSticker, icon: const Icon(Icons.add_reaction_outlined), label: const Text('เพิ่มทีละชิ้น')),
        OutlinedButton.icon(onPressed: _addPack, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('ชุดใหม่')),
        OutlinedButton.icon(
            onPressed: _packFromImages, icon: const Icon(Icons.photo_library_outlined), label: const Text('ชุดจากรูป')),
      ]),
      const SizedBox(height: 8),
      for (final p in _packs)
        GestureDetector(
          onSecondaryTapUp: (e) => _packMenu(p, e.globalPosition),
          onLongPressStart: (e) => _packMenu(p, e.globalPosition),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(
                  child: Text('${p.name}${p.builtin ? '' : ' · ของฉัน'}',
                      style: TextStyle(fontWeight: FontWeight.w600, color: p.enabled ? c.text : c.muted)),
                ),
                Switch(
                  value: p.enabled,
                  onChanged: (v) => calendar!.setStickerPackEnabled(p.id, v),
                ),
              ]),
              Wrap(spacing: 4, runSpacing: 4, children: [
                for (final s in p.stickers)
                  p.builtin
                      ? Tooltip(message: s.name, child: StickerGlyph(s, size: 26))
                      : InputChip(
                          avatar: StickerGlyph(s, size: 20),
                          label: Text(s.name),
                          onDeleted: () => calendar!.deleteSticker(s.id),
                          deleteButtonTooltipMessage: 'ลบสติกเกอร์นี้',
                        ),
                if (!p.builtin)
                  ActionChip(avatar: const Icon(Icons.add, size: 16), label: const Text('เพิ่ม'), onPressed: () => _addSticker(p)),
              ]),
            ]),
          ),
        ),
      Text('คลิกขวา / กดค้างที่ชุด = เพิ่มสติกเกอร์ · ลบชุด (ชุดในแอปซ่อนได้ แต่ลบไม่ได้)',
          style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }
}
