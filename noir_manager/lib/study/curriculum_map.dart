import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../study/mastery.dart';
import '../theme/noir_colors.dart';

/// สรุปความคืบหน้าของ 1 วิชา (ใช้วาดแถบสีในกล่องวิชา)
class SubjectProgress {
  const SubjectProgress({required this.assessed, required this.total, this.average});
  final int assessed;
  final int total;

  /// คะแนนเฉลี่ยของหัวข้อที่ประเมินแล้ว · null = ยังไม่ประเมิน
  final double? average;

  static const empty = SubjectProgress(assessed: 0, total: 0);
}

String termLabel(int term) => term == 3 ? 'ภาคฤดูร้อน' : 'ภาคเรียนที่ $term';

/// หน้า "แผนผังแผนการเรียน" แบบแผนภูมิหลักสูตร: ปี → เทอม → กล่องวิชา
/// แตะหัวปี → ดูเฉพาะปีนั้น · แตะหัวภาค → ดูเฉพาะภาคนั้น · ดับเบิลคลิกกล่องวิชา → เปิดวิชา
class CurriculumMap extends StatelessWidget {
  const CurriculumMap({
    super.key,
    required this.subjects,
    required this.progress,
    required this.selectedId,
    required this.onOpen,
    this.onSelect,
    this.focusYear,
    this.focusTerm,
    this.onFocus,
  });

  final List<Subject> subjects;
  final Map<int, SubjectProgress> progress;
  final int? selectedId;
  /// ดับเบิลคลิก = เปิดวิชา
  final ValueChanged<Subject> onOpen;

  /// แตะครั้งเดียว = เลือก (กรอบสีเน้น) · null = แตะครั้งเดียวก็เปิดเลย
  final ValueChanged<Subject>? onSelect;

  /// ดูเฉพาะปีนี้ (เห็นทุกเทอมของปีนั้นเต็มจอ) · null = ทั้งหลักสูตร
  final int? focusYear;

  /// ดูเฉพาะภาคนี้ของ [focusYear] · null = ทุกภาคของปีนั้น
  final int? focusTerm;

  /// แตะหัวปี/หัวภาค หรือชิป → เปลี่ยนสิ่งที่ดู (year null = ทุกปี, term null = ทั้งปี)
  /// null = หัวกดไม่ได้ (แบบเดิม)
  final void Function(int? year, int? term)? onFocus;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    // จัดกลุ่ม ปี → เทอม → วิชา
    final years = <int, Map<int, List<Subject>>>{};
    final unplanned = <Subject>[];
    for (final s in subjects) {
      if (s.planYear == null || s.planTerm == null) {
        unplanned.add(s);
      } else {
        ((years[s.planYear!] ??= {})[s.planTerm!] ??= []).add(s);
      }
    }
    final totalCredits = subjects
        .where((s) => s.planYear != null)
        .fold<int>(0, (sum, s) => sum + s.creditUnits);

    Widget box(Subject s) => _SubjectBox(
          subject: s,
          progress: progress[s.id] ?? SubjectProgress.empty,
          selected: s.id == selectedId,
          onTap: () => (onSelect ?? onOpen)(s),
          onDoubleTap: onSelect == null ? null : () => onOpen(s),
        );

    Widget termColumn(String title, List<Subject> items, {double width = _boxWidth, VoidCallback? onHeader}) {
      final credits = items.fold<int>(0, (sum, s) => sum + s.creditUnits);
      // คอลัมน์กว้าง (ดูปีเดียว) → วางกล่องหลายใบต่อแถว ไม่ให้กล่องยืดยาวเกิน
      final perRow = ((width + _gap) / (_boxWidth + _gap)).floor().clamp(1, 99);
      final boxW = (width - _gap * (perRow - 1)) / perRow;
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(text: title, onTap: onHeader),
            const SizedBox(height: 8),
            if (perRow == 1)
              for (final s in items)
                Padding(padding: const EdgeInsets.only(bottom: _gap), child: box(s))
            else
              Wrap(
                spacing: _gap,
                runSpacing: _gap,
                children: [for (final s in items) SizedBox(width: boxW, child: box(s))],
              ),
            if (perRow > 1 && items.isNotEmpty) const SizedBox(height: _gap),
            if (credits > 0) _Header(text: '$credits หน่วยกิต', subtle: true),
          ],
        ),
      );
    }

    final sortedYears = years.keys.toList()..sort();
    final focus = focusYear != null && years.containsKey(focusYear) ? focusYear : null;
    // ภาคที่เลือกหายไป (เช่น ย้ายวิชาออกหมด) → ถอยไปดูทั้งปี
    final focusT = focus != null && focusTerm != null && years[focus]!.containsKey(focusTerm)
        ? focusTerm
        : null;
    List<int> termsOf(int y) => years[y]!.keys.toList()..sort();
    int creditsOf(int y) =>
        years[y]!.values.expand((l) => l).fold<int>(0, (sum, s) => sum + s.creditUnits);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (subjects.isEmpty)
          Text('ยังไม่มีวิชา · กด "เพิ่มวิชา" หรือ ⋮ → ใส่ตัวอย่างแผน 4 ปี',
              style: TextStyle(color: c.muted)),
        if (onFocus != null && sortedYears.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('ทุกปี'),
              selected: focus == null,
              onSelected: (_) => onFocus!(null, null),
            ),
            for (final y in sortedYears)
              ChoiceChip(
                label: Text('ปี $y'),
                selected: focus == y,
                onSelected: (_) => onFocus!(y, null),
              ),
          ]),
          // ในปีที่เลือก: สลับดูทั้งปี / ทีละภาค (ชื่อชิปสั้น ไม่ซ้ำกับหัวคอลัมน์)
          if (focus != null && termsOf(focus).length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('ทั้งปี'),
                selected: focusT == null,
                onSelected: (_) => onFocus!(focus, null),
              ),
              for (final t in termsOf(focus))
                ChoiceChip(
                  label: Text(t == 3 ? 'ฤดูร้อน' : 'ภาค $t'),
                  selected: focusT == t,
                  onSelected: (_) => onFocus!(focus, t),
                ),
            ]),
          ],
          const SizedBox(height: 12),
        ],
        if (focus != null)
          // ปีเดียว: ทุกเทอมของปีนั้นแบ่งความกว้างจอกัน
          LayoutBuilder(builder: (context, box) {
            final terms = focusT == null ? termsOf(focus) : [focusT];
            final w = ((box.maxWidth - _termGap * (terms.length - 1)) / terms.length)
                .clamp(_boxWidth, double.infinity);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: w * terms.length + _termGap * (terms.length - 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      text: focusT == null
                          ? 'ปีการศึกษาที่ $focus · ${creditsOf(focus)} หน่วยกิต'
                          : 'ปีการศึกษาที่ $focus · ${termLabel(focusT)}',
                      strong: true,
                      // ดูภาคเดียวอยู่ → แตะหัวปีเพื่อกลับไปดูทั้งปี
                      onTap: focusT == null || onFocus == null ? null : () => onFocus!(focus, null),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, t) in terms.indexed) ...[
                          if (i > 0) const SizedBox(width: _termGap),
                          termColumn(termLabel(t), years[focus]![t]!,
                              width: w,
                              onHeader: focusT != null || onFocus == null
                                  ? null
                                  : () => onFocus!(focus, t)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            );
          })
        else
          // เลื่อนซ้าย-ขวาได้ ดูทั้งหลักสูตรเหมือนแผนภูมิกระดาษ
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final y in sortedYears) ...[
                  // IntrinsicWidth: ในแถวที่เลื่อนซ้าย-ขวา ความกว้างไม่มีขอบเขต
                  // → ให้คอลัมน์กว้างเท่าเนื้อหา (หัวปียืดเท่าเทอมด้านล่าง) แทนที่จะยืดไม่สิ้นสุด
                  IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          text: 'ปีการศึกษาที่ $y',
                          strong: true,
                          onTap: onFocus == null ? null : () => onFocus!(y, null),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final t in termsOf(y)) ...[
                              termColumn(termLabel(t), years[y]![t]!,
                                  onHeader: onFocus == null ? null : () => onFocus!(y, t)),
                              const SizedBox(width: 10),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                ],
                if (unplanned.isNotEmpty)
                  SizedBox(
                    width: _boxWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _Header(text: 'ยังไม่จัดเทอม', strong: true),
                        const SizedBox(height: 8),
                        termColumn('วิชาอื่น ๆ', unplanned),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        if (focus == null && totalCredits > 0) ...[
          const SizedBox(height: 12),
          _Header(text: 'จำนวนหน่วยกิตตลอดหลักสูตร $totalCredits หน่วยกิต', strong: true),
        ],
      ],
    );
  }
}

const double _boxWidth = 180;
const double _gap = 8;
const double _termGap = 16;

class _Header extends StatelessWidget {
  const _Header({required this.text, this.strong = false, this.subtle = false, this.onTap});
  final String text;
  final bool strong;
  final bool subtle;

  /// กดได้ → มีลูกศร › บอกว่าเข้าไปดูต่อได้
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final style = TextStyle(
      fontSize: 13,
      fontWeight: strong || !subtle ? FontWeight.w600 : FontWeight.w400,
      color: subtle ? c.muted : c.text,
    );
    return Material(
      color: subtle ? Colors.transparent : (strong ? c.surface2 : c.surface),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: onTap == null
              ? Text(text, textAlign: TextAlign.center, style: style)
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(child: Text(text, textAlign: TextAlign.center, style: style)),
                    Icon(Icons.chevron_right, size: 16, color: c.muted),
                  ],
                ),
        ),
      ),
    );
  }
}

/// กล่องวิชา: รหัส | หน่วยกิต · ชื่อ · แถบสีความเข้าใจ
class _SubjectBox extends StatelessWidget {
  const _SubjectBox({
    required this.subject,
    required this.progress,
    required this.onTap,
    this.onDoubleTap,
    this.selected = false,
  });

  final Subject subject;
  final SubjectProgress progress;
  final VoidCallback onTap;
  final VoidCallback? onDoubleTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final level = masteryOf(progress.average?.round());
    // ข้อมูลที่ขาด (เช่น ใส่วิชาไว้ก่อนมีแผนการเรียน) → กรอบแดง + บอกว่าขาดอะไร
    final missing = [
      if ((subject.code ?? '').isEmpty) 'รหัส',
      if ((subject.credits ?? '').isEmpty) 'หน่วยกิต',
      if (subject.planYear == null || subject.planTerm == null) 'ปี/เทอม',
    ];
    final barColor = switch (level) {
      MasteryLevel.good => c.good,
      MasteryLevel.warn => c.warn,
      MasteryLevel.bad => c.bad,
      MasteryLevel.none => c.line2,
    };
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        onDoubleTap: onDoubleTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? c.accent : (missing.isEmpty ? c.line2 : c.bad),
              width: selected || missing.isNotEmpty ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(subject.code ?? '—',
                          style: TextStyle(fontSize: 11, color: c.muted)),
                    ),
                    Text(subject.credits ?? '',
                        style: TextStyle(fontSize: 11, color: c.muted)),
                  ],
                ),
              ),
              Divider(height: 1, color: c.line),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
                child: Text(
                  subject.name,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.text, height: 1.3),
                ),
              ),
              if (missing.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Text('⚠ ขาด ${missing.join(' · ')}',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 11, color: c.bad, fontWeight: FontWeight.w600)),
                ),
              if (progress.total > 0)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Text(
                    progress.average == null
                        ? '${progress.total} หัวข้อ · ยังไม่ประเมิน'
                        : 'ประเมิน ${progress.assessed}/${progress.total} · ${progress.average!.round()}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: c.muted),
                  ),
                ),
              Container(height: 4, color: barColor),
            ],
          ),
        ),
      ),
    );
  }
}
