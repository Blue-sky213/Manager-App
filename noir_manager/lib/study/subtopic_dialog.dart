import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../theme/noir_colors.dart';
import '../widgets/mini_form.dart';

/// ผลลัพธ์จากกล่องหัวข้อย่อย
class SubtopicEdit {
  const SubtopicEdit({
    this.score,
    required this.examFlag,
    this.delete = false,
    this.rename = false,
    this.history = false,
  });

  final int? score; // null = ไม่ได้กรอกคะแนนใหม่
  final bool examFlag;
  final bool delete; // กดปุ่มลบหัวข้อ
  final bool rename; // กดปุ่มเปลี่ยนชื่อ
  final bool history; // กดดูประวัติคะแนน
}

/// กล่องจัดการหัวข้อย่อย: บันทึกคะแนน · ติด/เอาธงออก · เปลี่ยนชื่อ · ลบ
Future<SubtopicEdit?> showSubtopicDialog(BuildContext context, Subtopic topic) {
  return showMiniForm<SubtopicEdit>(context, (_) => _SubtopicDialog(topic: topic));
}

class _SubtopicDialog extends StatefulWidget {
  const _SubtopicDialog({required this.topic});

  final Subtopic topic;

  @override
  State<_SubtopicDialog> createState() => _SubtopicDialogState();
}

class _SubtopicDialogState extends State<_SubtopicDialog> {
  final _scoreController = TextEditingController();
  late bool _flag = widget.topic.examFlag;
  String? _error;

  @override
  void dispose() {
    // dispose ได้ที่นี่ เพราะ State นี้ถูกทิ้งหลังแอนิเมชันปิดจบแล้ว
    _scoreController.dispose();
    super.dispose();
  }

  void _save() {
    final text = _scoreController.text.trim();
    int? score;
    if (text.isNotEmpty) {
      score = int.tryParse(text);
      if (score == null || score < 0 || score > 100) {
        setState(() => _error = 'ใส่ตัวเลข 0–100');
        return;
      }
    }
    Navigator.pop(context, SubtopicEdit(score: score, examFlag: _flag));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final latest = widget.topic.latestScore;
    // คะแนนตัวใหญ่ · ลบ / เปลี่ยนชื่อ อยู่ในเมนู ⋮ · ปุ่มล่างเหลือ 2
    return MiniForm(
      title: widget.topic.name,
      menu: [
        miniMenu('เปลี่ยนชื่อ', () => Navigator.pop(context, SubtopicEdit(examFlag: _flag, rename: true))),
        miniMenu('ลบหัวข้อ', () => Navigator.pop(context, SubtopicEdit(examFlag: _flag, delete: true)), danger: true),
      ],
      primaryLabel: 'บันทึก',
      onPrimary: _save,
      children: [
        const MiniLabel('คะแนนรอบนี้'),
        MiniBigField(
          key: const Key('score-field'),
          controller: _scoreController,
          hint: '0–100',
          suffix: '%',
          fontSize: 28,
          keyboardType: TextInputType.number,
          onSubmitted: (_) => _save(),
        ),
        if (_error != null)
          Padding(padding: const EdgeInsets.only(top: 4), child: Text(_error!, style: TextStyle(fontSize: 12, color: c.bad))),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
            Text(
              latest == null
                  ? 'ยังไม่เคยประเมิน · เว้นว่างถ้าแค่จะติด/เอาดาวออก'
                  : 'ล่าสุด $latest% · เฉลี่ย ${widget.topic.averageScore}% (${widget.topic.scores.length} รอบ)',
              style: TextStyle(fontSize: 12, color: c.muted),
            ),
            if (latest != null)
              TextButton(
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: () => Navigator.pop(context, SubtopicEdit(examFlag: _flag, history: true)),
                child: const Text('ประวัติ · แก้คะแนน ›'),
              ),
          ]),
        ),
        MiniSwitchRow(
          icon: _flag ? Icons.star : Icons.star_outline,
          label: 'อาจออกสอบ',
          value: _flag,
          onChanged: (v) => setState(() => _flag = v),
          last: true,
        ),
      ],
    );
  }
}
