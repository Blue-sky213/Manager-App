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

  /// เพิ่มสติกเกอร์: อีโมจิ 1 ตัว หรือรูปของตัวเอง **กี่รูปก็ได้** (ชื่อ = ชื่อไฟล์) · เห็นตัวอย่างก่อนเพิ่ม
  /// ไม่ระบุชุด → ลง "สติกเกอร์ของฉัน" (สร้างให้ถ้ายังไม่มี)
  Future<void> _addSticker([StickerPack? pack]) async {
    final repo = calendar!;
    final emoji = TextEditingController();
    final name = TextEditingController();
    final images = <String>[]; // รูปที่เลือก (ยังไม่ย่อ)
    final picked = <String>{}; // รูปที่ติ๊กไว้ (แตะเพื่อเลือก / ไม่เลือก)
    var showErr = false;
    String? emojiErr() {
      if (picked.isNotEmpty) return null;
      final t = emoji.text.trim();
      if (t.isEmpty) return showErr ? 'ใส่อีโมจิ 1 ตัว หรือเลือกรูป' : null;
      return t.characters.length == 1 ? null : 'ใส่ได้ 1 ตัว';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final c = ctx.noir;
          final n = picked.length;
          return AlertDialog(
            title: Text(pack == null ? 'เพิ่มสติกเกอร์' : 'เพิ่มลงชุด "${pack.name}"'),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final more = await pickImages(many: true);
                        if (more.isEmpty) return;
                        setLocal(() {
                          for (final f in more) {
                            if (!images.contains(f)) images.add(f);
                            picked.add(f);
                          }
                        });
                      },
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(images.isEmpty ? 'เลือกรูป (เลือกได้หลายรูป)' : 'เลือกรูปเพิ่ม'),
                    ),
                  ),
                  if (images.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('แตะรูปเพื่อเลือก / ไม่เลือก · ชื่อ = ชื่อไฟล์ (แก้ทีหลังได้)',
                        style: TextStyle(fontSize: 12, color: c.muted)),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final f in images)
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setLocal(() => picked.contains(f) ? picked.remove(f) : picked.add(f)),
                          child: Container(
                            width: 64,
                            height: 64,
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: c.surface2,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: picked.contains(f) ? c.accent : Colors.transparent, width: 2),
                            ),
                            child: Stack(children: [
                              Center(child: Image.file(File(f), fit: BoxFit.contain)),
                              if (picked.contains(f))
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  child: Icon(Icons.check_circle, size: 16, color: c.accent),
                                ),
                            ]),
                          ),
                        ),
                    ]),
                  ],
                  if (picked.isEmpty) ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: emoji,
                      style: const TextStyle(fontSize: 28),
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: 'หรือใส่อีโมจิ',
                        hintText: '🐱',
                        helperText: 'Windows กด Win + .',
                        errorText: emojiErr(),
                      ),
                    ),
                    TextField(
                      controller: name,
                      onChanged: (_) => setLocal(() {}),
                      decoration: InputDecoration(
                        labelText: 'ชื่อ *',
                        hintText: 'เช่น อยากนอน',
                        errorText: showErr && name.text.trim().isEmpty ? 'ใส่ชื่อ' : null,
                      ),
                    ),
                  ],
                ]),
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
              FilledButton(
                onPressed: () {
                  showErr = true;
                  if (picked.isEmpty &&
                      (emojiErr() != null || emoji.text.trim().isEmpty || name.text.trim().isEmpty)) {
                    setLocal(() {});
                    return;
                  }
                  Navigator.pop(ctx, true);
                },
                child: Text(n > 0 ? 'เพิ่ม $n ชิ้น' : 'เพิ่ม'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    var packId = pack?.id;
    if (packId == null) {
      final mine = _packs.where((p) => !p.builtin && p.name == myStickerPackName).firstOrNull;
      packId = mine?.id ?? await repo.addStickerPack(myStickerPackName);
    }
    if (picked.isEmpty) {
      await repo.addSticker(packId, name.text.trim(), emoji: emoji.text.trim());
      return;
    }
    final dir = await stickerFolder();
    for (final f in images.where(picked.contains)) {
      await repo.addSticker(packId, stickerNameFromFile(f), imagePath: await saveStickerImage(f, dir));
    }
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

  /// แผ่นรายละเอียดชุด: ตารางรูปล้วน (ชี้ / กดค้าง = ชื่อ) · กด "แก้ไข" ถึงขึ้น ✕ + ลบทั้งชุด
  Future<void> _openPack(StickerPack pack) async {
    final repo = calendar!;
    var editing = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
        final c = ctx.noir;
        // อ่านชุดล่าสุดทุกครั้ง (ลบชิ้นแล้วตารางอัปเดต)
        final p = _packs.where((x) => x.id == pack.id).firstOrNull ?? pack;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(p.name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
              ),
              if (!p.builtin)
                TextButton(
                  onPressed: () => setLocal(() => editing = !editing),
                  child: Text(editing ? 'เสร็จ' : 'แก้ไข'),
                ),
            ]),
            Text('${p.stickers.length} ชิ้น · ชี้ / กดค้าง = ดูชื่อ', style: TextStyle(fontSize: 12, color: c.muted)),
            const SizedBox(height: 12),
            Flexible(
              child: SingleChildScrollView(
                child: Wrap(spacing: 10, runSpacing: 10, children: [
                  for (final st in p.stickers)
                    Tooltip(
                      message: st.name,
                      triggerMode: TooltipTriggerMode.longPress,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(12)),
                          child: StickerGlyph(st, size: 36),
                        ),
                        if (editing)
                          Positioned(
                            right: -6,
                            top: -6,
                            child: InkWell(
                              key: ValueKey('del-sticker-${st.id}'),
                              onTap: () async {
                                await repo.deleteSticker(st.id);
                                await reload();
                                setLocal(() {});
                              },
                              child: CircleAvatar(
                                radius: 10,
                                backgroundColor: c.bad,
                                child: const Icon(Icons.close, size: 13, color: Colors.white),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  if (!p.builtin)
                    InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () async {
                        await _addSticker(p);
                        await reload();
                        setLocal(() {});
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          border: Border.all(color: c.line2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.add, color: c.accent),
                      ),
                    ),
                ]),
              ),
            ),
            if (editing && !p.builtin) ...[
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: c.bad),
                  onPressed: () async {
                    if (await confirmDelete(ctx, p.name)) {
                      await repo.deleteStickerPack(p.id);
                      if (ctx.mounted) Navigator.pop(ctx);
                    }
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('ลบทั้งชุด'),
                ),
              ),
            ],
          ]),
        );
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: _addSticker, icon: const Icon(Icons.add_reaction_outlined), label: const Text('เพิ่มสติกเกอร์')),
        OutlinedButton.icon(onPressed: _addPack, icon: const Icon(Icons.create_new_folder_outlined), label: const Text('ชุดใหม่')),
        OutlinedButton.icon(
            onPressed: _packFromImages, icon: const Icon(Icons.photo_library_outlined), label: const Text('ชุดจากรูป')),
      ]),
      const SizedBox(height: 8),
      // ชุดละแถว: ชื่อ · จำนวน · รูปตัวอย่าง 5 รูป · สวิตช์ · แตะ = ดูทั้งชุด / แก้ไข
      for (final p in _packs)
        GestureDetector(
          onSecondaryTapUp: (e) => _packMenu(p, e.globalPosition),
          onLongPressStart: (e) => _packMenu(p, e.globalPosition),
          child: InkWell(
            key: ValueKey('pack-${p.id}'),
            borderRadius: BorderRadius.circular(10),
            onTap: () => _openPack(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, color: p.enabled ? c.text : c.muted)),
                    Text('${p.stickers.length} ชิ้น · ${p.builtin ? 'ในแอป' : 'ของฉัน'}',
                        style: TextStyle(fontSize: 12, color: c.muted)),
                  ]),
                ),
                Opacity(
                  opacity: p.enabled ? 1 : 0.4,
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    for (final st in p.stickers.take(5))
                      Padding(padding: const EdgeInsets.only(left: 2), child: StickerGlyph(st, size: 22)),
                    if (p.stickers.length > 5)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Text('+${p.stickers.length - 5}', style: TextStyle(fontSize: 12, color: c.muted)),
                      ),
                  ]),
                ),
                Switch(value: p.enabled, onChanged: (v) => calendar!.setStickerPackEnabled(p.id, v)),
              ]),
            ),
          ),
        ),
      Text('แตะชุด = ดูทั้งหมด · แก้ไข / ลบ อยู่ในนั้น (ชุดในแอปซ่อนได้ แต่ลบไม่ได้)',
          style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }
}
