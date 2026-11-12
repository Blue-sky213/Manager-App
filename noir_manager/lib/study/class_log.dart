import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../calendar/calendar_ui.dart' show pickMinute;
import '../data/study_models.dart';
import '../data/study_repository.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import 'attendance.dart';
import 'grading.dart';

/// ค่าที่กรอกในกล่อง "คาบนี้เรียนถึงไหน"
class ClassLogInput {
  const ClassLogInput({
    this.chapterId,
    this.newChapter,
    this.topics = const [],
    this.newTopics = const [],
    this.finished = false,
    this.note,
    this.homework,
    this.dueAt,
    this.gradePartId,
    this.actualEnd,
  });
  final int? chapterId;
  final String? newChapter; // ไม่ null = สร้างบทใหม่ชื่อนี้
  final List<String> topics; // หัวข้อที่มีอยู่แล้วที่เรียนคาบนี้
  final List<String> newTopics; // หัวข้อใหม่ (สร้างในบทด้วย)
  final bool finished;
  final String? note;
  final String? homework; // null = ไม่มีงาน
  final DateTime? dueAt;
  final int? gradePartId; // นับงานนี้เป็นชิ้นคะแนนในส่วนไหน (null = ไม่นับ)
  final DateTime? actualEnd; // เวลาเลิกจริง (แผ่น "ทำแล้ว") · null = ไม่บันทึก
}

/// บทที่น่าจะเรียนในคาบนี้: บทที่กำลังเรียนอยู่ → บทแรกที่ยังไม่เริ่ม
int? guessChapter(List<ChapterWithTopics> chapters) {
  for (final c in chapters) {
    if (c.chapter.status == ChapterStatus.learning) return c.chapter.id;
  }
  for (final c in chapters) {
    if (c.chapter.status == ChapterStatus.todo) return c.chapter.id;
  }
  return chapters.isEmpty ? null : chapters.last.chapter.id;
}

/// กำหนดส่งแบบลัด: อาทิตย์หน้า = วันเดียวกันสัปดาห์หน้า เวลาเดิม
DateTime nextWeek(DateTime day, {int hour = 23, int minute = 59}) =>
    DateTime(day.year, day.month, day.day + 7, hour, minute);

/// "พ. 17 พ.ย. 23:59 · อีก 7 วัน"
String dueText(DateTime due, {DateTime? now}) {
  final today = dayOnly(now ?? DateTime.now());
  final days = dayOnly(due).difference(today).inDays;
  final left = days < 0 ? 'เลยมา ${-days} วัน' : (days == 0 ? 'วันนี้' : (days == 1 ? 'พรุ่งนี้' : 'อีก $days วัน'));
  return '${thaiShortDate(due)} ${_hm(due)} · $left';
}

String _hm(DateTime d) => '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

/// ตั้งค่า: กด "ทำแล้ว" ที่คาบเรียนแล้วเปิดแผ่นบันทึกไหม ('off' = ไม่ต้องถาม)
const askClassLogKey = 'ask_class_log';

/// กล่อง "คาบนี้เรียนถึงไหน" · คืน true ถ้าบันทึก
/// [occurrence] = คาบในปฏิทิน (มีช่องเวลาเลิกจริง) · [justDone] = เพิ่งกด "ทำแล้ว" → หัวเป็น ✓ ปุ่ม "แค่ทำแล้ว"
/// จอแคบ (มือถือ) เปิดเป็นแผ่นจากด้านล่าง · จอกว้างเป็นกล่องกลางจอ
Future<bool> showClassLogDialog(BuildContext context,
    {required int subjectId,
    required DateTime day,
    int? occurrenceId,
    ClassLog? existing,
    Occurrence? occurrence,
    bool justDone = false}) async {
  final repo = StudyScope.of(context);
  final cal = CalendarScope.of(context);
  final chapters = await repo.chapters(subjectId);
  final parts = await repo.gradeParts(subjectId);
  final next = await nextClassAfter(cal, subjectId, day);
  if (!context.mounted) return false;
  final input = await showMiniForm<ClassLogInput>(
    context,
    (_) => _ClassLogDialog(
      subjectId: subjectId,
      day: day,
      chapters: chapters,
      parts: parts,
      nextClass: next,
      existing: existing,
      occurrence: occurrence,
      justDone: justDone,
    ),
  );
  if (input == null) return false;
  final occ = occurrence;
  if (input.actualEnd != null && occ != null) await cal.setActualTimes(occ.id, end: input.actualEnd);
  await saveClassLog(repo, subjectId, day, input,
      calendar: cal, occurrenceId: occurrenceId ?? occ?.id ?? existing?.occurrenceId, existing: existing);
  return true;
}

/// บันทึกจริง (แยกออกมาให้เทสได้โดยไม่ต้องเปิดกล่อง)
/// สร้างบท/หัวข้อใหม่ · งาน "ส่ง: …" ในปฏิทิน (ครั้งแรกครั้งเดียว) · ชิ้นคะแนน · แล้วเก็บบันทึก
Future<int> saveClassLog(StudyRepository repo, int subjectId, DateTime day, ClassLogInput input,
    {CalendarRepository? calendar, int? occurrenceId, ClassLog? existing}) async {
  var ch = input.chapterId;
  if (input.newChapter != null && input.newChapter!.trim().isNotEmpty) {
    ch = await repo.addChapter(subjectId, input.newChapter!.trim());
  }
  if (ch != null) {
    final have = (await repo.chapters(subjectId))
        .where((c) => c.chapter.id == ch)
        .expand((c) => c.subtopics.map((t) => t.name))
        .toSet();
    for (final t in input.newTopics) {
      if (t.isNotEmpty && !have.contains(t)) await repo.addSubtopic(ch, t);
    }
  }

  final hw = input.homework?.trim();
  final hasHw = hw != null && hw.isNotEmpty;
  var taskId = existing?.taskActivityId;
  if (hasHw && input.dueAt != null && taskId == null && calendar != null) {
    final subject = (await repo.subjects()).where((s) => s.id == subjectId).firstOrNull;
    final cats = await calendar.categories();
    final cat = cats.where((c) => c.name == 'งาน').firstOrNull?.id ?? studyCategoryId(cats) ?? cats.firstOrNull?.id;
    final due = input.dueAt!;
    final end = due.hour * 60 + due.minute;
    // แสดงเป็นช่อง 30 นาทีที่จบตรงเวลาส่ง
    final start = (end - 30).clamp(0, 24 * 60 - 30);
    taskId = await calendar.addActivity(NewActivity(
      name: 'ส่ง: $hw${subject == null ? '' : ' · ${subject.name}'}',
      categoryId: cat,
      importance: 3,
      timed: true,
      day: dayOnly(due),
      startMinute: start,
      durationMin: 30,
      subjectId: subjectId,
    ));
  }
  if (hasHw && input.gradePartId != null && (existing?.homework == null)) {
    final part = (await repo.gradeParts(subjectId)).where((p) => p.id == input.gradePartId).firstOrNull;
    if (part != null) {
      await repo.addGradeItem(part.id, hw, part.items.isEmpty ? 5 : part.items.last.full);
    }
  }

  return repo.logClass(subjectId, day,
      occurrenceId: occurrenceId,
      chapterId: ch,
      finished: input.finished,
      note: input.note,
      topics: [...input.topics, ...input.newTopics.where((t) => !input.topics.contains(t))],
      homework: hasHw ? hw : null,
      dueAt: hasHw ? input.dueAt : null,
      taskActivityId: hasHw ? taskId : null);
}

class _ClassLogDialog extends StatefulWidget {
  const _ClassLogDialog({
    required this.subjectId,
    required this.day,
    required this.chapters,
    required this.parts,
    this.nextClass,
    this.existing,
    this.occurrence,
    this.justDone = false,
  });

  final Occurrence? occurrence;
  final bool justDone;
  final int subjectId;
  final DateTime day;
  final List<ChapterWithTopics> chapters;
  final List<GradePart> parts;
  final DateTime? nextClass;
  final ClassLog? existing;

  @override
  State<_ClassLogDialog> createState() => _ClassLogDialogState();
}

class _ClassLogDialogState extends State<_ClassLogDialog> {
  static const _newId = -1;
  late List<ChapterWithTopics> _chapters = widget.chapters;
  late int? _chapter = _chapters.isEmpty ? null : (widget.existing?.chapterId ?? guessChapter(_chapters));
  late bool _finished = widget.existing?.finished ?? false;
  late final Set<String> _picked = {...?widget.existing?.topics};
  final _newName = TextEditingController();
  final _newTopics = TextEditingController();
  late final _note = TextEditingController(text: widget.existing?.note ?? '');

  // งาน / การบ้าน
  late bool _hw = widget.existing?.homework != null;
  late final _hwName = TextEditingController(text: widget.existing?.homework ?? '');
  late DateTime? _due = widget.existing?.dueAt;
  int? _gradePart;

  // เวลาเลิกจริง: เริ่มที่เวลาที่บันทึกไว้ / เวลาเลิกตามตาราง
  late DateTime? _end = widget.occurrence?.actualEnd ?? widget.occurrence?.endAt;

  Future<void> _pickEnd() async {
    final o = widget.occurrence!;
    final m = await pickMinute(context, minuteOf(_end ?? o.endAt!), title: 'เวลาเลิกจริง');
    if (m == null || !mounted) return;
    setState(() => _end = atMinute(o.day, m));
  }

  /// กดบันทึกแล้วยังขาดช่องที่ต้องกรอก → ขึ้นแดงที่ช่องนั้น
  bool _showErrors = false;
  String? _err(TextEditingController t, String msg) => _showErrors && t.text.trim().isEmpty ? msg : null;

  @override
  void dispose() {
    _newName.dispose();
    _newTopics.dispose();
    _note.dispose();
    _hwName.dispose();
    super.dispose();
  }

  /// ใส่รายการบทตาม course outline ทีเดียว (บรรทัดละบท)
  Future<void> _addOutline() async {
    final ctl = TextEditingController();
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => MiniForm(
        title: 'รายการบทตาม course outline',
        primaryLabel: 'เพิ่มทุกบท',
        onPrimary: () => Navigator.pop(ctx, true),
        children: [
          TextField(
            controller: ctl,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText: 'บรรทัดละบท เช่น\nบท 1 พื้นฐานภาษา\nบท 2 ลูปและเงื่อนไข\nบท 3 ฟังก์ชัน',
              border: InputBorder.none,
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final repo = StudyScope.of(context);
    for (final line in ctl.text.split('\n')) {
      if (line.trim().isNotEmpty) await repo.addChapter(widget.subjectId, line.trim());
    }
    final chapters = await repo.chapters(widget.subjectId);
    if (!mounted) return;
    setState(() {
      _chapters = chapters;
      _chapter = guessChapter(chapters);
    });
  }

  Future<void> _pickDate() async {
    final base = _due ?? nextWeek(widget.day);
    final d = await showDatePicker(
      context: context,
      initialDate: base,
      firstDate: DateTime(widget.day.year - 1),
      lastDate: DateTime(widget.day.year + 2),
    );
    if (d == null || !mounted) return;
    setState(() => _due = DateTime(d.year, d.month, d.day, base.hour, base.minute));
  }

  Future<void> _pickTime() async {
    final base = _due ?? nextWeek(widget.day);
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: base.hour, minute: base.minute));
    if (t == null || !mounted) return;
    setState(() => _due = DateTime(base.year, base.month, base.day, t.hour, t.minute));
  }

  Future<void> _pickChapter() async {
    final v = await showMiniChoice<int>(context, title: 'บทที่เรียน', current: _chapter, items: [
      for (final ch in _chapters) miniChoice(ch.chapter.id, ch.chapter.name, detail: chapterStatusLabel(ch.chapter.status)),
      miniChoice(_newId, '+ เพิ่มบทเอง'),
    ]);
    if (v == null || !mounted) return;
    setState(() {
      _chapter = v;
      _picked.clear();
    });
  }

  Future<void> _pickDue(DateTime? next, DateTime week) => showMiniSubSheet(context,
      title: 'กำหนดส่ง',
      parentSetState: setState,
      build: (ctx, set) => Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (next != null)
              MiniRow(
                label: 'คาบหน้า',
                valueText: thaiShortDate(next),
                trailing: Icon(_due == next ? Icons.check_circle : Icons.circle_outlined, size: 20),
                onTap: () => set(() => _due = next),
              ),
            MiniRow(
              label: 'อาทิตย์หน้า',
              valueText: thaiShortDate(week),
              trailing: Icon(_due == week ? Icons.check_circle : Icons.circle_outlined, size: 20),
              onTap: () => set(() => _due = week),
            ),
            MiniRow(icon: Icons.event, label: 'เลือกวัน', valueText: _due == null ? '—' : thaiShortDate(_due!), onTap: () async {
              await _pickDate();
              set(() {});
            }),
            MiniRow(icon: Icons.schedule, label: 'เวลา', valueText: _due == null ? '—' : _hm(_due!), last: true, onTap: () async {
              await _pickTime();
              set(() {});
            }),
          ]));

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final current = _chapters.where((ch) => ch.chapter.id == _chapter).firstOrNull;
    final next = widget.nextClass;
    final week = nextWeek(widget.day);
    final o = widget.occurrence;
    final titleText = widget.justDone
        ? '✓ เรียนเสร็จ · ${o?.title.replaceFirst(RegExp(r'^เรียน · '), '') ?? thaiShortDate(widget.day)}'
        : 'บันทึกคาบ · ${thaiShortDate(widget.day)}';
    Widget err(String? msg) => msg == null
        ? const SizedBox.shrink()
        : Padding(padding: const EdgeInsets.only(top: 4), child: Text(msg, style: TextStyle(fontSize: 12, color: c.bad)));
    final part = widget.parts.where((p) => p.id == _gradePart).firstOrNull;

    void save() {
      final isNew = _chapter == _newId;
      if ((isNew && _newName.text.trim().isEmpty) || (_hw && _hwName.text.trim().isEmpty)) {
        setState(() => _showErrors = true);
        return;
      }
      Navigator.pop(
        context,
        ClassLogInput(
          chapterId: isNew ? null : _chapter,
          newChapter: isNew ? _newName.text.trim() : null,
          topics: _picked.toList(),
          newTopics: [for (final t in _newTopics.text.split(',')) t.trim()]..removeWhere((t) => t.isEmpty),
          finished: _finished,
          note: _note.text,
          homework: _hw ? _hwName.text.trim() : null,
          dueAt: _hw ? (_due ?? next ?? week) : null,
          gradePartId: _hw ? _gradePart : null,
          actualEnd: o != null && o.timed && _end != null ? _end : null,
        ),
      );
    }

    return MiniForm(
      title: titleText,
      primaryLabel: 'บันทึก',
      onPrimary: save,
      secondaryLabel: widget.justDone ? 'แค่ทำแล้ว ไม่บันทึก' : 'ข้าม',
      children: [
        // ---- บท = หัวตัวใหญ่ แตะเพื่อเปลี่ยน ----
        if (_chapters.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: c.amberBg, borderRadius: BorderRadius.circular(10)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('วิชานี้ยังไม่มีรายการบท', style: TextStyle(fontWeight: FontWeight.w600, color: c.amberText)),
              const SizedBox(height: 4),
              Text('ใส่บทตาม course outline ก่อน จะได้เลือกบทเดียวกันทุกคาบ อ้างอิงได้',
                  style: TextStyle(fontSize: 13, color: c.amberText)),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _addOutline,
                icon: const Icon(Icons.playlist_add),
                label: const Text('ใส่รายการบท'),
              ),
            ]),
          ),
          if (_chapter != _newId)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _chapter = _newId),
                child: const Text('หรือเพิ่มบทเดียวเอง'),
              ),
            ),
        ] else if (_chapter != _newId)
          InkWell(
            key: const Key('classlog-chapter'),
            onTap: _pickChapter,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: c.line))),
              child: Row(children: [
                Expanded(
                  child: Text(current?.chapter.name ?? 'เลือกบท',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: c.text)),
                ),
                Icon(Icons.expand_more, color: c.muted),
              ]),
            ),
          ),
        if (_chapter == _newId) ...[
          MiniBigField(
            controller: _newName,
            hint: 'ชื่อบทใหม่ เช่น บท 3 ฟังก์ชัน',
            fontSize: 18,
            onChanged: (_) {
              if (_showErrors) setState(() {});
            },
          ),
          err(_err(_newName, 'ใส่ชื่อบท')),
        ],

        // ---- หัวข้อ = ป้าย ----
        if (current != null && current.subtopics.isNotEmpty) ...[
          const MiniLabel('หัวข้อที่เรียนคาบนี้'),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in current.subtopics)
              ChoiceChip(
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                label: Text(t.name),
                selected: _picked.contains(t.name),
                onSelected: (v) => setState(() {
                  if (v) {
                    _picked.add(t.name);
                  } else {
                    _picked.remove(t.name);
                  }
                }),
              ),
          ]),
        ],
        const SizedBox(height: 12),
        MiniSegments<bool>(
          value: _finished,
          items: const [(false, 'เรียนถึงกลางบท'), (true, 'จบบทนี้แล้ว')],
          onChanged: (v) => setState(() => _finished = v),
        ),
        const SizedBox(height: 6),
        if (_chapter != null)
          MiniRow(
            icon: Icons.add,
            label: 'หัวข้อใหม่',
            value: MiniInlineField(controller: _newTopics, hint: 'คั่นด้วย ,', width: 180),
          ),

        // ---- งาน / การบ้าน ----
        MiniSwitchRow(
          icon: _hw ? Icons.star : Icons.star_border,
          label: 'อาจารย์สั่งงาน',
          value: _hw,
          onChanged: (v) => setState(() {
            _hw = v;
            _due ??= next ?? week;
          }),
        ),
        if (_hw) ...[
          MiniRow(
            icon: Icons.assignment_outlined,
            label: 'งานอะไร',
            value: MiniInlineField(
              controller: _hwName,
              hint: 'เช่น บท 2 ข้อ 1–10',
              width: 200,
              onChanged: (_) {
                if (_showErrors) setState(() {});
              },
            ),
          ),
          err(_err(_hwName, 'ใส่ชื่องาน หรือปิดสวิตช์ถ้าไม่มีงาน')),
          MiniRow(
            icon: Icons.event_available,
            label: 'ส่ง',
            valueText: _due == null ? '—' : dueText(_due!),
            onTap: () => _pickDue(next, week),
          ),
          if (widget.parts.isNotEmpty && widget.existing?.homework == null)
            MiniRow(
              icon: Icons.grade_outlined,
              label: 'นับเป็นคะแนนเก็บ',
              valueText: part == null ? 'ไม่นับ' : part.name,
              onTap: () async {
                final v = await showMiniChoice<int>(context, title: 'นับเป็นคะแนนเก็บ', current: _gradePart ?? 0, items: [
                  miniChoice(0, 'ไม่นับ'),
                  for (final p in widget.parts) miniChoice(p.id, p.name, detail: 'ชิ้นใหม่'),
                ]);
                if (v != null && mounted) setState(() => _gradePart = v == 0 ? null : v);
              },
            ),
          if (widget.existing?.taskActivityId != null)
            const MiniLabel('มีงาน "ส่ง" ในปฏิทินแล้ว · ย้ายวันส่งได้ที่ปฏิทิน'),
        ],
        MiniRow(
          icon: Icons.edit_note,
          label: 'โน้ต',
          value: MiniInlineField(controller: _note, hint: 'ไม่ใส่ก็ได้', width: 200),
          last: !(o != null && o.timed && o.endAt != null && (widget.justDone || o.status == OccurrenceStatus.done)),
        ),
        // ---- เวลาเลิกจริง (คาบในปฏิทินที่ทำแล้ว) ----
        if (o != null && o.timed && o.endAt != null && (widget.justDone || o.status == OccurrenceStatus.done))
          MiniRow(
            icon: Icons.schedule,
            label: 'เลิกจริง',
            valueText: '${_hm(_end!)}${_end == o.endAt ? ' (ตามตาราง)' : ''}',
            onTap: _pickEnd,
            last: true,
          ),
      ],
    );
  }
}

/// การ์ด "คาบที่เรียนแล้ว" ในแท็บบทเรียน: คาบไหนเรียนบทไหน · หัวข้อ · ⭐ งานที่สั่ง + กำหนดส่ง
class ClassLogCard extends StatefulWidget {
  const ClassLogCard({super.key, required this.subject, required this.chapters, required this.onChanged});

  final Subject subject;
  final List<ChapterWithTopics> chapters;

  /// บันทึกแล้วสถานะบทเปลี่ยน → ให้หน้าวิชาโหลดบทใหม่
  final VoidCallback onChanged;

  @override
  State<ClassLogCard> createState() => _ClassLogCardState();
}

class _ClassLogCardState extends State<ClassLogCard> {
  List<ClassLog> _logs = const [];
  bool _all = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(ClassLogCard old) {
    super.didUpdateWidget(old);
    if (old.subject.id != widget.subject.id || old.chapters != widget.chapters) _load();
  }

  Future<void> _load() async {
    final logs = await StudyScope.of(context).classLogs(widget.subject.id);
    if (mounted) setState(() => _logs = logs);
  }

  Future<void> _add([ClassLog? existing]) async {
    final repo = StudyScope.of(context);
    final ok = await showClassLogDialog(context,
        subjectId: widget.subject.id, day: existing?.day ?? DateTime.now(), existing: existing);
    if (!ok) return;
    if (existing != null && existing.occurrenceId == null) {
      // บันทึกที่ไม่ผูกคาบ → แก้ = ลบอันเดิมแล้วใช้อันใหม่
      await repo.deleteClassLog(existing.id);
    }
    await _load();
    widget.onChanged();
  }

  Future<void> _menu(ClassLog l, Offset at) async {
    final repo = StudyScope.of(context);
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('edit', Icons.edit_outlined, 'แก้บันทึก'),
      ctxItem('delete', Icons.delete_outline, 'ลบบันทึกนี้', danger: true),
    ]);
    if (!mounted) return;
    if (v == 'edit') {
      await _add(l);
    } else if (v == 'delete') {
      await repo.deleteClassLog(l.id);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final names = {for (final ch in widget.chapters) ch.chapter.id: ch.chapter.name};
    final shown = _all ? _logs : _logs.take(3).toList();
    final pending = _logs.where((l) => l.dueAt != null && !l.dueAt!.isBefore(DateTime.now())).toList()
      ..sort((a, b) => a.dueAt!.compareTo(b.dueAt!));
    return Material(
      color: c.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.line)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(
              child: Text('คาบที่เรียนแล้ว', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text)),
            ),
            TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('บันทึกคาบ')),
          ]),
          // งานที่ยังไม่ถึงกำหนดส่ง ขึ้นบนสุด
          for (final l in pending)
            Padding(
              padding: const EdgeInsets.only(bottom: 4, right: 8),
              child: Row(children: [
                Icon(Icons.star, size: 18, color: c.warn),
                const SizedBox(width: 8),
                Expanded(child: Text(l.homework!, style: TextStyle(fontSize: 14, color: c.text))),
                Text('ส่ง ${dueText(l.dueAt!)}', style: TextStyle(fontSize: 13, color: c.warn)),
              ]),
            ),
          if (_logs.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text('ยังไม่มีบันทึก · หลังเรียนเสร็จ กด "บันทึกคาบ" หรือคลิกขวาที่คาบในปฏิทิน',
                  style: TextStyle(fontSize: 13, color: c.muted)),
            ),
          for (final l in shown)
            GestureDetector(
              onSecondaryTapUp: (d) => _menu(l, d.globalPosition),
              onLongPressStart: (d) => _menu(l, d.globalPosition),
              child: InkWell(
                onTap: () => _add(l),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    SizedBox(
                      width: 92,
                      child: Text(thaiShortDate(l.day), style: TextStyle(fontSize: 13, color: c.muted)),
                    ),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(
                          '${names[l.chapterId] ?? 'ไม่ระบุบท'} · ${l.finished ? 'จบบท' : 'ถึงกลางบท'}',
                          style: TextStyle(fontSize: 14, color: c.text),
                        ),
                        if (l.topics.isNotEmpty)
                          Text(l.topics.join(' · '), style: TextStyle(fontSize: 13, color: c.muted)),
                        if (l.homework != null)
                          Text('⭐ ${l.homework}${l.dueAt == null ? '' : ' · ส่ง ${thaiShortDate(l.dueAt!)} ${_hm(l.dueAt!)}'}',
                              style: TextStyle(fontSize: 13, color: c.warn)),
                        if (l.note != null) Text(l.note!, style: TextStyle(fontSize: 13, color: c.muted)),
                      ]),
                    ),
                    Icon(l.finished ? Icons.check_circle : Icons.timelapse, size: 18, color: l.finished ? c.good : c.warn),
                    const SizedBox(width: 8),
                  ]),
                ),
              ),
            ),
          if (_logs.length > 3)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                onPressed: () => setState(() => _all = !_all),
                child: Text(_all ? 'ย่อ' : 'ดูทั้งหมด ${_logs.length} คาบ'),
              ),
            ),
        ]),
      ),
    );
  }
}
