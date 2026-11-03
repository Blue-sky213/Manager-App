import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../data/study_repository.dart';
import '../data/study_scope.dart';
import '../study/advanced_rules.dart';
import '../study/mastery.dart';
import '../study/score_history_dialog.dart';
import '../study/subtopic_dialog.dart';
import '../theme/noir_colors.dart';
import '../widgets/dialogs.dart';

/// หน้า "วิชา": Study Tree + Mastery Score
/// วิชา → บท → หัวข้อย่อย · แตะหัวข้อย่อยเพื่อบันทึกคะแนน / ติดธง / ลบ
class StudyPage extends StatefulWidget {
  const StudyPage({super.key});

  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  StudyRepository? _repo;
  bool _loading = true;
  List<Subject> _subjects = [];
  int? _subjectId; // วิชาที่เลือกอยู่
  List<ChapterWithTopics> _chapters = [];
  GradingMode _mode = GradingMode.ez;

  Subject? get _subject {
    for (final s in _subjects) {
      if (s.id == _subjectId) return s;
    }
    return null;
  }

  // ใช้ didChangeDependencies แทน initState เพราะต้องอ่าน StudyScope จาก context
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = StudyScope.of(context);
    if (repo != _repo) {
      _repo = repo;
      _reload();
    }
  }

  /// โหลดข้อมูลใหม่ทั้งหน้า (เรียกหลังทุกการเปลี่ยนแปลง)
  Future<void> _reload() async {
    final repo = _repo!;
    final subjects = await repo.subjects();
    final selected = subjects.any((s) => s.id == _subjectId)
        ? _subjectId
        : (subjects.isEmpty ? null : subjects.first.id);
    final mode = await repo.gradingMode();
    final chapters =
        selected == null ? <ChapterWithTopics>[] : await repo.chapters(selected);
    if (!mounted) return; // ผู้ใช้ปิดหน้าไปแล้วระหว่างรอ → ไม่ต้องวาด
    setState(() {
      _subjects = subjects;
      _subjectId = selected;
      _chapters = chapters;
      _mode = mode;
      _loading = false;
    });
  }

  Future<void> _addSubject() async {
    final name = await askText(context,
        title: 'เพิ่มวิชา', label: 'ชื่อวิชา', hint: 'เช่น DataCOM');
    if (name == null || !mounted) return;
    final importance = await askImportance(context, current: 2);
    if (importance == null) return; // ยกเลิกตอนเลือกความสำคัญ = ไม่เพิ่มวิชา
    final id = await _repo!.addSubject(name, importance: importance);
    _subjectId = id;
    await _reload();
  }

  Future<void> _renameSubject(Subject subject) async {
    final name = await askText(context,
        title: 'เปลี่ยนชื่อวิชา',
        label: 'ชื่อวิชา',
        initial: subject.name,
        confirmLabel: 'บันทึก');
    if (name == null) return;
    await _repo!.renameSubject(subject.id, name);
    await _reload();
  }

  Future<void> _changeImportance(Subject subject) async {
    final importance = await askImportance(context, current: subject.importance);
    if (importance == null) return;
    await _repo!.setSubjectImportance(subject.id, importance);
    await _reload();
  }

  Future<void> _deleteSubject(Subject subject) async {
    if (!await confirmDelete(context, subject.name)) return;
    await _repo!.deleteSubject(subject.id);
    _subjectId = null; // ให้ _reload เลือกวิชาแรกที่เหลือแทน
    await _reload();
  }

  Future<void> _renameChapter(Chapter chapter) async {
    final name = await askText(context,
        title: 'เปลี่ยนชื่อบท',
        label: 'ชื่อบท',
        initial: chapter.name,
        confirmLabel: 'บันทึก');
    if (name == null) return;
    await _repo!.renameChapter(chapter.id, name);
    await _reload();
  }

  Future<void> _addChapter() async {
    final name = await askText(context,
        title: 'เพิ่มบท',
        label: 'ชื่อบท',
        hint: 'เช่น บท ${_chapters.length + 1} · ...');
    if (name == null) return;
    await _repo!.addChapter(_subjectId!, name);
    await _reload();
  }

  Future<void> _addSubtopic(Chapter chapter) async {
    final name = await askText(context,
        title: 'เพิ่มหัวข้อย่อย', label: 'ชื่อหัวข้อย่อย', hint: chapter.name);
    if (name == null) return;
    await _repo!.addSubtopic(chapter.id, name);
    await _reload();
  }

  Future<void> _deleteChapter(Chapter chapter) async {
    if (!await confirmDelete(context, chapter.name)) return;
    await _repo!.deleteChapter(chapter.id);
    await _reload();
  }

  Future<void> _openSubtopic(Subtopic topic) async {
    final edit = await showSubtopicDialog(context, topic);
    if (edit == null || !mounted) return;
    final repo = _repo!;

    if (edit.delete) {
      if (!await confirmDelete(context, topic.name)) return;
      await repo.deleteSubtopic(topic.id);
    } else if (edit.history) {
      await showScoreHistory(context, repo, topic);
    } else if (edit.rename) {
      final name = await askText(context,
          title: 'เปลี่ยนชื่อหัวข้อย่อย',
          label: 'ชื่อหัวข้อย่อย',
          initial: topic.name,
          confirmLabel: 'บันทึก');
      if (name == null) return;
      await repo.renameSubtopic(topic.id, name);
    } else {
      if (edit.examFlag != topic.examFlag) {
        await repo.setExamFlag(topic.id, edit.examFlag);
      }
      if (edit.score != null) {
        await repo.addAssessment(topic.id, edit.score!);
        if (_mode == GradingMode.advanced) await _applyAdvancedRules(topic.id);
      }
    }
    await _reload();
  }

  /// [Advanced] หลังบันทึกคะแนน: เช็ก 2 เหตุการณ์ที่ค่าเฉลี่ยรวมหลอกตา
  /// 1) เคยตก → เขียว 2 รอบติด  2) เคยเขียว → ตก 2 รอบติด
  /// ทำตามค่าตั้งค่า หรือถามผู้ใช้ (พร้อมติ๊ก "ไม่ต้องถามอีก")
  Future<void> _applyAdvancedRules(int subtopicId) async {
    final repo = _repo!;
    Subtopic? topic;
    for (final ch in await repo.chapters(_subjectId!)) {
      for (final t in ch.subtopics) {
        if (t.id == subtopicId) topic = t;
      }
    }
    if (topic == null) return;

    final RuleText rule;
    if (needsGreenDecision(topic)) {
      rule = greenRule;
    } else if (needsRedDecision(topic)) {
      rule = redRule;
    } else {
      return;
    }

    final saved = rule.choiceFrom(await repo.getSetting(rule.key));
    RuleAnswer answer;
    if (saved == RuleChoice.ask) {
      if (!mounted) return;
      final decision = rule == greenRule
          ? await askGreenTwice(context, topic)
          : await askRedTwice(context, topic);
      if (decision == null) return; // ปิดกล่องเฉย ๆ = ยังไม่ตัดสินใจ
      answer = decision.answer;
      if (decision.remember) {
        await repo.setSetting(
          rule.key,
          (answer == RuleAnswer.recent ? RuleChoice.recent : RuleChoice.average)
              .name,
        );
      }
    } else {
      answer =
          saved == RuleChoice.recent ? RuleAnswer.recent : RuleAnswer.average;
    }

    switch (answer) {
      case RuleAnswer.recent:
        // เริ่มนับใหม่ตั้งแต่รอบแรกของ 2 รอบล่าสุด (ก่อนหน้านั้นเป็นโมฆะ)
        await repo.resetHistoryFrom(
            topic.id, topic.scores[topic.scores.length - 2].at);
      case RuleAnswer.average:
        break; // ไม่ต้องทำอะไร
      case RuleAnswer.wrongScore:
        if (mounted) await showScoreHistory(context, repo, topic);
    }
  }

  Future<void> _openSettings() => showStudySettings(context, _repo!);

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    final subject = _subject;
    final allTopics = [for (final ch in _chapters) ...ch.subtopics];
    final review = reviewOrder(allTopics, mode: _mode);

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
      children: [
        Text('Study Tree', style: TextStyle(fontSize: 13, color: c.muted)),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: Text(
                subject?.name ?? 'ยังไม่มีวิชา',
                style: TextStyle(
                    fontSize: 28, fontWeight: FontWeight.w600, color: c.text),
              ),
            ),
            if (subject != null)
              PopupMenuButton<String>(
                tooltip: 'ตัวเลือกวิชา',
                onSelected: (v) {
                  switch (v) {
                    case 'rename':
                      _renameSubject(subject);
                    case 'importance':
                      _changeImportance(subject);
                    default:
                      _deleteSubject(subject);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'rename', child: Text('เปลี่ยนชื่อวิชา')),
                  PopupMenuItem(value: 'importance', child: Text('เปลี่ยนความสำคัญ')),
                  PopupMenuItem(value: 'delete', child: Text('ลบวิชา')),
                ],
              ),
          ],
        ),
        const SizedBox(height: 12),

        // แถบเลือกวิชา + ปุ่มเพิ่มวิชา (Wrap = ล้นแล้วขึ้นบรรทัดใหม่เอง)
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final s in _subjects)
              ChoiceChip(
                label: Text(s.name),
                selected: s.id == _subjectId,
                onSelected: (_) {
                  _subjectId = s.id;
                  _reload();
                },
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('เพิ่มวิชา'),
              onPressed: _addSubject,
            ),
          ],
        ),

        if (subject != null) ...[
          const SizedBox(height: 12),
          _Pill(
            text: 'ความสำคัญ: ${subject.importanceLabel} · '
                '${subject.sessionsPerWeek} รอบ/สัปดาห์',
            bg: c.navBg,
            fg: c.navText,
          ),
          const SizedBox(height: 16),
          const _Legend(),
          const SizedBox(height: 12),
          // สวิตช์โหมด EZ / Advanced (จำไว้ในฐานข้อมูล ทุกวิชาใช้ร่วมกัน)
          Row(
            children: [
              SegmentedButton<GradingMode>(
              segments: const [
                ButtonSegment(value: GradingMode.ez, label: Text('EZ')),
                ButtonSegment(
                    value: GradingMode.advanced, label: Text('Advanced')),
              ],
              selected: {_mode},
              showSelectedIcon: false,
              onSelectionChanged: (selected) async {
                await _repo!.setGradingMode(selected.first);
                await _reload();
              },
              ),
              if (_mode == GradingMode.advanced)
                IconButton(
                  tooltip: 'ตั้งค่าโหมด Advanced',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: _openSettings,
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _mode == GradingMode.ez
                ? 'EZ: สีและ % = คะแนนล่าสุด'
                : 'Advanced: สีและ % = ค่าเฉลี่ยทุกรอบ · เคยตกต้องเขียว 2 รอบติดถึงผ่าน',
            style: TextStyle(fontSize: 12, color: c.muted),
          ),
          const SizedBox(height: 16),
          for (final ch in _chapters) ...[
            _ChapterCard(
              data: ch,
              onAddSubtopic: () => _addSubtopic(ch.chapter),
              onRename: () => _renameChapter(ch.chapter),
              onDelete: () => _deleteChapter(ch.chapter),
              onOpenSubtopic: _openSubtopic,
              mode: _mode,
            ),
            const SizedBox(height: 12),
          ],
          OutlinedButton.icon(
            onPressed: _addChapter,
            icon: const Icon(Icons.add),
            label: const Text('เพิ่มบท'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: c.text,
              side: BorderSide(color: c.line2),
            ),
          ),
          if (review.isNotEmpty) ...[
            const SizedBox(height: 16),
            _ReviewBox(
              topics: review,
              chapterNames: {
                for (final ch in _chapters) ch.chapter.id: ch.chapter.name,
              },
            ),
          ],
        ],
      ],
    );
  }
}

/// การ์ดของ 1 บท: หัวบท + หัวข้อย่อยทุกข้อ
class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    required this.data,
    required this.onAddSubtopic,
    required this.onRename,
    required this.onDelete,
    required this.onOpenSubtopic,
    required this.mode,
  });

  final ChapterWithTopics data;
  final GradingMode mode;
  final VoidCallback onAddSubtopic;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final ValueChanged<Subtopic> onOpenSubtopic;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final topics = data.subtopics;
    final assessed = topics.where((t) => t.latestScore != null).length;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 4, 8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(data.chapter.name,
                          style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                      Text(
                        topics.isEmpty
                            ? 'ยังไม่มีหัวข้อย่อย'
                            : 'ประเมินแล้ว $assessed/${topics.length} หัวข้อ',
                        style: TextStyle(fontSize: 13, color: c.muted),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'ตัวเลือกบท',
                  onSelected: (v) {
                    switch (v) {
                      case 'add':
                        onAddSubtopic();
                      case 'rename':
                        onRename();
                      default:
                        onDelete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'add', child: Text('เพิ่มหัวข้อย่อย')),
                    PopupMenuItem(value: 'rename', child: Text('เปลี่ยนชื่อบท')),
                    PopupMenuItem(value: 'delete', child: Text('ลบบทนี้')),
                  ],
                ),
              ],
            ),
          ),
          for (final t in topics) ...[
            Divider(height: 1, color: c.line),
            _SubtopicRow(topic: t, mode: mode, onTap: () => onOpenSubtopic(t)),
          ],
        ],
      ),
    );
  }
}

/// แถวหัวข้อย่อย: ชื่อ + ป้าย + แถบคะแนน + %
class _SubtopicRow extends StatelessWidget {
  const _SubtopicRow({
    required this.topic,
    required this.mode,
    required this.onTap,
  });

  final Subtopic topic;
  final GradingMode mode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final score = shownScore(topic, mode); // EZ = ล่าสุด · Advanced = เฉลี่ย
    final color = switch (masteryOf(score)) {
      MasteryLevel.good => c.good,
      MasteryLevel.warn => c.warn,
      MasteryLevel.bad => c.bad,
      MasteryLevel.none => c.line2,
    };
    // จอแคบ (มือถือ / หน้าต่างเล็ก) → แถบคะแนนสั้นลง ชื่อหัวข้อจะได้ไม่โดนบีบ
    final barWidth = MediaQuery.sizeOf(context).width < 600 ? 64.0 : 160.0;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(topic.name, style: TextStyle(fontSize: 15, color: c.text)),
                  if (topic.examFlag)
                    _Tag(text: 'ธง', border: c.flag, fg: c.flagText),
                  if (showRecheck(topic, mode))
                    _Tag(text: 'เช็กซ้ำ', bg: c.amberBg, fg: c.amberText),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: barWidth,
              height: 8,
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: (score ?? 0) / 100,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                score == null ? '—' : '$score%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 14, color: score == null ? c.muted : c.text),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// กล่อง "ต้องทวนก่อนสอบ": รายการหัวข้อแยกบรรทัด เรียงจากเร่งสุด (ข้อ 1) ลงไป
/// โชว์แค่ชื่อหัวข้อ + อยู่บทไหน ไม่โชว์คะแนน (คะแนนดูได้ในการ์ดบทด้านบน)
class _ReviewBox extends StatelessWidget {
  const _ReviewBox({required this.topics, required this.chapterNames});

  final List<Subtopic> topics;
  final Map<int, String> chapterNames; // chapterId → ชื่อบท

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      decoration: BoxDecoration(
        color: c.amberBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ต้องทวนก่อนสอบ · ${topics.length} หัวข้อ',
            style: TextStyle(fontWeight: FontWeight.w600, color: c.amberText),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < topics.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 24,
                    child: Text('${i + 1}.',
                        style: TextStyle(color: c.amberText)),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(topics[i].name,
                            style: TextStyle(fontSize: 15, color: c.text)),
                        Text(
                          chapterNames[topics[i].chapterId] ?? '',
                          style: TextStyle(fontSize: 12, color: c.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// คำอธิบายสี
class _Legend extends StatelessWidget {
  const _Legend();

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    Widget dot(Color color, String label) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(3)),
            ),
            const SizedBox(width: 6),
            Text(label, style: TextStyle(fontSize: 13, color: c.muted)),
          ],
        );

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: [
        dot(c.good, 'ดี >80%'),
        dot(c.warn, 'พอได้ 60–80%'),
        dot(c.bad, 'ยังไม่ได้ <60%'),
        dot(c.line2, 'ยังไม่ประเมิน'),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.bg, required this.fg});

  final String text;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 13, color: fg)),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.fg, this.bg, this.border});

  final String text;
  final Color fg;
  final Color? bg;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
        border: border == null ? null : Border.all(color: border!),
      ),
      child: Text(text, style: TextStyle(fontSize: 12, color: fg)),
    );
  }
}
