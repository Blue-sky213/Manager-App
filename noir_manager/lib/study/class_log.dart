import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../data/study_repository.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';

/// ค่าที่กรอกในกล่อง "คาบนี้เรียนถึงไหน"
class _LogInput {
  const _LogInput({this.chapterId, this.newChapter, required this.topics, required this.finished, this.note});
  final int? chapterId;
  final String? newChapter; // ไม่ null = สร้างบทใหม่ชื่อนี้
  final List<String> topics;
  final bool finished;
  final String? note;
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

/// กล่อง "คาบนี้เรียนถึงไหน": เลือกบท (หรือบทใหม่) · หัวข้อที่เรียน · จบบทไหม · โน้ต
/// บันทึกแล้ว บทนั้นกลายเป็นบทที่รอบติวหยิบไปติวต่อ · คืน true ถ้าบันทึก
Future<bool> showClassLogDialog(BuildContext context,
    {required int subjectId, required DateTime day, int? occurrenceId, ClassLog? existing}) async {
  final repo = StudyScope.of(context);
  final chapters = await repo.chapters(subjectId);
  if (!context.mounted) return false;
  final input = await showDialog<_LogInput>(
    context: context,
    builder: (_) => _ClassLogDialog(
      day: day,
      chapters: chapters,
      initialChapter: existing?.chapterId ?? guessChapter(chapters),
      initialFinished: existing?.finished ?? false,
      initialNote: existing?.note,
    ),
  );
  if (input == null) return false;
  return saveClassLog(repo, subjectId, day,
      occurrenceId: occurrenceId ?? existing?.occurrenceId,
      chapterId: input.chapterId,
      newChapter: input.newChapter,
      topics: input.topics,
      finished: input.finished,
      note: input.note);
}

/// บันทึกจริง (แยกออกมาให้เทสได้โดยไม่ต้องเปิดกล่อง)
Future<bool> saveClassLog(StudyRepository repo, int subjectId, DateTime day,
    {int? occurrenceId, int? chapterId, String? newChapter, List<String> topics = const [], bool finished = false, String? note}) async {
  var ch = chapterId;
  if (newChapter != null && newChapter.trim().isNotEmpty) {
    ch = await repo.addChapter(subjectId, newChapter.trim());
  }
  if (ch != null) {
    final existing = (await repo.chapters(subjectId))
        .where((c) => c.chapter.id == ch)
        .expand((c) => c.subtopics.map((t) => t.name))
        .toSet();
    for (final t in topics) {
      if (t.isNotEmpty && !existing.contains(t)) await repo.addSubtopic(ch, t);
    }
  }
  await repo.logClass(subjectId, day, occurrenceId: occurrenceId, chapterId: ch, finished: finished, note: note);
  return true;
}

class _ClassLogDialog extends StatefulWidget {
  const _ClassLogDialog({
    required this.day,
    required this.chapters,
    this.initialChapter,
    this.initialFinished = false,
    this.initialNote,
  });

  final DateTime day;
  final List<ChapterWithTopics> chapters;
  final int? initialChapter;
  final bool initialFinished;
  final String? initialNote;

  @override
  State<_ClassLogDialog> createState() => _ClassLogDialogState();
}

class _ClassLogDialogState extends State<_ClassLogDialog> {
  static const _newId = -1;
  late int? _chapter = widget.chapters.isEmpty ? _newId : widget.initialChapter;
  late bool _finished = widget.initialFinished;
  final _newName = TextEditingController();
  final _topics = TextEditingController();
  late final _note = TextEditingController(text: widget.initialNote ?? '');

  @override
  void dispose() {
    _newName.dispose();
    _topics.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return AlertDialog(
      title: Text('คาบ ${thaiShortDate(widget.day)} เรียนถึงไหน'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            DropdownButtonFormField<int>(
              initialValue: _chapter,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'บทที่เรียน'),
              items: [
                for (final ch in widget.chapters)
                  DropdownMenuItem(
                    value: ch.chapter.id,
                    child: Text('${ch.chapter.name} · ${chapterStatusLabel(ch.chapter.status)}',
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                const DropdownMenuItem(value: _newId, child: Text('+ บทใหม่')),
              ],
              onChanged: (v) => setState(() => _chapter = v),
            ),
            if (_chapter == _newId)
              TextField(
                controller: _newName,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'ชื่อบทใหม่', hintText: 'เช่น บท 3 ฟังก์ชัน'),
              ),
            TextField(
              controller: _topics,
              decoration: const InputDecoration(
                labelText: 'หัวข้อที่เรียน (ไม่ใส่ก็ได้)',
                hintText: 'คั่นด้วย , เช่น for loop, while loop',
              ),
            ),
            const SizedBox(height: 14),
            SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: false, label: Text('เรียนถึงกลางบท')),
                ButtonSegment(value: true, label: Text('จบบทนี้แล้ว')),
              ],
              selected: {_finished},
              onSelectionChanged: (v) => setState(() => _finished = v.first),
            ),
            TextField(
              controller: _note,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'โน้ต (ไม่ใส่ก็ได้)', hintText: 'เช่น อาจารย์สั่งงาน 3 ส่งศุกร์'),
            ),
            const SizedBox(height: 8),
            Text('บทนี้จะเป็นบทที่รอบติวหยิบไปติวต่อ', style: TextStyle(fontSize: 12, color: c.muted)),
          ]),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('ข้าม')),
        FilledButton(
          onPressed: () {
            final isNew = _chapter == _newId;
            if (isNew && _newName.text.trim().isEmpty) return;
            Navigator.pop(
              context,
              _LogInput(
                chapterId: isNew ? null : _chapter,
                newChapter: isNew ? _newName.text.trim() : null,
                topics: [for (final t in _topics.text.split(',')) t.trim()]..removeWhere((t) => t.isEmpty),
                finished: _finished,
                note: _note.text,
              ),
            );
          },
          child: const Text('บันทึก'),
        ),
      ],
    );
  }
}

/// การ์ด "คาบที่เรียนแล้ว" ในแท็บบทเรียน: ดูว่าแต่ละคาบเรียนบทไหน จบไหม · เพิ่ม / แก้ / ลบ
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
