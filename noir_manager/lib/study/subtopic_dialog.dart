import 'package:flutter/material.dart';

import '../data/study_models.dart';

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
  return showDialog<SubtopicEdit>(
    context: context,
    builder: (_) => _SubtopicDialog(topic: topic),
  );
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
    final latest = widget.topic.latestScore;

    return AlertDialog(
      title: Text(widget.topic.name),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(latest == null
                ? 'ยังไม่เคยประเมิน'
                : 'คะแนนล่าสุด $latest% · เฉลี่ย ${widget.topic.averageScore}% '
                    '(${widget.topic.scores.length} รอบ)'),
            if (latest != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(padding: EdgeInsets.zero),
                  onPressed: () => Navigator.pop(
                    context,
                    SubtopicEdit(examFlag: _flag, history: true),
                  ),
                  icon: const Icon(Icons.history, size: 18),
                  label: const Text('ประวัติคะแนน · แก้คะแนนที่ใส่ผิด'),
                ),
              ),
            const SizedBox(height: 16),
            TextField(
              key: const Key('score-field'),
              controller: _scoreController,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'คะแนนรอบนี้ (%)',
                hintText: '0–100 · เว้นว่างถ้าแค่จะแก้ธง',
                errorText: _error,
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('ธง: อาจออกสอบ'),
              value: _flag,
              onChanged: (v) => setState(() => _flag = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            SubtopicEdit(examFlag: _flag, delete: true),
          ),
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          child: const Text('ลบหัวข้อ'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            SubtopicEdit(examFlag: _flag, rename: true),
          ),
          child: const Text('เปลี่ยนชื่อ'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(onPressed: _save, child: const Text('บันทึก')),
      ],
    );
  }
}
