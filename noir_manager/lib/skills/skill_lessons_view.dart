/// หน้าสกิล › บทเรียน (รอบ 13): บท → หัวข้อ · ให้คะแนนเข้าใจเหมือนหน้าการเรียน · ▶ เปิดคลิปที่ดูเรียน
/// "ล็อก" แค่บอกว่าบทก่อนยังไม่ผ่าน ไม่บล็อก (อิสระ ไม่บล็อก)
library;

import 'package:flutter/material.dart';

import '../theme/noir_colors.dart';
import '../utils/open_link.dart';
import '../utils/thai_date.dart';
import '../widgets/dialogs.dart';
import '../widgets/mini_form.dart';
import '../widgets/toast.dart';
import 'skill_models.dart';
import 'skill_repository.dart';
import 'skill_tree.dart';

/// สีตามระดับ (เดียวกับหน้าการเรียน)
Color topicColor(NoirColors c, int? score) => switch (topicLevel(score)) {
      TopicLevel.good => c.good,
      TopicLevel.ok => c.warn,
      TopicLevel.bad => c.bad,
      TopicLevel.none => c.line2,
    };

class SkillLessons extends StatefulWidget {
  const SkillLessons({super.key, required this.repo, required this.skill});
  final SkillRepository repo;
  final Skill skill;

  @override
  State<SkillLessons> createState() => _SkillLessonsState();
}

class _SkillLessonsState extends State<SkillLessons> {
  List<SkillNode> _nodes = const [];
  List<SkillTopic> _topics = const [];
  final _open = <int>{};
  bool _first = true;

  @override
  void initState() {
    super.initState();
    widget.repo.addListener(_load);
    _load();
  }

  @override
  void didUpdateWidget(SkillLessons old) {
    super.didUpdateWidget(old);
    if (old.repo != widget.repo) {
      old.repo.removeListener(_load);
      widget.repo.addListener(_load);
    }
    if (old.skill.id != widget.skill.id) {
      _first = true;
      _open.clear();
      _load();
    }
  }

  @override
  void dispose() {
    widget.repo.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final nodes = [for (final n in await widget.repo.nodes()) if (n.skillId == widget.skill.id) n]
      ..sort((a, b) => a.sort != b.sort ? a.sort - b.sort : a.id - b.id);
    final ids = {for (final n in nodes) n.id};
    final topics = [for (final t in await widget.repo.topics()) if (ids.contains(t.nodeId)) t];
    if (!mounted) return;
    setState(() {
      _nodes = nodes;
      _topics = topics;
      // เปิดครั้งแรก: กางบทที่กำลังเรียน
      if (_first) {
        _first = false;
        final cur = _current;
        if (cur != null) _open.add(cur.id);
      }
    });
  }

  List<SkillTopic> _of(int nodeId) => _topics.where((t) => t.nodeId == nodeId).toList();

  /// บทแรกที่ยังไม่ผ่าน
  SkillNode? get _current => _nodes.where((n) => !nodePassed(n, _topics)).firstOrNull;

  // ---------- แก้ไข ----------

  Future<void> _editChapter({SkillNode? node}) async {
    final name = TextEditingController(text: node?.name ?? '');
    final url = TextEditingController(text: node?.url ?? '');
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => MiniForm(
        title: node == null ? 'เพิ่มบท' : 'แก้บท',
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, name.text.trim().isNotEmpty),
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('chapter-name'), controller: name, hint: 'ชื่อบท เช่น บท 3 Color'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('chapter-url'),
            controller: url,
            decoration: const InputDecoration(labelText: 'ลิงก์คลิปของทั้งบท (ไม่ใส่ก็ได้)', isDense: true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final u = url.text.trim();
    if (node == null) {
      final id = await widget.repo.saveNode(SkillNode(
          skillId: widget.skill.id,
          name: name.text.trim(),
          sort: _nodes.isEmpty ? 0 : _nodes.last.sort + 1,
          url: u.isEmpty ? null : u));
      if (mounted) setState(() => _open.add(id));
    } else {
      await widget.repo.saveNode(node.copyWith(name: name.text.trim(), url: u.isEmpty ? null : u, clearUrl: u.isEmpty));
    }
  }

  Future<void> _addTopic(SkillNode node) async {
    final name = TextEditingController();
    final url = TextEditingController();
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => MiniForm(
        title: 'เพิ่มหัวข้อ · ${node.name}',
        primaryLabel: 'เพิ่ม',
        onPrimary: () => Navigator.pop(ctx, name.text.trim().isNotEmpty),
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          MiniBigField(key: const Key('topic-name'), controller: name, hint: 'ชื่อหัวข้อ'),
          const SizedBox(height: 8),
          TextField(
            key: const Key('topic-new-url'),
            controller: url,
            decoration: const InputDecoration(labelText: 'ลิงก์คลิป (ไม่ใส่ก็ได้)', isDense: true),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final mine = _of(node.id);
    final u = url.text.trim();
    await widget.repo.saveTopic(SkillTopic(
        nodeId: node.id, name: name.text.trim(), sort: mine.isEmpty ? 0 : mine.last.sort + 1, url: u.isEmpty ? null : u));
    if (mounted) setState(() => _open.add(node.id));
  }

  Future<void> _chapterMenu(SkillNode n, Offset at) async {
    final v = await showContextMenuAt<String>(context, at, [
      ctxItem('edit', Icons.edit_outlined, 'แก้ชื่อ / ลิงก์'),
      ctxItem('topic', Icons.add, 'เพิ่มหัวข้อ'),
      ctxItem('delete', Icons.delete_outline, 'ลบบท', danger: true),
    ]);
    if (!mounted || v == null) return;
    switch (v) {
      case 'edit':
        await _editChapter(node: n);
      case 'topic':
        await _addTopic(n);
      case 'delete':
        final count = _of(n.id).length;
        if (await confirmMini(context,
            title: 'ลบ "${n.name}"?', message: 'หัวข้อ $count ข้อ + คะแนนในบทนี้หายด้วย', okLabel: 'ลบ', danger: true)) {
          await widget.repo.deleteNode(n.id);
        }
    }
  }

  // ---------- หน้าตา ----------

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final scored = _topics.where((t) => t.score != null).length;
    final green = _topics.where((t) => t.green).length;
    final review = _topics.where((t) => t.score != null && !t.green).toList()..sort((a, b) => a.score!.compareTo(b.score!));
    final cur = _current;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.only(top: 20, bottom: 6),
        child: Row(children: [
          Expanded(child: Text('บทเรียน', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: c.text))),
          TextButton.icon(
            key: const Key('lesson-add-chapter'),
            onPressed: () => _editChapter(),
            icon: const Icon(Icons.add, size: 18),
            label: const Text('บท'),
          ),
        ]),
      ),
      if (_nodes.isEmpty)
        Text('ยังไม่มีบท · กด "+ บท" แล้วใส่หัวข้อ + ลิงก์คลิปที่ดูเรียน · ให้คะแนนความเข้าใจแต่ละหัวข้อ (🟢 ≥ 80)',
            style: TextStyle(fontSize: 12, color: c.muted))
      else ...[
        Wrap(spacing: 8, runSpacing: 8, children: [
          _kpi(c, 'ความคืบหน้า', _topics.isEmpty ? '–' : '${(green * 100 / _topics.length).round()}%', c.good, key: 'lesson-kpi-progress'),
          _kpi(c, 'ประเมินแล้ว', '$scored/${_topics.length}', c.text),
          _kpi(c, 'ต้องทวน', '${review.length}', review.isEmpty ? c.muted : c.warn),
          _kpi(c, 'บทตอนนี้', cur?.name ?? 'ผ่านครบ 🏆', c.accent, wide: true),
        ]),
        if (review.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('ต้องทวน', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final t in review.take(8))
              ActionChip(
                key: ValueKey('lesson-review-${t.id}'),
                visualDensity: VisualDensity.compact,
                avatar: CircleAvatar(radius: 5, backgroundColor: topicColor(c, t.score)),
                label: Text('${t.name} · ${t.score}', style: const TextStyle(fontSize: 12)),
                onPressed: () => topicForm(context, widget.repo, t),
              ),
          ]),
        ],
        const SizedBox(height: 10),
        for (final (i, n) in _nodes.indexed) _chapter(context, n, i),
      ],
    ]);
  }

  Widget _kpi(NoirColors c, String label, String value, Color color, {bool wide = false, String? key}) => Container(
        key: key == null ? null : Key(key),
        constraints: BoxConstraints(minWidth: 96, maxWidth: wide ? 320 : 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(color: c.surface2, borderRadius: BorderRadius.circular(10)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: TextStyle(fontSize: 11, color: c.muted)),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: wide ? 14 : 18, fontWeight: FontWeight.w600, color: color)),
        ]),
      );

  Widget _chapter(BuildContext context, SkillNode n, int i) {
    final c = context.noir;
    final mine = _of(n.id);
    final scored = mine.where((t) => t.score != null).length;
    final green = mine.where((t) => t.green).length;
    final state = nodeState(_nodes, i, topics: _topics);
    final (tag, tagColor) = switch (state) {
      TreeState.done => ('ผ่าน', c.good),
      TreeState.prog => ('กำลังเรียน', c.accent),
      TreeState.lock => ('บทก่อนยังไม่ผ่าน', c.muted),
      TreeState.open => ('ยังไม่เริ่ม', c.muted),
    };
    final open = _open.contains(n.id);
    return Card(
      key: ValueKey('lesson-ch-${n.id}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          key: ValueKey('lesson-ch-head-${n.id}'),
          onTap: () => setState(() => open ? _open.remove(n.id) : _open.add(n.id)),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
            child: Row(children: [
              Icon(open ? Icons.expand_more : Icons.chevron_right, color: c.muted),
              const SizedBox(width: 6),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(n.name, style: TextStyle(fontWeight: FontWeight.w600, color: c.text)),
                  const SizedBox(height: 2),
                  Text(
                    mine.isEmpty
                        ? (n.done ? 'ติ๊กผ่านแล้ว' : 'ยังไม่มีหัวข้อ')
                        : 'ประเมินแล้ว $scored/${mine.length} หัวข้อ · 🟢 $green',
                    style: TextStyle(fontSize: 12, color: c.muted),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  border: Border.all(color: tagColor.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(tag, style: TextStyle(fontSize: 11, color: tagColor)),
              ),
              if (isWebLink(n.url))
                IconButton(
                  key: ValueKey('lesson-ch-play-${n.id}'),
                  tooltip: 'เปิดคลิปของบท',
                  onPressed: () => openLink(context, n.url!),
                  icon: Icon(Icons.play_circle_outline, color: c.bad),
                ),
              Builder(
                builder: (bctx) => IconButton(
                  key: ValueKey('lesson-ch-menu-${n.id}'),
                  tooltip: 'เมนูบท',
                  onPressed: () {
                    final box = bctx.findRenderObject() as RenderBox;
                    _chapterMenu(n, box.localToGlobal(box.size.center(Offset.zero)));
                  },
                  icon: const Icon(Icons.more_vert, size: 20),
                ),
              ),
            ]),
          ),
        ),
        if (open) ...[
          Divider(height: 1, color: c.line),
          for (final t in mine) _topicRow(context, t),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: ValueKey('lesson-add-topic-${n.id}'),
              onPressed: () => _addTopic(n),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('หัวข้อ'),
            ),
          ),
        ],
      ]),
    );
  }

  Widget _topicRow(BuildContext context, SkillTopic t) {
    final c = context.noir;
    final col = topicColor(c, t.score);
    return InkWell(
      key: ValueKey('lesson-topic-${t.id}'),
      onTap: () => topicForm(context, widget.repo, t),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 4, 6),
        child: Row(children: [
          Expanded(child: Text(t.name, style: TextStyle(fontSize: 13, color: c.text))),
          const SizedBox(width: 8),
          SizedBox(
            width: 72,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(value: (t.score ?? 0) / 100, minHeight: 6, color: col, backgroundColor: c.surface2),
            ),
          ),
          SizedBox(
            width: 34,
            child: Text(t.score?.toString() ?? '–',
                textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: col)),
          ),
          SizedBox(
            width: 40,
            child: isWebLink(t.url)
                ? IconButton(
                    key: ValueKey('lesson-play-${t.id}'),
                    tooltip: 'เปิดคลิป',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => openLink(context, t.url!),
                    icon: Icon(Icons.play_arrow_rounded, color: c.bad),
                  )
                : null,
          ),
        ]),
      ),
    );
  }
}

/// ให้คะแนน / แก้หัวข้อ: ปุ่มเร็ว 🟢 90 · 🟡 70 · 🔴 40 หรือพิมพ์ 0–100 · ลิงก์ · โน้ต · ประวัติ
Future<void> topicForm(BuildContext context, SkillRepository repo, SkillTopic t) async {
  final score = TextEditingController();
  final name = TextEditingController(text: t.name);
  final url = TextEditingController(text: t.url ?? '');
  final note = TextEditingController(text: t.note ?? '');
  final v = await showMiniForm<String>(
    context,
    (ctx) => StatefulBuilder(builder: (ctx, setLocal) {
      final c = ctx.noir;
      Widget quick(int s, String label) => OutlinedButton(
            key: Key('topic-score-$s'),
            onPressed: () => setLocal(() => score.text = '$s'),
            style: OutlinedButton.styleFrom(
              foregroundColor: topicColor(c, s),
              side: BorderSide(color: score.text == '$s' ? topicColor(c, s) : c.line2, width: score.text == '$s' ? 2 : 1),
            ),
            child: Text(label),
          );
      return MiniForm(
        title: t.name,
        primaryLabel: 'บันทึก',
        onPrimary: () => Navigator.pop(ctx, 'save'),
        onSecondary: () => Navigator.pop(ctx),
        menu: [miniMenu('ลบหัวข้อ', () => Navigator.pop(ctx, 'delete'), danger: true)],
        children: [
          Text('เข้าใจแค่ไหน (ไม่ให้คะแนนรอบนี้ = เว้นว่าง)', style: TextStyle(fontSize: 12, color: c.muted)),
          const SizedBox(height: 6),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            quick(90, '🟢 เข้าใจ 90'),
            quick(70, '🟡 พอได้ 70'),
            quick(40, '🔴 ยัง 40'),
            MiniInlineField(
              key: const Key('topic-score'),
              controller: score,
              hint: '0–100',
              width: 80,
              keyboardType: TextInputType.number,
              onChanged: (_) => setLocal(() {}),
            ),
          ]),
          const SizedBox(height: 10),
          TextField(key: const Key('topic-edit-name'), controller: name, decoration: const InputDecoration(labelText: 'ชื่อหัวข้อ', isDense: true)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                  key: const Key('topic-url'), controller: url, decoration: const InputDecoration(labelText: 'ลิงก์คลิป', isDense: true)),
            ),
            IconButton(
              key: const Key('topic-open'),
              tooltip: 'เปิดคลิป',
              onPressed: isWebLink(url.text) ? () => openLink(ctx, url.text) : null,
              icon: Icon(Icons.play_arrow_rounded, color: c.bad),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            key: const Key('topic-note'),
            controller: note,
            minLines: 1,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'โน้ต (สรุปสั้น ๆ / จุดที่ยังงง)', isDense: true),
          ),
          if (t.scores.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text('ประวัติ', style: TextStyle(fontSize: 12, color: c.muted)),
            for (final p in t.scores.reversed.take(6))
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Row(children: [
                  Expanded(child: Text(thaiShortDate(p.at), style: TextStyle(fontSize: 12, color: c.muted))),
                  Text('${p.score}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: topicColor(c, p.score))),
                ]),
              ),
          ],
        ],
      );
    }),
  );
  if (v == 'delete') {
    if (context.mounted &&
        await confirmMini(context, title: 'ลบ "${t.name}"?', message: 'คะแนนของหัวข้อนี้หายด้วย', okLabel: 'ลบ', danger: true)) {
      await repo.deleteTopic(t.id);
    }
    return;
  }
  if (v != 'save') return;
  final u = url.text.trim(), nt = note.text.trim(), nm = name.text.trim();
  await repo.saveTopic(t.copyWith(
      name: nm.isEmpty ? null : nm, url: u.isEmpty ? null : u, clearUrl: u.isEmpty, note: nt.isEmpty ? null : nt, clearNote: nt.isEmpty));
  final s = int.tryParse(score.text.trim());
  if (s != null) {
    await repo.addTopicScore(t.id, s.clamp(0, 100));
    if (context.mounted) showToast(context, '${t.name}: $s ${topicLevel(s) == TopicLevel.good ? '🟢' : topicLevel(s) == TopicLevel.ok ? '🟡' : '🔴'}');
  }
}
