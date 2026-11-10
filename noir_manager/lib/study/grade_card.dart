import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../calendar/calendar_repository.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../widgets/dialogs.dart';
import 'attendance.dart';
import 'grading.dart';

/// แท็บ "เกรด" ในหน้าวิชา: ใส่คะแนนย่อย → เห็นเกรด · ต้องได้อีกเท่าไหร่ · ช่วงเกรดของอาจารย์
class GradeCard extends StatefulWidget {
  const GradeCard({super.key, required this.subject});

  final Subject subject;

  @override
  State<GradeCard> createState() => _GradeCardState();
}

/// แบบตัวอย่างที่อาจารย์ส่วนใหญ่ใช้ (ชื่อ, คะแนนเก็บ, จำนวนชิ้น)
const _template = [
  ('งาน', 20.0, 4),
  ('สอบย่อย', 15.0, 3),
  ('เข้าเรียน', 5.0, 1),
  ('สอบกลางภาค', 20.0, 1),
  ('สอบปลายภาค', 40.0, 1),
];

class _GradeCardState extends State<GradeCard> {
  List<GradePart> _parts = const [];
  GradeSetup _setup = const GradeSetup();
  bool _loading = true;

  /// คาบทั้งหมดนับจากปฏิทิน (null = นับไม่ได้ → ใส่เอง)
  int? _autoTotal;

  /// เงื่อนไขที่ใช้คิดจริง: ไม่ได้ใส่จำนวนคาบเอง → ใช้ที่นับจากปฏิทิน
  GradeFlags get _flags => _setup.flags.classTotal == null && _autoTotal != null
      ? _setup.flags.copyWith(classTotal: _autoTotal)
      : _setup.flags;
  GradeSetup get _effective => GradeSetup(scale: _setup.scale, flags: _flags, official: _setup.official);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(GradeCard old) {
    super.didUpdateWidget(old);
    if (old.subject.id != widget.subject.id) _load();
  }

  Future<void> _load() async {
    final repo = StudyScope.of(context);
    final parts = await repo.gradeParts(widget.subject.id);
    final setup = await repo.gradeSetup(widget.subject.id);
    if (!mounted) return;
    final auto = await plannedClassTotal(CalendarScope.of(context), widget.subject.id);
    if (!mounted) return;
    setState(() {
      _parts = parts;
      _setup = setup;
      _autoTotal = auto;
      _loading = false;
    });
  }

  Future<void> _saveSetup(GradeSetup s) async {
    setState(() => _setup = s);
    await StudyScope.of(context).setGradeSetup(widget.subject.id, s);
  }

  Future<void> _useTemplate() async {
    final repo = StudyScope.of(context);
    for (final (name, weight, n) in _template) {
      await repo.addGradePart(widget.subject.id, name, weight, items: n, itemFull: n == 1 ? weight : 5);
    }
    await _load();
  }

  // ---------- กล่องถาม ----------

  /// เพิ่ม / แก้ส่วนคะแนน: ชื่อ · คะแนนเก็บ · (ตอนเพิ่ม) จำนวนชิ้น + เต็มชิ้นละ
  Future<void> _editPart([GradePart? part]) async {
    final name = TextEditingController(text: part?.name ?? '');
    final weight = TextEditingController(text: part == null ? '' : fmtScore(part.weight));
    final count = TextEditingController(text: '1');
    final full = TextEditingController();
    var showErr = false;
    String? err(TextEditingController t, String msg, {bool number = false}) {
      if (!showErr) return null;
      final v = t.text.trim();
      if (v.isEmpty) return msg;
      if (number && ((double.tryParse(v) ?? 0) <= 0)) return 'ใส่ตัวเลขมากกว่า 0';
      return null;
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(part == null ? 'เพิ่มส่วนคะแนน' : 'แก้ส่วนคะแนน'),
          content: SizedBox(
            width: 380,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(
                controller: name,
                autofocus: part == null,
                onChanged: (_) {
                  if (showErr) setLocal(() {});
                },
                decoration: InputDecoration(
                  labelText: 'ชื่อ *',
                  hintText: 'เช่น งาน, สอบย่อย, สอบปลายภาค',
                  errorText: err(name, 'ใส่ชื่อส่วนคะแนน'),
                ),
              ),
              TextField(
                controller: weight,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) {
                  if (showErr) setLocal(() {});
                },
                decoration: InputDecoration(
                  labelText: 'คะแนนเก็บ (จาก 100) *',
                  hintText: 'เช่น 20',
                  errorText: err(weight, 'ใส่คะแนนเก็บ', number: true),
                ),
              ),
              if (part == null) ...[
                TextField(
                  controller: count,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'จำนวนชิ้น', hintText: 'เช่น งาน 4 ชิ้น'),
                ),
                TextField(
                  controller: full,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                      labelText: 'เต็มชิ้นละ (เว้นว่าง = แบ่งเท่ากัน)', hintText: 'เช่น งานละ 5 · สอบเต็ม 60'),
                ),
              ],
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
            FilledButton(
              onPressed: () {
                final w = double.tryParse(weight.text.trim());
                if (name.text.trim().isEmpty || w == null || w <= 0) {
                  setLocal(() => showErr = true);
                  return;
                }
                Navigator.pop(ctx, true);
              },
              child: Text(part == null ? 'เพิ่ม' : 'บันทึก'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final n = name.text.trim();
    final w = double.tryParse(weight.text.trim());
    if (n.isEmpty || w == null || w <= 0) {
      _toast('ใส่ชื่อและคะแนนเก็บให้ครบ');
      return;
    }
    final repo = StudyScope.of(context);
    if (part == null) {
      await repo.addGradePart(widget.subject.id, n, w,
          items: int.tryParse(count.text.trim()) ?? 1, itemFull: double.tryParse(full.text.trim()));
    } else {
      await repo.updateGradePart(part.id, name: n, weight: w);
    }
    await _load();
  }

  /// ใส่คะแนนชิ้นเดียว: ได้ (เว้นว่าง = ยังไม่ได้คะแนน) · เต็ม · ชื่อ · ลบ
  Future<void> _editItem(GradeItem item) async {
    final got = TextEditingController(text: item.got == null ? '' : fmtScore(item.got!));
    final full = TextEditingController(text: fmtScore(item.full));
    final name = TextEditingController(text: item.name);
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(item.name),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Expanded(
                child: TextField(
                  controller: got,
                  autofocus: true,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'ได้', hintText: 'เว้นว่าง = ยังไม่ได้คะแนน'),
                  onSubmitted: (_) => Navigator.pop(ctx, 'save'),
                ),
              ),
              const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('/')),
              Expanded(
                child: TextField(
                  controller: full,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'เต็ม'),
                ),
              ),
            ]),
            TextField(controller: name, decoration: const InputDecoration(labelText: 'ชื่อชิ้น')),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('ลบชิ้นนี้')),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'save'), child: const Text('บันทึก')),
        ],
      ),
    );
    if (res == null || !mounted) return;
    final repo = StudyScope.of(context);
    if (res == 'delete') {
      await repo.deleteGradeItem(item.id);
    } else {
      final f = double.tryParse(full.text.trim());
      final g = double.tryParse(got.text.trim());
      if (f == null || f <= 0 || (g != null && (g < 0 || g > f))) {
        _toast('คะแนนต้องอยู่ระหว่าง 0 ถึงคะแนนเต็ม');
        return;
      }
      await repo.updateGradeItem(item.id,
          name: name.text.trim().isEmpty ? null : name.text.trim(), full: f, got: g, clearGot: g == null);
    }
    await _load();
  }

  Future<void> _partMenu(GradePart part, Offset at) async {
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('edit', Icons.edit_outlined, 'แก้ชื่อ / คะแนนเก็บ'),
      ctxItem('add', Icons.add, 'เพิ่มชิ้นคะแนน'),
      ctxItem('delete', Icons.delete_outline, 'ลบส่วนนี้', danger: true),
    ]);
    if (!mounted) return;
    final repo = StudyScope.of(context);
    switch (v) {
      case 'edit':
        await _editPart(part);
      case 'add':
        final last = part.items.isEmpty ? null : part.items.last;
        await repo.addGradeItem(part.id, '${part.name} ${part.items.length + 1}', last?.full ?? part.weight);
        await _load();
      case 'delete':
        if (await confirmDelete(context, part.name)) {
          await repo.deleteGradePart(part.id);
          await _load();
        }
    }
  }

  /// แก้คะแนนต่ำสุดของเกรด 1 ขั้น
  Future<void> _editBand(int index) async {
    final b = _setup.scale[index];
    final text = await askText(context,
        title: 'เกรด ${b.letter} ได้ตั้งแต่', label: 'คะแนน (จาก 100)', initial: fmtScore(b.min), confirmLabel: 'บันทึก');
    final v = double.tryParse(text ?? '');
    if (v == null || v < 0 || v > 100) return;
    final scale = [..._setup.scale]..[index] = GradeBand(b.letter, v, b.points);
    scale.sort((a, b) => b.min.compareTo(a.min));
    await _saveSetup(GradeSetup(scale: scale, flags: _setup.flags, official: _setup.official));
  }

  void _toast(String msg) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  // ---------- หน้าจอ ----------

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    final r = computeGrade(_parts, _setup.scale, _flags);
    return LayoutBuilder(builder: (context, box) {
      final left = _partsColumn(context);
      final right = _summaryColumn(context, r);
      if (box.maxWidth < 760) {
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [right, const SizedBox(height: 16), left]);
      }
      return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(child: left),
        const SizedBox(width: 20),
        SizedBox(width: 320, child: right),
      ]);
    });
  }

  Widget _box(BuildContext context, List<Widget> children) {
    final c = context.noir;
    // Material (ไม่ใช่ Container สีพื้น) → ช่องติ๊ก / ปุ่มข้างในยังเห็นเงากดได้
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
      ),
    );
  }

  Widget _partsColumn(BuildContext context) {
    final c = context.noir;
    final total = _parts.fold<double>(0, (s, p) => s + p.weight);
    if (_parts.isEmpty) {
      return _box(context, [
        Text('ยังไม่มีส่วนคะแนน', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 6),
        Text('ใส่ตามที่อาจารย์บอก เช่น งาน 20 · สอบย่อย 15 · กลางภาค 20 · ปลายภาค 40',
            style: TextStyle(color: c.muted)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: () => _editPart(), icon: const Icon(Icons.add), label: const Text('เพิ่มส่วนคะแนน')),
          OutlinedButton(onPressed: _useTemplate, child: const Text('ใช้แบบตัวอย่าง')),
        ]),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(
          child: Text('คะแนนแต่ละส่วน · รวม ${fmtScore(total)}',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
        ),
        TextButton.icon(onPressed: () => _editPart(), icon: const Icon(Icons.add), label: const Text('เพิ่มส่วน')),
      ]),
      if ((total - 100).abs() > 0.01)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text('คะแนนรวมไม่เท่ากับ 100 → แอปเทียบเป็น 100 ก่อนตัดเกรด',
              style: TextStyle(fontSize: 13, color: c.warn)),
        ),
      for (final p in _parts)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: GestureDetector(
            onSecondaryTapUp: (d) => _partMenu(p, d.globalPosition),
            onLongPressStart: (d) => _partMenu(p, d.globalPosition),
            child: _box(context, [
              Row(children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _editPart(p),
                    child: Text(p.name, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
                  ),
                ),
                Text(
                  p.anyGraded ? '${fmtScore(p.earned)} / ${fmtScore(p.weight)}' : '— / ${fmtScore(p.weight)}',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text),
                ),
              ]),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: p.weight <= 0 ? 0 : (p.earned / p.weight).clamp(0, 1).toDouble(),
                  minHeight: 5,
                  backgroundColor: c.surface2,
                  color: c.accent,
                ),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final i in p.items)
                  ActionChip(
                    label: Text('${i.name} · ${i.got == null ? '—' : fmtScore(i.got!)}/${fmtScore(i.full)}'),
                    onPressed: () => _editItem(i),
                    backgroundColor: i.got == null ? null : c.surface2,
                    visualDensity: VisualDensity.compact,
                  ),
              ]),
            ]),
          ),
        ),
      Text('คลิกชิ้น = ใส่คะแนน · คลิกขวา / กดค้างที่ส่วน = เพิ่มชิ้น · แก้ · ลบ',
          style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }

  Widget _summaryColumn(BuildContext context, GradeResult r) {
    final c = context.noir;
    final official = _setup.official;
    final letter = (official != null && official.isNotEmpty) ? official : r.letter;
    final hasScore = _parts.any((p) => p.anyGraded);
    final color = letter == 'F' || letter == 'U'
        ? c.bad
        : const {'A', 'B+', 'B', 'S'}.contains(letter)
            ? c.good
            : c.warn;
    final title = official != null && official.isNotEmpty
        ? 'เกรดจริง (ประกาศแล้ว)'
        : r.complete
            ? 'เกรดที่ได้'
            : 'ตอนนี้ (ยังไม่ครบทุกส่วน)';
    final flags = _setup.flags;
    void setFlags(GradeFlags f) => _saveSetup(GradeSetup(scale: _setup.scale, flags: f, official: _setup.official));
    final fCut = fCutOf(_setup.scale);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _box(context, [
        Text(title, style: TextStyle(fontSize: 13, color: c.muted)),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(hasScore || official != null || r.reason != null ? letter : '—',
              style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text('${fmtScore(r.earned)} / ${fmtScore(r.decided)} คะแนน',
                  style: TextStyle(fontSize: 15, color: c.text)),
            ),
          ),
        ]),
        Text(
          r.reason ?? (r.complete ? 'ตามช่วงเกรดด้านล่าง' : 'เหลืออีก ${fmtScore(r.remaining)} คะแนนที่ยังไม่ได้ใส่'),
          style: TextStyle(fontSize: 13, color: r.reason != null ? c.bad : c.muted),
        ),
        if (!r.complete && _parts.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text('ต้องได้อีกเท่าไหร่ (จากที่เหลือ ${fmtScore(r.remaining)})',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: c.text)),
          const SizedBox(height: 4),
          for (final b in _setup.scale.take(5))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 36, child: Text(b.letter, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
                Expanded(
                  child: Text(
                    switch (neededFor(r, b)) {
                      null => 'ได้แน่นอนแล้ว',
                      double n when n.isInfinite => 'ไม่ทันแล้ว',
                      double n => '≥ ${fmtScore(n)} คะแนน',
                    },
                    style: TextStyle(fontSize: 13, color: c.muted),
                  ),
                ),
              ]),
            ),
        ],
      ]),
      const SizedBox(height: 12),
      _box(context, [
        Row(children: [
          Expanded(child: Text('ช่วงเกรด', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
          TextButton(
            onPressed: () => _saveSetup(GradeSetup(flags: flags, official: _setup.official)),
            child: const Text('คืนค่าเริ่มต้น'),
          ),
        ]),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final (i, b) in _setup.scale.indexed)
            ActionChip(
              label: Text('${b.letter} ≥ ${fmtScore(b.min)}'),
              onPressed: () => _editBand(i),
              visualDensity: VisualDensity.compact,
            ),
          Chip(label: Text('F ≤ ${fmtScore(fCut)}'), visualDensity: VisualDensity.compact),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: Text('อาจารย์ตัด F ที่', style: TextStyle(color: c.text))),
          IconButton(
            tooltip: 'ลด',
            onPressed: () => _saveSetup(GradeSetup(
                scale: withFCut(_setup.scale, fCut - 1), flags: flags, official: _setup.official)),
            icon: const Icon(Icons.remove),
          ),
          Text(fmtScore(fCut), style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
          IconButton(
            tooltip: 'เพิ่ม',
            onPressed: () => _saveSetup(GradeSetup(
                scale: withFCut(_setup.scale, fCut + 1), flags: flags, official: _setup.official)),
            icon: const Icon(Icons.add),
          ),
        ]),
      ]),
      const SizedBox(height: 12),
      _box(context, [
        Text('เงื่อนไขได้ F ทันที', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        _absentRow(context, setFlags),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          value: flags.missedExam,
          onChanged: (v) => setFlags(flags.copyWith(missedExam: v ?? false)),
          title: const Text('ขาดสอบ'),
        ),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: Text('เกรดจริงที่ประกาศ', style: TextStyle(color: c.text))),
          DropdownButton<String>(
            value: official ?? '',
            focusColor: Colors.transparent,
            underline: const SizedBox.shrink(),
            items: [
              for (final g in const ['', 'A', 'B+', 'B', 'C+', 'C', 'D+', 'D', 'F', 'S', 'U'])
                DropdownMenuItem(value: g, child: Text(g.isEmpty ? 'ยังไม่ประกาศ' : g)),
            ],
            onChanged: (g) => _saveSetup(GradeSetup(
                scale: _setup.scale, flags: flags, official: (g == null || g.isEmpty) ? null : g)),
          ),
        ]),
      ]),
      ..._feedback(context),
    ]);
  }

  /// ขาดเรียน: [−] จำนวน [+] · จากกี่คาบ · กี่ % · ขาดได้อีกกี่คาบ
  Widget _absentRow(BuildContext context, void Function(GradeFlags) setFlags) {
    final c = context.noir;
    final stored = _setup.flags;
    final f = _flags;
    final pct = f.absentPercent;
    final left = f.absentLeft;
    final color = f.absentOver ? c.bad : (left != null && left <= 1 ? c.warn : c.muted);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('ขาดเรียน', style: TextStyle(color: c.text))),
        IconButton(
          tooltip: 'ลดคาบที่ขาด',
          onPressed: stored.absentCount <= 0 ? null : () => setFlags(stored.copyWith(absentCount: stored.absentCount - 1)),
          icon: const Icon(Icons.remove),
        ),
        Text('${stored.absentCount}', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
        IconButton(
          tooltip: 'ขาดเพิ่ม 1 คาบ',
          onPressed: () => setFlags(stored.copyWith(absentCount: stored.absentCount + 1)),
          icon: const Icon(Icons.add),
        ),
      ]),
      Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        ActionChip(
          visualDensity: VisualDensity.compact,
          label: Text(f.classTotal == null
              ? 'ใส่จำนวนคาบทั้งหมด'
              : 'จาก ${f.classTotal} คาบ${stored.classTotal == null ? ' (นับจากปฏิทิน)' : ''}'),
          onPressed: () => _editTotal(setFlags),
        ),
        ActionChip(
          visualDensity: VisualDensity.compact,
          label: Text('เกณฑ์ ${fmtScore(f.absentLimit)}%'),
          onPressed: () => _editLimit(setFlags),
        ),
      ]),
      if (pct != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            f.absentOver
                ? 'ขาด ${fmtScore(pct)}% · เกินเกณฑ์ → F'
                : 'ขาด ${fmtScore(pct)}% · ขาดได้อีก ${left ?? 0} คาบ',
            style: TextStyle(fontSize: 13, color: color),
          ),
        ),
    ]);
  }

  Future<void> _editTotal(void Function(GradeFlags) setFlags) async {
    final text = await askText(context,
        title: 'คาบเรียนทั้งหมดของวิชานี้',
        label: 'จำนวนคาบ',
        hint: _autoTotal == null ? 'เช่น 30' : 'เว้นว่าง = นับจากปฏิทิน ($_autoTotal คาบ)',
        initial: _setup.flags.classTotal?.toString() ?? '',
        confirmLabel: 'บันทึก');
    if (!mounted) return;
    final n = int.tryParse(text ?? '');
    // เว้นว่าง / 0 → กลับไปนับจากปฏิทิน
    setFlags(n == null || n <= 0 ? _setup.flags.copyWith(clearTotal: true) : _setup.flags.copyWith(classTotal: n));
  }

  Future<void> _editLimit(void Function(GradeFlags) setFlags) async {
    final text = await askText(context,
        title: 'ขาดเรียนได้ไม่เกินกี่ %', label: '%', initial: fmtScore(_setup.flags.absentLimit), confirmLabel: 'บันทึก');
    final v = double.tryParse(text ?? '');
    if (v == null || v <= 0 || v > 100) return;
    setFlags(_setup.flags.copyWith(absentLimit: v));
  }

  /// โอกาสปรับปรุง: เสียคะแนนตรงไหน · ขาดอีกเท่าไหร่ถึงเกรดถัดไป · เกรดจริงไม่ตรงกับที่คิด
  List<Widget> _feedback(BuildContext context) {
    final c = context.noir;
    final tips = gradeFeedback(_parts, _effective);
    if (tips.isEmpty) return const [];
    return [
      const SizedBox(height: 12),
      _box(context, [
        Text('โอกาสปรับปรุง', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
        const SizedBox(height: 6),
        for (final t in tips)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2, right: 8),
                child: Icon(Icons.lightbulb_outline, size: 16, color: c.warn),
              ),
              Expanded(child: Text(t, style: TextStyle(fontSize: 14, color: c.text))),
            ]),
          ),
      ]),
    ];
  }
}
