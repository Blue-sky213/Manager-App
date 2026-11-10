import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../widgets/mini_dropdown.dart';
import 'grading.dart';
import 'subject_colors.dart';

/// 1 แถวในตาราง: วิชา + เกรดที่ใช้คิด GPA
class GpaRow {
  const GpaRow(this.subject, this.letter, this.score, {this.projected = false});
  final Subject subject;
  final String letter; // '—' = ยังไม่มีคะแนน
  final double? score; // คะแนนรวมเทียบ 100 (null = ยังไม่มี)
  final bool projected; // ยังไม่ครบทุกส่วน → เกรดคาดการณ์
}

/// โหลดเกรดของทุกวิชาในแผน (ใช้ทั้งหน้านี้และเทส)
Future<List<GpaRow>> loadGpaRows(BuildContext context) async {
  final repo = StudyScope.of(context);
  final rows = <GpaRow>[];
  for (final s in await repo.subjects()) {
    final parts = await repo.gradeParts(s.id);
    final setup = await repo.gradeSetup(s.id);
    final letter = effectiveLetter(setup, parts);
    final r = computeGrade(parts, setup.scale, setup.flags);
    final official = setup.official != null && setup.official!.isNotEmpty;
    rows.add(GpaRow(s, letter, parts.any((p) => p.anyGraded) ? r.percent : null,
        projected: !official && letter != '—' && !r.complete));
  }
  return rows;
}

/// หน้า "เกรดและหน่วยกิต": GPA ต่อเทอม · GPAX สะสม · หน่วยกิตทั้งหลักสูตร
class GpaPage extends StatefulWidget {
  const GpaPage({super.key, this.initialTerm});

  /// (ปี, ภาค) ที่เปิดก่อน · null = เทอมแรกที่มีวิชา
  final (int, int)? initialTerm;

  @override
  State<GpaPage> createState() => _GpaPageState();
}

class _GpaPageState extends State<GpaPage> {
  List<GpaRow> _rows = const [];
  bool _loaded = false;
  (int, int)? _term;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final rows = await loadGpaRows(context);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loaded = true;
      final terms = _terms;
      _term ??= (widget.initialTerm != null && terms.contains(widget.initialTerm))
          ? widget.initialTerm
          : (terms.isEmpty ? null : terms.first);
    });
  }

  List<(int, int)> get _terms {
    final set = <(int, int)>{
      for (final r in _rows)
        if (r.subject.planYear != null) (r.subject.planYear!, r.subject.planTerm ?? 1),
    };
    return set.toList()..sort((a, b) => a.$1 != b.$1 ? a.$1 - b.$1 : a.$2 - b.$2);
  }

  String _termLabel((int, int) t) => 'ปี ${t.$1} · ${t.$2 == 3 ? 'ฤดูร้อน' : 'ภาค ${t.$2}'}';

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final terms = _terms;
    final inTerm = _term == null
        ? const <GpaRow>[]
        : _rows.where((r) => r.subject.planYear == _term!.$1 && (r.subject.planTerm ?? 1) == _term!.$2).toList();
    final termGpa = gpa([for (final r in inTerm) (r.subject.creditUnits, r.letter)]);
    final gpax = gpa([for (final r in _rows.where((r) => !r.projected)) (r.subject.creditUnits, r.letter)]);
    final termCredits = inTerm.fold<int>(0, (s, r) => s + r.subject.creditUnits);
    final planCredits = _rows.where((r) => r.subject.planYear != null).fold<int>(0, (s, r) => s + r.subject.creditUnits);
    final passed = _rows
        .where((r) => !r.projected && r.letter != '—' && r.letter != 'F' && r.letter != 'U')
        .fold<int>(0, (s, r) => s + r.subject.creditUnits);
    final anyProjected = inTerm.any((r) => r.projected);

    Widget tile(String label, String value, String sub, {Color? color, double? progress}) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: c.line),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: color ?? c.text)),
            const SizedBox(height: 4),
            if (progress != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                    value: progress.clamp(0, 1).toDouble(), minHeight: 6, backgroundColor: c.surface2, color: c.accent),
              )
            else
              Text(sub, style: TextStyle(fontSize: 13, color: c.muted)),
          ]),
        );

    Color gradeColor(String g) => switch (g) {
          'A' || 'B+' || 'B' || 'S' => c.good,
          'F' || 'U' => c.bad,
          '—' => c.muted,
          _ => c.warn,
        };

    return Scaffold(
      appBar: AppBar(title: const Text('เกรดและหน่วยกิต')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
              children: [
                Row(children: [
                  Expanded(
                    child: Text(_term == null ? 'ยังไม่มีวิชาในแผน 4 ปี' : _termLabel(_term!),
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: c.text)),
                  ),
                  if (terms.isNotEmpty && _term != null)
                    MiniDropdown<(int, int)>(
                      value: _term!,
                      items: [for (final t in terms) (t, _termLabel(t))],
                      onChanged: (t) => setState(() => _term = t),
                    ),
                ]),
                const SizedBox(height: 16),
                LayoutBuilder(builder: (context, box) {
                  final tiles = [
                    tile(anyProjected ? 'GPA เทอมนี้ (คาดการณ์)' : 'GPA เทอมนี้',
                        termGpa == null ? '—' : termGpa.toStringAsFixed(2),
                        termGpa == null ? 'ยังไม่มีคะแนน' : 'ตามคะแนนที่ใส่แล้ว',
                        color: termGpa == null ? null : (termGpa >= 3 ? c.good : termGpa >= 2 ? c.warn : c.bad)),
                    tile('GPAX สะสม', gpax == null ? '—' : gpax.toStringAsFixed(2),
                        gpax == null ? 'ยังไม่มีวิชาที่จบ' : 'เฉพาะวิชาที่ได้เกรดครบ'),
                    tile('หน่วยกิตเทอมนี้', '$termCredits', '${inTerm.length} วิชา'),
                    tile('สะสมทั้งหลักสูตร', '$passed / $planCredits', '',
                        progress: planCredits == 0 ? 0 : passed / planCredits),
                  ];
                  final cols = box.maxWidth >= 900 ? 4 : 2;
                  final w = (box.maxWidth - 12 * (cols - 1)) / cols;
                  return Wrap(spacing: 12, runSpacing: 12, children: [
                    for (final t in tiles) SizedBox(width: w, child: t),
                  ]);
                }),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: c.surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.line),
                  ),
                  child: Column(children: [
                    _row(context, null, 'วิชา', 'หน่วยกิต', 'คะแนน', 'เกรด', 'แต้ม × หน่วยกิต', header: true),
                    for (final r in inTerm)
                      _row(
                        context,
                        subjectColorOf(r.subject),
                        r.subject.name,
                        '${r.subject.creditUnits}',
                        r.score == null ? '—' : '${fmtScore(r.score!)}${r.projected ? ' *' : ''}',
                        r.letter,
                        switch (gradePoints(r.letter)) {
                          null => '—',
                          double p => fmtScore(p * r.subject.creditUnits),
                        },
                        gradeColor: gradeColor(r.letter),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Text(
                        'GPA = ผลรวม (แต้ม × หน่วยกิต) ÷ หน่วยกิตที่นับเกรด · S/U ไม่นับ · * = ยังไม่ครบทุกส่วน (เกรดคาดการณ์)',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                    ),
                  ]),
                ),
              ],
            ),
    );
  }

  Widget _row(BuildContext context, Color? dot, String name, String credits, String score, String grade, String points,
      {bool header = false, Color? gradeColor}) {
    final c = context.noir;
    final style = TextStyle(fontSize: header ? 13 : 15, color: header ? c.muted : c.text);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
      child: Row(children: [
        Container(
            width: 5,
            height: 24,
            decoration: BoxDecoration(color: dot ?? Colors.transparent, borderRadius: BorderRadius.circular(4))),
        const SizedBox(width: 12),
        Expanded(child: Text(name, style: style, maxLines: 1, overflow: TextOverflow.ellipsis)),
        SizedBox(width: 70, child: Text(credits, style: style)),
        SizedBox(width: 70, child: Text(score, style: style)),
        SizedBox(
            width: 56,
            child: Text(grade,
                style: header ? style : style.copyWith(fontWeight: FontWeight.w700, color: gradeColor))),
        SizedBox(width: 90, child: Text(points, style: style, textAlign: TextAlign.right)),
      ]),
    );
  }
}
