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

/// หน้า "แผนผังแผนการเรียน" แบบแผนภูมิหลักสูตร: ปี → เทอม → กล่องวิชา + เส้นวิชาที่ต้องเรียนก่อน
/// แตะหัวปี → ดูเฉพาะปีนั้น · แตะหัวภาค → ดูเฉพาะภาคนั้น · ดับเบิลคลิกกล่องวิชา → เปิดวิชา
/// ชี้ / เลือกวิชา → เส้นสายของวิชานั้นชัด วิชาอื่นจางลง
class CurriculumMap extends StatefulWidget {
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
    this.links = const [],
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

  /// เส้นวิชาที่ต้องเรียนก่อน (from → to) · วาดเฉพาะเส้นที่ทั้ง 2 วิชาอยู่บนจอ
  final List<SubjectLink> links;

  @override
  State<CurriculumMap> createState() => _CurriculumMapState();
}

class _CurriculumMapState extends State<CurriculumMap> {
  int? _hoverId;

  // ตำแหน่งกล่องวิชา: ตัววาดเส้นอ่านจาก key หลังจัดวางเสร็จ จึงต่อเส้นตรงขอบกล่องเสมอ
  final _stackKey = GlobalKey();
  final Map<int, GlobalKey> _boxKeys = {};
  GlobalKey _keyOf(int id) => _boxKeys.putIfAbsent(id, GlobalKey.new);

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final w = widget;
    final onFocus = w.onFocus;

    // จัดกลุ่ม ปี → เทอม → วิชา
    final years = <int, Map<int, List<Subject>>>{};
    final unplanned = <Subject>[];
    for (final s in w.subjects) {
      if (s.planYear == null || s.planTerm == null) {
        unplanned.add(s);
      } else {
        ((years[s.planYear!] ??= {})[s.planTerm!] ??= []).add(s);
      }
    }
    final totalCredits = w.subjects
        .where((s) => s.planYear != null)
        .fold<int>(0, (sum, s) => sum + s.creditUnits);

    // สายความสัมพันธ์ของวิชาที่ชี้/เลือก (บรรพบุรุษ + ลูกหลานทั้งสาย)
    final ids = {for (final s in w.subjects) s.id};
    final links = [for (final l in w.links) if (ids.contains(l.from) && ids.contains(l.to)) l];
    final chain = linkChain(links, _hoverId ?? w.selectedId);
    // วิชาไม่มีเส้นเลย → ไม่ต้องหรี่วิชาอื่น
    final dimOthers = chain.nodes.length > 1;

    Widget box(Subject s) => MouseRegion(
          onEnter: (_) => setState(() => _hoverId = s.id),
          onExit: (_) {
            if (_hoverId == s.id) setState(() => _hoverId = null);
          },
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: dimOthers && !chain.nodes.contains(s.id) ? 0.35 : 1,
            child: _SubjectBox(
              key: _keyOf(s.id),
              subject: s,
              progress: w.progress[s.id] ?? SubjectProgress.empty,
              selected: s.id == w.selectedId,
              onTap: () => (w.onSelect ?? w.onOpen)(s),
              onDoubleTap: w.onSelect == null ? null : () => w.onOpen(s),
            ),
          ),
        );

    // คอลัมน์ 1 ภาค: กล่องเรียงลงมาทีละใบ สูงเท่ากันทุกใบ
    Widget termColumn(String title, List<Subject> items,
        {double width = _boxWidth, VoidCallback? onHeader}) {
      final credits = items.fold<int>(0, (sum, s) => sum + s.creditUnits);
      return SizedBox(
        width: width,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(text: title, onTap: onHeader),
            const SizedBox(height: 8),
            for (final s in items)
              Padding(padding: const EdgeInsets.only(bottom: _gap), child: box(s)),
            if (credits > 0) _Header(text: '$credits หน่วยกิต', subtle: true),
          ],
        ),
      );
    }

    // ชั้นเส้นทับบนกล่อง (ไม่รับการแตะ ให้แตะทะลุถึงกล่อง)
    // [shown] = วิชาที่อยู่บนจอใน build นี้ · กล่องที่เพิ่งถูกถอด (สลับปี) ห้ามอ่านตำแหน่ง
    Widget withLines(Set<int> shown, Widget child) => Stack(
          key: _stackKey,
          children: [
            child,
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LinkPainter(
                    links: [for (final l in links) if (shown.contains(l.from) && shown.contains(l.to)) l],
                    chain: chain,
                    boxKeys: _boxKeys,
                    stackKey: _stackKey,
                    idle: c.muted,
                    dim: c.line2,
                    strong: c.accent,
                  ),
                ),
              ),
            ),
          ],
        );

    final sortedYears = years.keys.toList()..sort();
    final focus = w.focusYear != null && years.containsKey(w.focusYear) ? w.focusYear : null;
    // ภาคที่เลือกหายไป (เช่น ย้ายวิชาออกหมด) → ถอยไปดูทั้งปี
    final focusT = focus != null && w.focusTerm != null && years[focus]!.containsKey(w.focusTerm)
        ? w.focusTerm
        : null;
    List<int> termsOf(int y) => years[y]!.keys.toList()..sort();
    int creditsOf(int y) =>
        years[y]!.values.expand((l) => l).fold<int>(0, (sum, s) => sum + s.creditUnits);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (w.subjects.isEmpty)
          Text('ยังไม่มีวิชา · กด "เพิ่มวิชา" หรือ ⋮ → ใส่ตัวอย่างแผน 4 ปี',
              style: TextStyle(color: c.muted)),
        if (onFocus != null && sortedYears.isNotEmpty) ...[
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(
              label: const Text('ทุกปี'),
              selected: focus == null,
              onSelected: (_) => onFocus(null, null),
            ),
            for (final y in sortedYears)
              ChoiceChip(
                label: Text('ปี $y'),
                selected: focus == y,
                onSelected: (_) => onFocus(y, null),
              ),
          ]),
          // ในปีที่เลือก: สลับดูทั้งปี / ทีละภาค (ชื่อชิปสั้น ไม่ซ้ำกับหัวคอลัมน์)
          if (focus != null && termsOf(focus).length > 1) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              ChoiceChip(
                label: const Text('ทั้งปี'),
                selected: focusT == null,
                onSelected: (_) => onFocus(focus, null),
              ),
              for (final t in termsOf(focus))
                ChoiceChip(
                  label: Text(t == 3 ? 'ฤดูร้อน' : 'ภาค $t'),
                  selected: focusT == t,
                  onSelected: (_) => onFocus(focus, t),
                ),
            ]),
          ],
          const SizedBox(height: 12),
        ],
        if (focus != null)
          // ปีเดียว / ภาคเดียว: แต่ละภาคเป็นคอลัมน์เรียงลงมา กว้างขึ้นแต่ไม่เกิน _focusMaxWidth
          // ช่องระหว่างภาคกว้าง ให้เส้นเลี้ยวเห็นชัด
          LayoutBuilder(builder: (context, size) {
            final terms = focusT == null ? termsOf(focus) : [focusT];
            final colW = ((size.maxWidth - _focusGap * (terms.length - 1)) / terms.length)
                .clamp(_boxWidth, _focusMaxWidth);
            final total = colW * terms.length + _focusGap * (terms.length - 1);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: total,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _Header(
                      text: focusT == null
                          ? 'ปีการศึกษาที่ $focus · ${creditsOf(focus)} หน่วยกิต'
                          : 'ปีการศึกษาที่ $focus · ${termLabel(focusT)}',
                      strong: true,
                      // ดูภาคเดียวอยู่ → แตะหัวปีเพื่อกลับไปดูทั้งปี
                      onTap: focusT == null || onFocus == null ? null : () => onFocus(focus, null),
                    ),
                    const SizedBox(height: 8),
                    withLines({
                      for (final t in terms) ...years[focus]![t]!.map((s) => s.id)
                    }, Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, t) in terms.indexed) ...[
                          if (i > 0) const SizedBox(width: _focusGap),
                          termColumn(termLabel(t), years[focus]![t]!,
                              width: colW,
                              onHeader: focusT != null || onFocus == null
                                  ? null
                                  : () => onFocus(focus, t)),
                        ],
                      ],
                    )),
                  ],
                ),
              ),
            );
          })
        else
          // เลื่อนซ้าย-ขวาได้ ดูทั้งหลักสูตรเหมือนแผนภูมิกระดาษ
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: withLines(ids, Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (yi, y) in sortedYears.indexed) ...[
                  if (yi > 0) const SizedBox(width: _yearGap),
                  // IntrinsicWidth: ในแถวที่เลื่อนซ้าย-ขวา ความกว้างไม่มีขอบเขต
                  // → ให้คอลัมน์กว้างเท่าเนื้อหา (หัวปียืดเท่าเทอมด้านล่าง) แทนที่จะยืดไม่สิ้นสุด
                  IntrinsicWidth(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _Header(
                          text: 'ปีการศึกษาที่ $y',
                          strong: true,
                          onTap: onFocus == null ? null : () => onFocus(y, null),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final (ti, t) in termsOf(y).indexed) ...[
                              if (ti > 0) const SizedBox(width: _termGap),
                              termColumn(termLabel(t), years[y]![t]!,
                                  onHeader: onFocus == null ? null : () => onFocus(y, t)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                if (unplanned.isNotEmpty) ...[
                  if (sortedYears.isNotEmpty) const SizedBox(width: _yearGap),
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
              ],
            )),
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
const double _boxHeight = 108; // ทุกกล่องสูงเท่ากัน: ชื่อ 2 บรรทัด + บรรทัดสถานะ 1 บรรทัด
const double _gap = 8;
// ช่องว่างระหว่างคอลัมน์ต้อง ≥ 24 ให้เส้นเลี้ยว (ห่างกล่องปลายทาง 15) ไม่ชนกล่อง
const double _termGap = 24;
const double _yearGap = 32;
const double _focusGap = 56;
const double _focusMaxWidth = 320;

/// สายความสัมพันธ์ของ 1 วิชา: ทุกวิชาที่ต้องเรียนก่อน (ไล่ขึ้น) + ทุกวิชาที่ต่อยอด (ไล่ลง)
typedef LinkChain = ({Set<int> nodes, Set<SubjectLink> edges});

LinkChain linkChain(List<SubjectLink> links, int? focus) {
  if (focus == null) return (nodes: <int>{}, edges: <SubjectLink>{});
  Set<int> walk(bool up) {
    final seen = {focus};
    final todo = [focus];
    while (todo.isNotEmpty) {
      final id = todo.removeLast();
      for (final l in links) {
        final next = up ? (l.to == id ? l.from : null) : (l.from == id ? l.to : null);
        if (next != null && seen.add(next)) todo.add(next);
      }
    }
    return seen;
  }

  final up = walk(true), down = walk(false);
  return (
    nodes: {...up, ...down},
    // เส้นที่อยู่ในสาย = ทั้ง 2 ปลายอยู่ฝั่งเดียวกัน (กันเส้นข้างเคียงของวิชาในสายติดมาด้วย)
    edges: {
      for (final l in links)
        if ((up.contains(l.from) && up.contains(l.to)) ||
            (down.contains(l.from) && down.contains(l.to)))
          l,
    },
  );
}

/// วาดเส้นหักมุม: ขอบขวากล่องต้นทาง → เลี้ยวลง/ขึ้นในช่องว่างหน้ากล่องปลายทาง → ลูกศรเข้าขอบซ้าย
class _LinkPainter extends CustomPainter {
  _LinkPainter({
    required this.links,
    required this.chain,
    required this.boxKeys,
    required this.stackKey,
    required this.idle,
    required this.dim,
    required this.strong,
  });

  final List<SubjectLink> links;
  final LinkChain chain;
  final Map<int, GlobalKey> boxKeys;
  final GlobalKey stackKey;
  final Color idle, dim, strong;

  Rect? _rectOf(int id, RenderBox stack) {
    final box = boxKeys[id]?.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero, ancestor: stack) & box.size;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final stack = stackKey.currentContext?.findRenderObject();
    if (stack is! RenderBox) return;
    final active = chain.nodes.length > 1;
    // วาดเส้นจางก่อน เส้นในสายทีหลัง → เส้นสายอยู่บนสุดเสมอ
    final ordered = [
      for (final l in links) if (!chain.edges.contains(l)) l,
      for (final l in links) if (chain.edges.contains(l)) l,
    ];
    for (final l in ordered) {
      final a = _rectOf(l.from, stack), b = _rectOf(l.to, stack);
      if (a == null || b == null) continue; // ยังไม่ได้จัดวาง
      final on = chain.edges.contains(l);
      final color = on ? strong : (active ? dim.withValues(alpha: 0.35) : idle.withValues(alpha: 0.7));
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = on ? 2.2 : 1.4
        ..strokeCap = StrokeCap.round;
      _drawElbow(canvas, a, b, paint, color);
    }
  }

  void _drawElbow(Canvas canvas, Rect a, Rect b, Paint paint, Color color) {
    final y1 = a.center.dy, y2 = b.center.dy;
    final path = Path();
    late double x1, x2, gx;
    if (b.left > a.right + 8) {
      // ปกติ: ต้นทางอยู่ซ้ายของปลายทาง
      x1 = a.right;
      x2 = b.left;
      gx = (x2 - 15).clamp(x1 + 6, x2 - 6);
    } else {
      // คอลัมน์เดียวกัน / ปลายทางอยู่ซ้าย: อ้อมทางซ้ายของทั้ง 2 กล่อง
      x1 = a.left;
      x2 = b.left;
      gx = (a.left < b.left ? a.left : b.left) - 12;
    }
    path.moveTo(x1, y1);
    final dy = y2 - y1;
    if (dy.abs() < 1) {
      path.lineTo(x2, y2);
    } else {
      final dir = dy.sign;
      final r = [6.0, dy.abs() / 2, (gx - x1).abs(), (x2 - gx).abs()].reduce((p, q) => p < q ? p : q);
      final sx = (gx - x1).sign; // ทิศช่วงแรก (ขวา หรือ ซ้ายตอนอ้อม)
      path.lineTo(gx - sx * r, y1);
      path.quadraticBezierTo(gx, y1, gx, y1 + dir * r);
      path.lineTo(gx, y2 - dir * r);
      path.quadraticBezierTo(gx, y2, gx + r, y2);
      path.lineTo(x2 - 5, y2);
    }
    canvas.drawPath(path, paint);
    // จุดต้นทาง + หัวลูกศรชี้เข้ากล่องปลายทาง
    final fill = Paint()..color = color;
    canvas.drawCircle(Offset(x1, y1), 2.5, fill);
    canvas.drawPath(
      Path()
        ..moveTo(x2, y2)
        ..lineTo(x2 - 7, y2 - 4.5)
        ..lineTo(x2 - 7, y2 + 4.5)
        ..close(),
      fill,
    );
  }

  // ตำแหน่งกล่องอ่านจาก key ตอนวาด → วาดใหม่ทุกครั้งที่หน้า build
  @override
  bool shouldRepaint(covariant _LinkPainter old) => true;
}

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
    super.key,
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
          height: _boxHeight,
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
              // ชื่อกินพื้นที่ที่เหลือ (ตรงกลาง) → กล่องสูงเท่ากันไม่ว่าชื่อยาวกี่บรรทัด
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      subject.name,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: c.text, height: 1.3),
                    ),
                  ),
                ),
              ),
              // บรรทัดสถานะ 1 บรรทัดเสมอ (ข้อมูลขาด > ความคืบหน้า > ว่าง)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                child: Text(
                  missing.isNotEmpty
                      ? '⚠ ขาด ${missing.join(' · ')}'
                      : progress.total == 0
                          ? ' '
                          : progress.average == null
                              ? '${progress.total} หัวข้อ · ยังไม่ประเมิน'
                              : 'ประเมิน ${progress.assessed}/${progress.total} · ${progress.average!.round()}%',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: missing.isNotEmpty
                      ? TextStyle(fontSize: 11, color: c.bad, fontWeight: FontWeight.w600)
                      : TextStyle(fontSize: 11, color: c.muted),
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
