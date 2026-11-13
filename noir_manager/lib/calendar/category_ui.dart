import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'calendar_listener.dart';
import 'calendar_models.dart';
import 'calendar_repository.dart';
import 'calendar_ui.dart';

/// ฟอร์มสร้าง / แก้หมวด · คืนหมวดใหม่ (id = 0 ถ้าสร้างใหม่) หรือ null ถ้ายกเลิก
Future<ActivityCategory?> showCategoryEditor(BuildContext context,
    {ActivityCategory? existing, required List<ActivityCategory> all}) {
  final name = TextEditingController(text: existing?.name ?? '');
  var color = existing?.colorKey ?? 'pink';
  var icon = existing?.icon ?? '📌';
  var importance = existing?.defaultImportance ?? 2;
  var minutes = existing?.defaultMinutes ?? 60;
  var replaceable = existing?.replaceable ?? true;
  var lock = existing?.lockOnStart ?? false;
  var group = existing?.statsGroup ?? 'other';
  String? error;

  return showMiniForm<ActivityCategory>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      final accent = categoryAccent(color);
      void save() {
        final n = name.text.trim();
        if (n.isEmpty) {
          setLocal(() => error = 'ใส่ชื่อหมวด');
          return;
        }
        if (all.any((x) => x.id != existing?.id && x.name.trim().toLowerCase() == n.toLowerCase())) {
          setLocal(() => error = 'มีหมวด "$n" แล้ว');
          return;
        }
        Navigator.pop(
          ctx,
          ActivityCategory(
            id: existing?.id ?? 0,
            name: n,
            colorKey: color,
            systemKey: existing?.systemKey,
            icon: icon,
            defaultImportance: importance,
            defaultMinutes: minutes,
            replaceable: replaceable,
            lockOnStart: lock,
            statsGroup: group,
            hidden: existing?.hidden ?? false,
          ),
        );
      }

      return MiniForm(
        title: existing == null ? 'สร้างหมวดใหม่' : 'แก้หมวด',
        primaryLabel: existing == null ? 'สร้าง' : 'บันทึก',
        onPrimary: save,
        children: [
          // ตัวอย่างไอคอนจริงข้างชื่อ (เปลี่ยนสี/ไอคอนแล้วเห็นทันที)
          Row(children: [
            CategoryIcon(
                ActivityCategory(id: 0, name: '', colorKey: color, icon: icon), size: 42),
            const SizedBox(width: 12),
            Expanded(
              child: MiniBigField(
                key: const Key('cat-name'),
                controller: name,
                hint: 'ชื่อหมวด เช่น อ่านหนังสือ',
                onChanged: (_) {
                  if (error != null) setLocal(() => error = null);
                },
                onSubmitted: (_) => save(),
              ),
            ),
          ]),
          if (error != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text(error!, style: TextStyle(fontSize: 12, color: c.bad))),
          const MiniLabel('สี'),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final k in categoryColorKeys)
              InkWell(
                key: Key('cat-color-$k'),
                customBorder: const CircleBorder(),
                onTap: () => setLocal(() => color = k),
                child: Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: categoryAccent(k),
                    shape: BoxShape.circle,
                    border: k == color ? Border.all(color: c.text, width: 3) : null,
                  ),
                ),
              ),
          ]),
          const MiniLabel('ไอคอน'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final e in categoryIcons)
              Material(
                color: e == icon ? accent : c.surface2,
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  key: Key('cat-icon-$e'),
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setLocal(() => icon = e),
                  child: SizedBox(width: 38, height: 38, child: Center(child: Text(e, style: const TextStyle(fontSize: 18)))),
                ),
              ),
          ]),
          const MiniLabel('ค่าเริ่มต้นตอนเลือกหมวดนี้'),
          MiniSegments<int>(
            value: importance,
            items: const [(1, 'น้อย'), (2, 'กลาง'), (3, 'สำคัญ')],
            onChanged: (v) => setLocal(() => importance = v),
          ),
          const SizedBox(height: 6),
          MiniSegments<int>(
            value: minutes,
            items: const [(30, '30 น.'), (60, '1 ชม.'), (90, '1.5 ชม.'), (120, '2 ชม.'), (180, '3 ชม.')],
            onChanged: (v) => setLocal(() => minutes = v),
          ),
          const MiniLabel('นับในสถิติเป็น'),
          MiniSegments<String>(
            value: group,
            items: [for (final (k, n) in statsGroups) (k, n)],
            onChanged: (v) => setLocal(() => group = v),
          ),
          const SizedBox(height: 6),
          MiniSwitchRow(
            icon: Icons.swap_horiz,
            label: 'แทนได้',
            detail: 'ติวจองทับได้ (⇄)',
            value: replaceable,
            onChanged: (v) => setLocal(() => replaceable = v),
          ),
          MiniSwitchRow(
            icon: Icons.lock_outline,
            label: 'ล็อกเมื่อเริ่ม',
            detail: 'แก้งานที่เริ่มแล้วต้องยืนยัน',
            value: lock,
            last: true,
            onChanged: (v) => setLocal(() => lock = v),
          ),
        ],
      );
    }),
  );
}

/// สร้างหมวดใหม่แล้วบันทึกลงฐานข้อมูล · คืนหมวดพร้อม id จริง
Future<ActivityCategory?> createCategoryFlow(BuildContext context, CalendarRepository repo) async {
  final all = await repo.categories();
  if (!context.mounted) return null;
  final made = await showCategoryEditor(context, all: all);
  if (made == null) return null;
  final id = await repo.addCategory(made);
  return made.copyWith(id: id);
}

/// หน้าตั้งค่า › หมวดงาน: รายการ (ไอคอนบนป้ายสี · จำนวนงาน) · ⋮ = แก้ · ซ่อน · ลบ
class CategorySettings extends StatefulWidget {
  const CategorySettings({super.key});

  @override
  State<CategorySettings> createState() => _CategorySettingsState();
}

class _CategorySettingsState extends State<CategorySettings> with CalendarListener<CategorySettings> {
  List<ActivityCategory> _cats = const [];
  Map<int, int> _usage = const {};

  @override
  Future<void> reload() async {
    final repo = calendar!;
    final cats = await repo.categories();
    final usage = await repo.categoryUsage();
    if (mounted) {
      setState(() {
        _cats = cats;
        _usage = usage;
      });
    }
  }

  Future<void> _edit(ActivityCategory cat) async {
    final repo = calendar!;
    final res = await showCategoryEditor(context, existing: cat, all: _cats);
    if (res != null) await repo.updateCategory(res);
  }

  Future<void> _delete(ActivityCategory cat) async {
    final repo = calendar!;
    final n = _usage[cat.id] ?? 0;
    int? moveTo;
    if (n > 0) {
      final others = _cats.where((x) => x.id != cat.id).toList();
      final pick = await showMiniChoice<int>(context, title: 'หมวด "${cat.name}" มี $n งาน · ย้ายงานไปหมวดไหน?', items: [
        for (final o in others) miniChoice(o.id, o.name),
        miniChoice(0, 'ไม่มีหมวด'),
      ]);
      if (pick == null) return;
      moveTo = pick == 0 ? null : pick;
    } else {
      if (!mounted) return;
      final ok = await confirmMini(context, title: 'ลบหมวด "${cat.name}"?', message: 'ยังไม่มีงานในหมวดนี้', okLabel: 'ลบ', danger: true);
      if (!ok) return;
    }
    await repo.deleteCategory(cat.id, moveTo: moveTo);
  }

  Future<void> _menu(ActivityCategory cat, Offset at) async {
    final repo = calendar!;
    final pick = await showContextMenuAt<String>(context, at, [
      ctxItem('edit', Icons.edit_outlined, 'แก้ไข'),
      ctxItem('hide', cat.hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined, cat.hidden ? 'เลิกซ่อน' : 'ซ่อน'),
      if (!cat.isSystem) ctxItem('delete', Icons.delete_outline, 'ลบ', danger: true),
    ]);
    switch (pick) {
      case 'edit':
        await _edit(cat);
      case 'hide':
        await repo.updateCategory(ActivityCategory(
          id: cat.id,
          name: cat.name,
          colorKey: cat.colorKey,
          systemKey: cat.systemKey,
          icon: cat.icon,
          defaultImportance: cat.defaultImportance,
          defaultMinutes: cat.defaultMinutes,
          replaceable: cat.replaceable,
          lockOnStart: cat.lockOnStart,
          statsGroup: cat.statsGroup,
          hidden: !cat.hidden,
        ));
      case 'delete':
        await _delete(cat);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final cat in _cats)
        Builder(
          builder: (rowCtx) => GestureDetector(
            onSecondaryTapDown: (d) => _menu(cat, d.globalPosition),
            child: MiniRow(
              key: Key('cat-row-${cat.id}'),
              iconWidget: Opacity(opacity: cat.hidden ? 0.4 : 1, child: CategoryIcon(cat)),
              label: '',
              value: Row(children: [
                Expanded(
                  child: Text(
                    '${cat.name}${cat.isSystem ? ' · ระบบ' : ''}${cat.hidden ? ' · ซ่อน' : ''}',
                    style: TextStyle(color: cat.hidden ? c.muted : c.text),
                  ),
                ),
                Text('${_usage[cat.id] ?? 0} งาน', style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
              trailing: IconButton(
                key: Key('cat-menu-${cat.id}'),
                tooltip: 'ตัวเลือก',
                icon: const Icon(Icons.more_vert, size: 20),
                onPressed: () {
                  final box = rowCtx.findRenderObject() as RenderBox;
                  _menu(cat, box.localToGlobal(box.size.centerRight(Offset.zero)));
                },
              ),
              onTap: () => _edit(cat),
            ),
          ),
        ),
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('cat-create'),
          onPressed: () => createCategoryFlow(context, calendar!),
          icon: const Icon(Icons.add),
          label: const Text('สร้างหมวดใหม่'),
        ),
      ),
      Text('⋮ / คลิกขวา = แก้ · ซ่อน · ลบ · ลบหมวดที่มีงาน → ถามก่อนว่าจะย้ายงานไปหมวดไหน · หมวดระบบ (เรียน) แก้ได้ ลบไม่ได้',
          style: TextStyle(fontSize: 11, color: c.muted)),
    ]);
  }
}
