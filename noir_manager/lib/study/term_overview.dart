/// การเรียน › ภาพรวม (รอบ 9A): เปิดมาเจอเลย ไม่ต้องหา
/// คาบถัดไป · สอบถัดไป · ติวสัปดาห์นี้ · เข้าใจเฉลี่ย · วงทุกวิชาเทอมนี้ · ต้องทวน · การเรียนวันนี้
library;

import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../data/study_models.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'mastery.dart';
import 'subject_colors.dart';

class _SubjectRow {
  const _SubjectRow(this.subject, this.average, this.review);
  final Subject subject;
  final double? average;
  final int review;
}

class _ReviewItem {
  const _ReviewItem(this.topic, this.subject, this.chapter, this.score);
  final String topic;
  final String subject;
  final String chapter;
  final int? score;
}

class TermOverview extends StatefulWidget {
  const TermOverview({super.key, required this.onOpenSubject});

  /// คลิกวิชา → แท็บรายวิชาของวิชานั้น
  final ValueChanged<Subject> onOpenSubject;

  @override
  State<TermOverview> createState() => _TermOverviewState();
}

class _TermOverviewState extends State<TermOverview> {
  CalendarRepository? _cal;
  bool _loaded = false;
  String _termLabel = '';
  List<_SubjectRow> _rows = const [];
  List<_ReviewItem> _review = const [];
  Occurrence? _nextClass;
  (Activity, DateTime)? _nextExam;
  (int, int) _tutor = (0, 0);
  List<Occurrence> _today = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final cal = CalendarScope.of(context);
    if (cal != _cal) {
      _cal?.removeListener(_load);
      _cal = cal..addListener(_load);
      _load();
    }
  }

  @override
  void dispose() {
    _cal?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final study = StudyScope.of(context);
    final cal = _cal!;
    final now = DateTime.now();
    final today = dayOnly(now);
    final mode = await study.gradingMode();
    final all = await study.subjects();
    final term = (await cal.terms()).where((t) => !today.isBefore(t.start) && !today.isAfter(t.end)).firstOrNull;
    // วิชาเทอมนี้ (ไม่มีเทอม = วิชาที่มีคาบในปฏิทิน · ยังไม่มีอีก = ทุกวิชา)
    var subjects = term == null ? <Subject>[] : [for (final s in all) if (s.planYear == term.year && s.planTerm == term.termNo) s];
    final week = await cal.occurrencesBetween(today, today.add(const Duration(days: 13)));
    if (subjects.isEmpty) {
      final ids = {for (final l in week.values) for (final o in l) if (o.subjectId != null) o.subjectId};
      subjects = [for (final s in all) if (ids.contains(s.id)) s];
    }
    if (subjects.isEmpty) subjects = all.take(8).toList();
    final ids = {for (final s in subjects) s.id};

    final rows = <_SubjectRow>[];
    final review = <_ReviewItem>[];
    for (final s in subjects) {
      final chapters = await study.chapters(s.id);
      final topics = [for (final ch in chapters) ...ch.subtopics];
      final scores = [for (final t in topics) if (shownScore(t, mode) != null) shownScore(t, mode)!];
      final need = reviewOrder(topics, mode: mode);
      rows.add(_SubjectRow(s, scores.isEmpty ? null : scores.reduce((a, b) => a + b) / scores.length, need.length));
      final chName = {for (final ch in chapters) ch.chapter.id: ch.chapter.name};
      for (final t in need) {
        review.add(_ReviewItem(t.name, s.name, chName[t.chapterId] ?? '', shownScore(t, mode)));
      }
    }
    review.sort((a, b) => (a.score ?? 999).compareTo(b.score ?? 999));

    // คาบถัดไป · ติวสัปดาห์นี้ · วันนี้
    Occurrence? next;
    for (final d in week.keys.toList()..sort()) {
      for (final o in week[d]!) {
        if (o.kind != ActivityKind.classSession || !ids.contains(o.subjectId) || !o.timed) continue;
        if (o.status != OccurrenceStatus.planned || !o.startAt!.isAfter(now)) continue;
        if (next == null || o.startAt!.isBefore(next.startAt!)) next = o;
      }
      if (next != null) break;
    }
    final monday = today.subtract(Duration(days: today.weekday - 1));
    final thisWeek = await cal.occurrencesBetween(monday, monday.add(const Duration(days: 6)));
    final tutors = [
      for (final l in thisWeek.values) for (final o in l) if (o.kind == ActivityKind.tutor && ids.contains(o.subjectId)) o
    ];
    final todays = [
      for (final o in week[today] ?? const <Occurrence>[])
        if (ids.contains(o.subjectId) && o.status != OccurrenceStatus.moved) o
    ];

    // สอบถัดไป
    (Activity, DateTime)? exam;
    for (final s in subjects) {
      for (final a in await cal.activitiesForSubject(s.id)) {
        if (a.kind != ActivityKind.exam) continue;
        final at = a.startMinute == null ? a.startDate : atMinute(a.startDate, a.startMinute!);
        if (at.isBefore(today)) continue;
        if (exam == null || at.isBefore(exam.$2)) exam = (a, at);
      }
    }
    if (!mounted) return;
    setState(() {
      _termLabel = term == null ? 'เทอมนี้' : 'ปี ${term.year} ภาค ${term.termNo == 3 ? 'ฤดูร้อน' : term.termNo}';
      _rows = rows;
      _review = review;
      _nextClass = next;
      _nextExam = exam;
      _tutor = (tutors.where((o) => o.status == OccurrenceStatus.done).length, tutors.length);
      _today = todays;
      _loaded = true;
    });
  }

  Color _levelColor(NoirColors c, double? v) => v == null ? c.muted : (v >= 80 ? c.good : (v >= 60 ? c.warn : c.bad));

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    final avgs = [for (final r in _rows) if (r.average != null) r.average!];
    final avg = avgs.isEmpty ? null : avgs.reduce((a, b) => a + b) / avgs.length;
    final now = DateTime.now();
    String inText(DateTime t) {
      final m = t.difference(now).inMinutes;
      if (m < 60) return 'อีก $m นาที';
      if (m < 24 * 60) return 'อีก ${m ~/ 60} ชม.';
      return thaiShortDate(t);
    }

    final next = _nextClass;
    final exam = _nextExam;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 32), children: [
      Wrap(spacing: 12, runSpacing: 12, children: [
        _kpi(c, 'คาบถัดไป', next == null ? '—' : '${fmtTime(next.startAt!)} ${next.title.replaceFirst('เรียน · ', '')}',
            next == null ? 'ไม่มีใน 2 สัปดาห์' : inText(next.startAt!), key: 'ov-next'),
        _kpi(c, 'สอบถัดไป', exam == null ? '—' : '${exam.$2.difference(dayOnly(now)).inDays} วัน',
            exam == null ? 'ยังไม่มีวันสอบ' : '${exam.$1.name} · ${thaiShortDate(exam.$2)}', key: 'ov-exam'),
        _kpi(c, 'ติวสัปดาห์นี้', '${_tutor.$1} / ${_tutor.$2}', 'รอบที่ทำแล้ว', key: 'ov-tutor',
            ratio: _tutor.$2 == 0 ? null : _tutor.$1 / _tutor.$2),
        _kpi(c, 'เข้าใจเฉลี่ย', avg == null ? '—' : '${avg.round()}%', 'ต้องทวน ${_review.length} หัวข้อ',
            key: 'ov-avg', color: _levelColor(c, avg)),
      ]),
      const SizedBox(height: 18),
      Row(children: [
        Expanded(child: Text('วิชา · $_termLabel', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
        Text('คลิก = เปิดวิชา', style: TextStyle(fontSize: 12, color: c.muted)),
      ]),
      const SizedBox(height: 8),
      if (_rows.isEmpty) Text('ยังไม่มีวิชา · เพิ่มที่แท็บ "รายวิชา" หรือ "แผน 4 ปี"', style: TextStyle(color: c.muted)),
      Wrap(spacing: 10, runSpacing: 10, children: [
        for (final r in _rows)
          SizedBox(
            width: 230,
            child: Material(
              color: c.surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
              child: InkWell(
                key: ValueKey('ov-subject-${r.subject.id}'),
                borderRadius: BorderRadius.circular(14),
                onTap: () => widget.onOpenSubject(r.subject),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(children: [
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(alignment: Alignment.center, children: [
                        CircularProgressIndicator(
                          value: (r.average ?? 0) / 100,
                          strokeWidth: 4,
                          backgroundColor: c.surface2,
                          color: _levelColor(c, r.average),
                        ),
                        Text(r.average == null ? '—' : '${r.average!.round()}',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: c.text)),
                      ]),
                    ),
                    const SizedBox(width: 10),
                    Container(width: 3, height: 32, color: subjectColorOf(r.subject)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(r.subject.name,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                        Text(r.review == 0 ? (r.average == null ? 'ยังไม่ประเมิน' : 'ไม่มีหัวข้อต้องทวน') : 'ต้องทวน ${r.review}',
                            style: TextStyle(fontSize: 12, color: r.review == 0 ? c.muted : c.warn)),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
      ]),
      const SizedBox(height: 18),
      LayoutBuilder(builder: (context, box) {
        final review = _box(c, 'ต้องทวนก่อนสอบ', '${_review.length}', [
          if (_review.isEmpty) Text('ไม่มี · ประเมินหัวข้อในแท็บรายวิชา', style: TextStyle(fontSize: 12, color: c.muted)),
          for (final t in _review.take(6))
            _line(c, Container(width: 8, height: 8, decoration: BoxDecoration(color: _levelColor(c, t.score?.toDouble()), shape: BoxShape.circle)),
                t.topic, '${t.subject} · ${t.chapter}'),
        ]);
        final todays = _box(c, 'การเรียนวันนี้', '${_today.length}', [
          if (_today.isEmpty) Text('วันนี้ไม่มีคาบ / ติว', style: TextStyle(fontSize: 12, color: c.muted)),
          for (final o in _today)
            _line(
              c,
              Text(o.timed ? fmtTime(o.startAt!) : '—', style: TextStyle(fontSize: 12, color: c.muted)),
              o.title,
              o.status == OccurrenceStatus.done ? '✓ ทำแล้ว' : (o.status == OccurrenceStatus.cancelled ? 'ยกเลิก' : ''),
            ),
        ]);
        return box.maxWidth >= 720
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: review),
                const SizedBox(width: 12),
                Expanded(child: todays),
              ])
            : Column(children: [review, const SizedBox(height: 12), todays]);
      }),
    ]);
  }

  Widget _kpi(NoirColors c, String k, String v, String sub, {required String key, double? ratio, Color? color}) => Container(
        width: 220,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(k, style: TextStyle(fontSize: 12, color: c.muted)),
          Text(v,
              key: Key(key),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: color ?? c.text)),
          if (ratio != null) ...[
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: ratio, minHeight: 6, backgroundColor: c.surface2, color: c.accent),
            ),
          ],
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted)),
        ]),
      );

  Widget _box(NoirColors c, String title, String count, List<Widget> children) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text(title, style: TextStyle(fontWeight: FontWeight.w600, color: c.text))),
            Text(count, style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
          const SizedBox(height: 6),
          ...children,
        ]),
      );

  Widget _line(NoirColors c, Widget lead, String text, String right) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 44, child: Align(alignment: Alignment.centerLeft, child: lead)),
          Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13, color: c.text))),
          const SizedBox(width: 8),
          Flexible(child: Text(right, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: c.muted))),
        ]),
      );
}
