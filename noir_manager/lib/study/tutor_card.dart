import 'package:flutter/material.dart';

import '../calendar/calendar_flows.dart';
import '../calendar/calendar_listener.dart';
import '../calendar/calendar_models.dart';
import '../calendar/calendar_ui.dart';
import '../calendar/slot_picker.dart';
import '../data/study_models.dart';
import '../data/study_repository.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import 'mastery.dart' show GradingMode;
import 'subject_colors.dart';
import 'tutor_plan.dart';

/// ความยาวรอบติวที่ตั้งได้ (นาที)
const tutorLengths = [30, 45, 60, 90, 120];

/// การ์ด "รอบติวสัปดาห์นี้": นับรอบ (เรียน + ติว) · ความยาวรอบ · เนื้อหารอบถัดไป · หาเวลาติว
class TutorCard extends StatefulWidget {
  const TutorCard({super.key, required this.subject, required this.chapters});

  final Subject subject;
  final List<ChapterWithTopics> chapters;

  @override
  State<TutorCard> createState() => _TutorCardState();
}

class _TutorCardState extends State<TutorCard> with CalendarListener<TutorCard> {
  List<Occurrence> _week = [];

  /// วันคาบแรกของวิชา (ใช้คิดเป้าสัปดาห์แรก)
  DateTime? _firstClass;
  int _minutes = 90;

  /// บทถัดไปเคยติวมาแล้วกี่รอบ (จาก tutor_log)
  int _chapterRounds = 0;
  int? _loadedFor;
  StudyRepository? _settings;

  // กฎติวตามบทที่เรียนถึง
  List<ClassLog> _logs = [];
  bool _advanced = false;
  int _pass = defaultTutorPass;
  bool _rest = false;

  List<ChapterWithTopics> get _scope => tutorScope(widget.chapters, _logs);
  bool get _passed => scopePassed(_scope, _pass);

  @override
  void didChangeDependencies() {
    _settings = StudyScope.of(context); // ต้องมีก่อน super (super เรียก reload)
    super.didChangeDependencies();
  }

  DateTime get _monday => mondayOf(DateTime.now());

  /// วันแรกที่งานนี้เกิดจริง (ดูไปข้างหน้าไม่เกิน 2 สัปดาห์)
  static DateTime? _firstDayOf(Activity a) {
    var d = dayOnly(a.startDate);
    for (var i = 0; i < 14; i++) {
      if (occursOn(a, d)) return d;
      d = DateTime(d.year, d.month, d.day + 1);
    }
    return null;
  }

  @override
  void didUpdateWidget(TutorCard old) {
    super.didUpdateWidget(old);
    if (old.subject.id != widget.subject.id ||
        old.subject.tutorMinutes != widget.subject.tutorMinutes ||
        old.chapters != widget.chapters) {
      reload();
    }
  }

  @override
  Future<void> reload() async {
    final id = widget.subject.id;
    final settings = _settings!;
    // สร้างครั้งของงานในสัปดาห์นี้ให้ครบก่อน แล้วค่อยกรองเฉพาะวิชานี้
    final week = <Occurrence>[];
    for (var i = 0; i < 7; i++) {
      final d = DateTime(_monday.year, _monday.month, _monday.day + i);
      week.addAll((await calendar!.occurrencesOn(d)).where((o) => o.subjectId == id));
    }
    // ความยาวรอบ: อ่านจากวิชาครั้งแรกที่เปิดวิชานี้ · หลังจากนั้นใช้ค่าที่กดเลือกล่าสุด
    final minutes = _loadedFor == id ? _minutes : widget.subject.tutorMinutes;
    final classActs = (await calendar!.activitiesForSubject(id)).where((a) => a.kind == ActivityKind.classSession);
    final firstClass = classActs.isEmpty
        ? null
        : classActs.map(_firstDayOf).whereType<DateTime>().fold<DateTime?>(
            null, (m, d) => m == null || d.isBefore(m) ? d : m);
    final logs = await settings.classLogs(id);
    final advanced = await settings.gradingMode() == GradingMode.advanced;
    final pass = int.tryParse(await settings.getSetting(tutorPassKey) ?? '') ?? defaultTutorPass;
    final rest = await settings.getSetting(restKey(id, _monday)) == 'on';
    final plan = planTutor(tutorScope(widget.chapters, logs), minutes);
    final done = plan.chapter == null ? 0 : await settings.tutorCount(plan.chapter!.id);
    if (!mounted || id != widget.subject.id) return;
    setState(() {
      _logs = logs;
      _advanced = advanced;
      _pass = pass;
      _rest = rest;
      _week = week;
      _firstClass = firstClass;
      _minutes = minutes;
      _loadedFor = id;
      _chapterRounds = done;
    });
  }

  Future<void> _setMinutes(int m) async {
    setState(() => _minutes = m);
    await _settings!.setTutorMinutes(widget.subject.id, m);
  }

  Future<void> _setRest(bool v) async {
    setState(() => _rest = v);
    await _settings!.setSetting(restKey(widget.subject.id, _monday), v ? 'on' : '');
  }

  /// [preview] = บทถัดไปที่ยังไม่ได้เรียน → "อ่านล่วงหน้า" (สิทธิผู้ใช้ ไม่บังคับ)
  Future<void> _findTime({ChapterWithTopics? preview}) async {
    final repo = calendar!;
    final today = dayOnly(DateTime.now());
    final classDays = {
      for (final o in _week)
        if (o.kind == ActivityKind.classSession) dayOnly(o.day),
    };
    final plan = planTutor(_scope, _minutes);
    final colors = await loadSubjectColors(_settings!);
    final names = {for (final s in await _settings!.subjects()) s.id: s.name};
    if (!mounted) return;
    final picked = await pickFreeSlot(
      context,
      repo,
      title: 'หาเวลาติว · ${widget.subject.name}',
      minutes: _minutes,
      days: [for (var i = 0; i < 7; i++) DateTime(today.year, today.month, today.day + i)],
      avoidDays: classDays,
      subjectColors: colors,
      subjectNames: names,
      subjectId: widget.subject.id,
      note: preview != null
          ? 'อ่านล่วงหน้า: ${preview.chapter.name} (ก่อนเข้าเรียน)'
          : plan.chapter == null
              ? 'รอบนี้: ทวนหัวข้อที่ยังไม่ดี ${plan.review.length} หัวข้อ'
              : 'รอบนี้: ${plan.chapter!.name}'
                  '${plan.review.isEmpty ? '' : ' + ทวน ${plan.review.length} หัวข้อ'}',
    );
    if (picked == null) return;
    if (picked.minutes != _minutes) await _setMinutes(picked.minutes);
    final learn = studyCategoryId(await repo.categories());
    await repo.addActivity(NewActivity(
      name: '${preview != null ? 'อ่านล่วงหน้า' : 'ติว'} · ${widget.subject.name}',
      categoryId: learn,
      importance: widget.subject.importance,
      timed: true,
      day: picked.day,
      startMinute: picked.start,
      durationMin: picked.minutes,
      subjectId: widget.subject.id,
      kind: ActivityKind.tutor,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final scope = _scope;
    final q = weekQuota(widget.subject.sessionsPerWeek, _week,
        advanced: _advanced, passed: _passed, today: DateTime.now(), monday: _monday, firstClass: _firstClass);
    final plan = planTutor(scope, _minutes);
    final reached = reachedIndex(widget.chapters, _logs);
    final avg = scopeAverage(scope);
    final focus = weakestFirst(scope).take(3).toList();
    final ahead = reached != null && reached + 1 < widget.chapters.length ? widget.chapters[reached + 1] : null;
    final sunday = _monday.add(const Duration(days: 6));
    final tutors = _week.where((o) => o.kind == ActivityKind.tutor && o.active).toList()
      ..sort((a, b) => a.startAt!.compareTo(b.startAt!));
    final title = TextStyle(fontWeight: FontWeight.w600, color: c.text);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('สัปดาห์นี้ · ${thaiShortDate(_monday)} – ${thaiShortDate(sunday)}', style: title),
            const SizedBox(height: 8),
            // เป้า · เรียน · ติว
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Chip(q.firstWeek ? 'เป้าสัปดาห์แรก ${q.weekTarget} รอบ' : 'เป้า ${q.target} รอบ', c.surface2, c.text),
              _Chip('เรียน ${q.classes}', c.navBg, c.navText),
              _Chip('ติว ${q.tutors}/${q.tutorNeeded}', c.surface2, c.text),
              if (q.passed)
                _Chip('ผ่าน ${avg!.round()}% · พักได้', c.greenBg, c.greenText)
              else if (q.firstWeek && q.tutorNeeded == 0)
                _Chip('สัปดาห์แรก · เริ่มติวสัปดาห์หน้า', c.greenBg, c.greenText)
              else if (q.remaining == 0)
                _Chip(q.tutorNeeded == 0 ? 'คาบเรียนครบเป้าแล้ว' : 'ครบแล้ว', c.greenBg, c.greenText)
              else
                _Chip('ต้องติวอีก ${q.remaining} รอบ${q.cappedByDays ? ' (เหลือ ${q.daysLeft} วัน)' : ''}', c.amberBg,
                    c.amberText),
            ]),
            // เรียนถึงบทไหน → ขอบเขตติว
            if (reached != null) ...[
              const SizedBox(height: 12),
              Text('เรียนถึง บท ${reached + 1} / ${widget.chapters.length} · ติวในขอบเขตนี้',
                  style: TextStyle(fontSize: 13, color: c.muted)),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: (reached + 1) / widget.chapters.length,
                  minHeight: 5,
                  backgroundColor: c.surface2,
                ),
              ),
            ],
            // ผ่านเกณฑ์ → เลือกพัก หรือติวต่อ
            if (q.passed) ...[
              const SizedBox(height: 10),
              Text('บทที่เรียนแล้วเฉลี่ย ${avg!.round()}% (เกณฑ์ $_pass%) · สัปดาห์นี้เลือกได้',
                  style: TextStyle(fontSize: 13, color: c.text)),
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                ChoiceChip(label: const Text('พักสัปดาห์นี้'), selected: _rest, onSelected: (_) => _setRest(true)),
                ChoiceChip(label: const Text('ติวต่อ'), selected: !_rest, onSelected: (_) => _setRest(false)),
              ]),
            ],
            // หัวข้อที่ควรติวก่อน (อ่อนสุดก่อน)
            if (reached != null && focus.isNotEmpty && !(q.passed && _rest)) ...[
              const SizedBox(height: 12),
              Text('ติวก่อน (อ่อนสุดก่อน)', style: TextStyle(fontSize: 13, color: c.muted)),
              for (final t in focus)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(children: [
                    Expanded(child: Text(t.name, style: TextStyle(fontSize: 13, color: c.text))),
                    Text(t.latestScore == null ? 'ยังไม่ประเมิน' : '${t.latestScore}%',
                        style: TextStyle(fontSize: 13, color: c.muted)),
                  ]),
                ),
            ],
            if (ahead != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _findTime(preview: ahead),
                  icon: const Icon(Icons.arrow_forward, size: 18),
                  label: Text('อ่าน${ahead.chapter.name}ล่วงหน้า (ไม่บังคับ)'),
                ),
              ),
            const SizedBox(height: 12),

            const SizedBox(height: 12),
            // ปุ่มหลักปุ่มเดียว · ความยาวรอบเลือกในหน้าจอง
            FilledButton.icon(
              onPressed: _findTime,
              icon: const Icon(Icons.event_available_outlined),
              label: Text(q.remaining == 0 ? 'จองเวลาติวเพิ่ม' : 'จองเวลาติว'),
            ),
            const SizedBox(height: 14),
            // เนื้อหารอบถัดไป
            Text(
              plan.chapter == null
                  ? (plan.review.isEmpty
                      ? 'รอบถัดไป: ติวครบทุกบทแล้ว ไม่มีหัวข้อที่ต้องทวน'
                      : 'รอบถัดไป: ทวนอย่างเดียว')
                  : 'รอบถัดไป · ${durationText(_minutes)}: ${plan.chapter!.name} · ${chapterKindLabel(plan.chapter!.kind)}'
                      '${_chapterRounds == 0 ? '' : ' · ติวมาแล้ว $_chapterRounds รอบ'}',
              style: title,
            ),
            const SizedBox(height: 4),
            for (final s in plan.steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  SizedBox(
                    width: 64,
                    child: Text('${s.minutes} นาที', style: TextStyle(fontSize: 13, color: c.muted)),
                  ),
                  Expanded(child: Text(s.label, style: TextStyle(fontSize: 13, color: c.text))),
                ]),
              ),
            Text('จบรอบแล้วเว้น 10 นาที พักเงียบ ไม่เล่นจอ',
                style: TextStyle(fontSize: 12, color: c.muted)),

            // รอบติวที่จองแล้ว
            if (tutors.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('จองแล้ว', style: title),
              for (final o in tutors)
                // คลิก = รายละเอียด · คลิกขวา / กดค้าง = ทำแล้ว / เลื่อน / ลบ
                OccurrenceMenuArea(o: o, child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: Icon(
                    o.status == OccurrenceStatus.done ? Icons.check_circle : Icons.school_outlined,
                    color: o.status == OccurrenceStatus.done ? c.good : c.accent,
                  ),
                  title: Text('${thaiShortDate(o.day)} · ${fmtTime(o.startAt!)}–${fmtTime(o.endAt!)}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showOccurrenceDetails(context, o),
                )),
            ],
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, this.bg, this.fg);
  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 13, color: fg, fontWeight: FontWeight.w600)),
      );
}
