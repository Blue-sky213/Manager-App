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
  int _minutes = 90;

  /// บทถัดไปเคยติวมาแล้วกี่รอบ (จาก tutor_log)
  int _chapterRounds = 0;
  int? _loadedFor;
  StudyRepository? _settings;

  @override
  void didChangeDependencies() {
    _settings = StudyScope.of(context); // ต้องมีก่อน super (super เรียก reload)
    super.didChangeDependencies();
  }

  DateTime get _monday => mondayOf(DateTime.now());

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
    final plan = planTutor(widget.chapters, minutes);
    final done = plan.chapter == null ? 0 : await settings.tutorCount(plan.chapter!.id);
    if (!mounted || id != widget.subject.id) return;
    setState(() {
      _week = week;
      _minutes = minutes;
      _loadedFor = id;
      _chapterRounds = done;
    });
  }

  Future<void> _setMinutes(int m) async {
    setState(() => _minutes = m);
    await _settings!.setTutorMinutes(widget.subject.id, m);
  }

  Future<void> _findTime() async {
    final repo = calendar!;
    final today = dayOnly(DateTime.now());
    final classDays = {
      for (final o in _week)
        if (o.kind == ActivityKind.classSession) dayOnly(o.day),
    };
    final plan = planTutor(widget.chapters, _minutes);
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
      note: plan.chapter == null
          ? 'รอบนี้: ทวนหัวข้อที่ยังไม่ดี ${plan.review.length} หัวข้อ'
          : 'รอบนี้: ${plan.chapter!.name}'
              '${plan.review.isEmpty ? '' : ' + ทวน ${plan.review.length} หัวข้อ'}',
    );
    if (picked == null) return;
    final learn = studyCategoryId(await repo.categories());
    await repo.addActivity(NewActivity(
      name: 'ติว · ${widget.subject.name}',
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
    final q = weekQuota(widget.subject.sessionsPerWeek, _week);
    final plan = planTutor(widget.chapters, _minutes);
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
            Row(children: [
              Expanded(
                child: Text('รอบติวสัปดาห์นี้ · ${thaiShortDate(_monday)} – ${thaiShortDate(sunday)}',
                    style: title),
              ),
              FilledButton.tonalIcon(
                onPressed: _findTime,
                icon: const Icon(Icons.event_available_outlined),
                label: const Text('หาเวลาติว'),
              ),
            ]),
            const SizedBox(height: 8),
            // เป้า · เรียน · ติว
            Wrap(spacing: 8, runSpacing: 8, children: [
              _Chip('เป้า ${q.target} รอบ', c.surface2, c.text),
              _Chip('เรียน ${q.classes}', c.navBg, c.navText),
              _Chip('ติว ${q.tutors}/${q.tutorNeeded}', c.surface2, c.text),
              q.remaining == 0
                  ? _Chip(q.tutorNeeded == 0 ? 'คาบเรียนครบเป้าแล้ว' : 'ครบแล้ว', c.greenBg, c.greenText)
                  : _Chip('ขาดอีก ${q.remaining} รอบ', c.amberBg, c.amberText),
            ]),
            const SizedBox(height: 12),

            // ความยาวรอบติว
            Row(children: [
              Text('ความยาวรอบ', style: TextStyle(color: c.muted, fontSize: 13)),
              const SizedBox(width: 8),
              Expanded(
                child: Wrap(spacing: 6, runSpacing: 6, children: [
                  for (final m in tutorLengths)
                    ChoiceChip(
                      label: Text(durationText(m)),
                      selected: _minutes == m,
                      onSelected: (_) => _setMinutes(m),
                    ),
                ]),
              ),
            ]),
            const SizedBox(height: 12),

            // เนื้อหารอบถัดไป
            Text(
              plan.chapter == null
                  ? (plan.review.isEmpty
                      ? 'รอบถัดไป: ติวครบทุกบทแล้ว ไม่มีหัวข้อที่ต้องทวน'
                      : 'รอบถัดไป: ทวนอย่างเดียว')
                  : 'รอบถัดไป: ${plan.chapter!.name} · ${chapterKindLabel(plan.chapter!.kind)}'
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
