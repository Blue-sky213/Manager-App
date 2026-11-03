import 'package:flutter/material.dart';

import '../data/study_models.dart';

/// ชื่อค่าตั้งค่าในตาราง setting
const String greenRuleKey = 'green_twice_rule';

/// เมื่อ "เคยตก → เขียว 2 รอบติด แต่ค่าเฉลี่ยยังไม่ถึงเขียว" จะทำอะไร
enum GreenRule {
  ask, // ถามทุกครั้ง (ค่าเริ่มต้น)
  green, // นับเป็นเขียวเลย: คะแนนก่อน 2 รอบนั้นเป็นโมฆะ
  average; // ใช้ค่าเฉลี่ยต่อ

  static GreenRule parse(String? value) =>
      GreenRule.values.firstWhere((r) => r.name == value,
          orElse: () => GreenRule.ask);

  String get label => switch (this) {
        GreenRule.ask => 'ถามทุกครั้ง',
        GreenRule.green => 'นับเป็นเขียวอัตโนมัติ',
        GreenRule.average => 'ใช้ค่าเฉลี่ยต่ออัตโนมัติ',
      };

  String get detail => switch (this) {
        GreenRule.ask => 'เด้งกล่องถามเมื่อเกิดเหตุการณ์',
        GreenRule.green => 'คะแนนก่อน 2 รอบล่าสุดเป็นโมฆะ ป้ายเช็กซ้ำหาย',
        GreenRule.average => 'สีตามค่าเฉลี่ยทุกรอบ ยังอยู่ในกล่องทวน',
      };
}

/// คำตอบจากกล่องถาม
class GreenAnswer {
  const GreenAnswer({required this.makeGreen, required this.remember});

  final bool makeGreen;
  final bool remember; // ติ๊ก "ไม่ต้องถามอีก"
}

/// กล่องถาม: เขียว 2 รอบติดแล้ว นับเป็นเขียวเลยไหม?
Future<GreenAnswer?> askGreenTwice(BuildContext context, Subtopic topic) {
  return showDialog<GreenAnswer>(
    context: context,
    builder: (_) => _GreenTwiceDialog(topic: topic),
  );
}

class _GreenTwiceDialog extends StatefulWidget {
  const _GreenTwiceDialog({required this.topic});

  final Subtopic topic;

  @override
  State<_GreenTwiceDialog> createState() => _GreenTwiceDialogState();
}

class _GreenTwiceDialogState extends State<_GreenTwiceDialog> {
  bool _remember = false;

  void _answer(bool makeGreen) => Navigator.pop(
      context, GreenAnswer(makeGreen: makeGreen, remember: _remember));

  @override
  Widget build(BuildContext context) {
    final t = widget.topic;
    final lastTwo = t.scores.sublist(t.scores.length - 2).map((s) => '${s.score}%');

    return AlertDialog(
      title: const Text('เขียว 2 รอบติดแล้ว'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('"${t.name}" ได้ ${lastTwo.join(' และ ')} สองรอบล่าสุด '
                'แต่ค่าเฉลี่ยทุกรอบยังเป็น ${t.averageScore}%'),
            const SizedBox(height: 12),
            const Text('นับเป็นเขียวเลยไหม? '
                '(คะแนนก่อน 2 รอบนี้จะเป็นโมฆะ ไม่นำมาเฉลี่ย)'),
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _remember,
              onChanged: (v) => setState(() => _remember = v ?? false),
              title: const Text('ไม่ต้องถามอีก'),
              subtitle: const Text('ใช้คำตอบนี้ทุกครั้ง · เปลี่ยนได้ที่ปุ่ม ⚙ ตั้งค่า'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => _answer(false),
          child: const Text('ใช้ค่าเฉลี่ยต่อ'),
        ),
        FilledButton(
          onPressed: () => _answer(true),
          child: const Text('นับเป็นเขียว'),
        ),
      ],
    );
  }
}

/// กล่องตั้งค่า (ชั่วคราว จนกว่าจะมีหน้า Settings เต็ม)
Future<GreenRule?> showStudySettings(BuildContext context, GreenRule current) {
  return showDialog<GreenRule>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('ตั้งค่าโหมด Advanced'),
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text('เมื่อเคยตก แล้วได้เขียว 2 รอบติด '
              'แต่ค่าเฉลี่ยยังไม่ถึงเขียว:'),
        ),
        for (final rule in GreenRule.values)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, rule),
            child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(rule == current
                  ? Icons.radio_button_checked
                  : Icons.radio_button_unchecked),
              title: Text(rule.label),
              subtitle: Text(rule.detail),
            ),
          ),
      ],
    ),
  );
}
