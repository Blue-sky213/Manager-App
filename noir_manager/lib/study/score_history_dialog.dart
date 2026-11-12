import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../data/study_repository.dart';
import '../theme/noir_colors.dart';
import '../utils/thai_date.dart';
import '../widgets/mini_form.dart';
import 'mastery.dart';

/// ตารางประวัติคะแนนของ 1 หัวข้อ: ดู · แก้ · ลบ · ยกเลิกโมฆะ
/// ทุกการเปลี่ยนแปลงต้องยืนยัน พร้อมโชว์ผล "ก่อน → หลัง"
Future<void> showScoreHistory(
  BuildContext context,
  StudyRepository repo,
  Subtopic topic,
) {
  return showMiniForm<void>(context, (_) => _ScoreHistoryDialog(repo: repo, topic: topic));
}

class _ScoreHistoryDialog extends StatefulWidget {
  const _ScoreHistoryDialog({required this.repo, required this.topic});

  final StudyRepository repo;
  final Subtopic topic;

  @override
  State<_ScoreHistoryDialog> createState() => _ScoreHistoryDialogState();
}

class _ScoreHistoryDialogState extends State<_ScoreHistoryDialog> {
  List<ScoreRecord>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final rows = await widget.repo.scoreHistory(widget.topic.id);
    if (mounted) setState(() => _rows = rows);
  }

  /// สรุปผล (ล่าสุด + เฉลี่ย) จากรอบที่ไม่เป็นโมฆะ
  String _summary(List<ScoreRecord> rows) {
    final active = rows.where((r) => !r.voided).map((r) => r.score).toList();
    if (active.isEmpty) return 'ยังไม่ประเมิน';
    final avg = averageOf(active)!;
    return 'ล่าสุด ${active.last}% · เฉลี่ย $avg% (${levelLabel(masteryOf(avg))})';
  }

  /// กล่องยืนยัน: โชว์สิ่งที่จะเปลี่ยน + ผลก่อน → หลัง
  Future<bool> _confirm(String what, List<ScoreRecord> after) async {
    final before = _summary(_rows!);
    final afterText = _summary(after);
    final ok = await showMiniForm<bool>(
      context,
      (ctx) => MiniForm(
        title: 'ยืนยันการแก้คะแนน',
        primaryLabel: 'ยืนยัน',
        onPrimary: () => Navigator.pop(ctx, true),
        onSecondary: () => Navigator.pop(ctx, false),
        children: [
          Text(what, style: TextStyle(color: ctx.noir.text, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          MiniRow(label: 'ก่อน', valueText: before),
          MiniRow(label: 'หลัง', valueText: afterText, last: true),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _edit(int index) async {
    final row = _rows![index];
    final newScore = await _askScore(row.score);
    if (newScore == null || newScore == row.score || !mounted) return;
    final after = [
      for (final r in _rows!)
        r.id == row.id
            ? ScoreRecord(id: r.id, score: newScore, at: r.at, voided: r.voided)
            : r,
    ];
    if (!await _confirm(
        'แก้รอบที่ ${index + 1}: ${row.score}% → $newScore%', after)) {
      return;
    }
    await widget.repo.updateAssessment(row.id, newScore);
    await _load();
  }

  Future<void> _delete(int index) async {
    final row = _rows![index];
    final after = [for (final r in _rows!) if (r.id != row.id) r];
    if (!await _confirm('ลบรอบที่ ${index + 1} (${row.score}%)', after)) return;
    await widget.repo.deleteAssessment(row.id);
    await _load();
  }

  Future<void> _undoVoid() async {
    final after = [
      for (final r in _rows!)
        ScoreRecord(id: r.id, score: r.score, at: r.at, voided: false),
    ];
    if (!await _confirm('ยกเลิกโมฆะ: นำคะแนนทุกรอบกลับมาคิด', after)) return;
    await widget.repo.undoReset(widget.topic.id);
    await _load();
  }

  Future<int?> _askScore(int current) async {
    final controller = TextEditingController(text: '$current');
    String? error;
    return showMiniForm<int>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void save() {
            final v = int.tryParse(controller.text.trim());
            if (v == null || v < 0 || v > 100) {
              setLocal(() => error = 'ใส่ตัวเลข 0–100');
              return;
            }
            Navigator.pop(ctx, v);
          }

          return MiniForm(
            title: 'แก้คะแนน',
            primaryLabel: 'ต่อไป',
            onPrimary: save,
            children: [
              MiniBigField(
                controller: controller,
                hint: '0–100',
                suffix: '%',
                fontSize: 28,
                keyboardType: TextInputType.number,
                onSubmitted: (_) => save(),
              ),
              if (error != null) Text(error!, style: TextStyle(fontSize: 12, color: ctx.noir.bad)),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final rows = _rows;
    final hasVoided = rows?.any((r) => r.voided) ?? false;

    return MiniForm(
      title: 'ประวัติคะแนน · ${widget.topic.name}',
      menu: [if (hasVoided) miniMenu('ยกเลิกโมฆะ', _undoVoid)],
      children: [
        if (rows == null)
          const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()))
        else if (rows.isEmpty)
          Text('ยังไม่มีคะแนน', style: TextStyle(color: c.muted))
        else ...[
          Text(_summary(rows), style: TextStyle(color: c.muted, fontSize: 13)),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++)
            _HistoryRow(index: i, record: rows[i], onEdit: () => _edit(i), onDelete: () => _delete(i)),
          if (hasVoided) ...[
            const SizedBox(height: 8),
            Text('รอบสีจาง = โมฆะ (ไม่นำมาคิด แต่ยังเก็บไว้) · ยกเลิกโมฆะที่เมนู ⋮',
                style: TextStyle(fontSize: 12, color: c.muted)),
          ],
        ],
      ],
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.index,
    required this.record,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final ScoreRecord record;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final fg = record.voided ? c.muted : c.text;
    final at = record.at;
    final time =
        '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';

    return Opacity(
      opacity: record.voided ? 0.55 : 1,
      child: Row(
        children: [
          SizedBox(
              width: 28, child: Text('${index + 1}.', style: TextStyle(color: fg))),
          Expanded(
            child: Text('${thaiShortDate(at)} $time',
                style: TextStyle(fontSize: 13, color: fg)),
          ),
          SizedBox(
            width: 52,
            child: Text('${record.score}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontWeight: FontWeight.w600, color: fg)),
          ),
          if (record.voided)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Text('โมฆะ', style: TextStyle(fontSize: 12, color: fg)),
            ),
          IconButton(
            tooltip: 'แก้คะแนน',
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: onEdit,
          ),
          IconButton(
            tooltip: 'ลบรอบนี้',
            icon: const Icon(Icons.delete_outline, size: 20),
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }
}
