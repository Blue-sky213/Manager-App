/// กฎพิเศษของโหมด Advanced: เหตุการณ์ที่ "ค่าเฉลี่ยรวม" หลอกตา แล้วต้องถามผู้ใช้
///
/// ทุกเหตุการณ์มี 3 ทางเลือกในหน้าตั้งค่า: ถามทุกครั้ง / ทางเลือก A อัตโนมัติ / ทางเลือก B อัตโนมัติ
/// กล่องถามมีติ๊ก "ไม่ต้องถามอีก" → จำคำตอบล่าสุด แก้ได้ที่หน้าตั้งค่า
library;

import 'package:flutter/material.dart';

import '../data/study_models.dart';
import '../theme/noir_colors.dart';
import '../widgets/mini_form.dart';

/// เหตุการณ์ 1: เคยตก (<60) → เขียว (>80) 2 รอบติด แต่ค่าเฉลี่ยยังไม่เขียว
const String greenRuleKey = 'green_twice_rule';

/// เหตุการณ์ 2: เคยเขียว (>80) → ตก (<60) 2 รอบติด
const String redRuleKey = 'red_twice_rule';

/// คำตอบที่ตั้งไว้: ถาม / ใช้แค่ 2 รอบล่าสุด (ก่อนหน้าเป็นโมฆะ) / ใช้ค่าเฉลี่ยทุกรอบ
enum RuleChoice {
  ask,
  recent,
  average;

  static RuleChoice parse(String? value) => RuleChoice.values
      .firstWhere((r) => r.name == value, orElse: () => RuleChoice.ask);
}

/// ข้อความของแต่ละเหตุการณ์ (ใช้ทั้งกล่องถามและหน้าตั้งค่า)
class RuleText {
  const RuleText({
    required this.key,
    required this.event,
    required this.recentLabel,
    required this.recentDetail,
    required this.averageLabel,
    required this.averageDetail,
    this.allowAverage = true,
  });

  final String key;
  final String event;
  final String recentLabel;
  final String recentDetail;
  final String averageLabel;
  final String averageDetail;

  /// false = ไม่มีทางเลือก "ใช้ค่าเฉลี่ยต่อ" (โหมด Advanced ต้องโหดและตรงความจริง)
  final bool allowAverage;

  /// ตีความค่าที่บันทึกไว้: ถ้าห้ามใช้ค่าเฉลี่ย แต่บันทึกไว้เป็น average (ค่าเก่า) → กลับไปถาม
  RuleChoice choiceFrom(String? saved) {
    final c = RuleChoice.parse(saved);
    return (!allowAverage && c == RuleChoice.average) ? RuleChoice.ask : c;
  }
}

const greenRule = RuleText(
  key: greenRuleKey,
  event: 'เคยตก แล้วได้เขียว 2 รอบติด แต่ค่าเฉลี่ยยังไม่ถึงเขียว',
  recentLabel: 'นับเป็นเขียว',
  recentDetail: 'คะแนนก่อน 2 รอบล่าสุดเป็นโมฆะ ป้ายเช็กซ้ำหาย',
  averageLabel: 'ใช้ค่าเฉลี่ยต่อ',
  averageDetail: 'สีตามค่าเฉลี่ยทุกรอบ ยังอยู่ในกล่องทวน',
);

const redRule = RuleText(
  key: redRuleKey,
  event: 'เคยได้เขียว แล้วตกต่ำกว่า 60 สองรอบติด',
  recentLabel: 'ถูกแล้ว → นับจาก 2 รอบล่าสุด',
  recentDetail: 'คะแนนก่อน 2 รอบล่าสุดเป็นโมฆะ เห็นระดับจริงตอนนี้',
  averageLabel: 'ใช้ค่าเฉลี่ยต่อ',
  averageDetail: 'ไม่อนุญาต: คะแนนเขียวเก่าจะหลอกให้ดูดีเกินจริง',
  allowAverage: false, // ตก 2 รอบติด = ต้องยอมรับความจริง ไม่ให้ค่าเฉลี่ยเก่าช่วย
);

/// ผลจากกล่องถาม
enum RuleAnswer { recent, average, wrongScore }

class RuleDecision {
  const RuleDecision(this.answer, {required this.remember});

  final RuleAnswer answer;
  final bool remember;
}

/// กล่องถาม: เขียว 2 รอบติดแล้ว นับเป็นเขียวเลยไหม?
Future<RuleDecision?> askGreenTwice(BuildContext context, Subtopic t) {
  final lastTwo = t.scores.sublist(t.scores.length - 2).map((s) => '${s.score}%');
  return showMiniForm<RuleDecision>(
    context,
    (_) => _RuleDialog(
      title: 'เขียว 2 รอบติดแล้ว',
      message: '"${t.name}" ได้ ${lastTwo.join(' และ ')} สองรอบล่าสุด '
          'แต่ค่าเฉลี่ยทุกรอบยังเป็น ${t.averageScore}%\n\n'
          'นับเป็นเขียวเลยไหม? (คะแนนก่อน 2 รอบนี้จะเป็นโมฆะ ไม่นำมาเฉลี่ย)',
      text: greenRule,
      offerWrongScore: false,
    ),
  );
}

/// กล่องถาม: เคยเขียว แต่ตก 2 รอบติด ใส่คะแนนถูกไหม?
Future<RuleDecision?> askRedTwice(BuildContext context, Subtopic t) {
  final s = t.scores;
  final lastTwo = s.sublist(s.length - 2).map((p) => '${p.score}%');
  final best = s.sublist(0, s.length - 2).map((p) => p.score).reduce(
        (a, b) => a > b ? a : b,
      );
  return showMiniForm<RuleDecision>(
    context,
    (_) => _RuleDialog(
      title: 'คะแนนตก 2 รอบติด',
      message: '"${t.name}" เคยได้ $best% แต่ 2 รอบล่าสุดได้ ${lastTwo.join(' และ ')}\n\n'
          'ใส่คะแนนถูกจริงไหม? ถ้าถูก จะคิดจาก 2 รอบล่าสุดเท่านั้น '
          '(โหมด Advanced ไม่ใช้ค่าเฉลี่ยรวม ${t.averageScore}% เพราะดูดีเกินจริง)',
      text: redRule,
      offerWrongScore: true,
    ),
  );
}

class _RuleDialog extends StatefulWidget {
  const _RuleDialog({
    required this.title,
    required this.message,
    required this.text,
    required this.offerWrongScore,
  });

  final String title;
  final String message;
  final RuleText text;
  final bool offerWrongScore;

  @override
  State<_RuleDialog> createState() => _RuleDialogState();
}

class _RuleDialogState extends State<_RuleDialog> {
  bool _remember = false;

  void _answer(RuleAnswer a) => Navigator.pop(
        context,
        // "ใส่ผิด" ไม่ใช่คำตอบที่ควรจำ → ไม่บันทึกค่าตั้งค่า
        RuleDecision(a, remember: _remember && a != RuleAnswer.wrongScore),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final options = [
      MiniRow(label: widget.text.recentLabel, onTap: () => _answer(RuleAnswer.recent)),
      if (widget.text.allowAverage)
        MiniRow(label: widget.text.averageLabel, onTap: () => _answer(RuleAnswer.average)),
      if (widget.offerWrongScore)
        MiniRow(label: 'ใส่ผิด → แก้คะแนน', onTap: () => _answer(RuleAnswer.wrongScore)),
    ];
    return MiniForm(title: widget.title, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(widget.message, style: TextStyle(color: c.text)),
      ),
      MiniSwitchRow(
        label: 'ไม่ต้องถามอีก',
        detail: 'เปลี่ยนได้ที่หน้าตั้งค่า',
        value: _remember,
        onChanged: (v) => setState(() => _remember = v),
      ),
      for (var i = 0; i < options.length; i++)
        i == options.length - 1
            ? MiniRow(label: options[i].label, onTap: options[i].onTap, last: true)
            : options[i],
    ]);
  }
}

/// ข้อความสั้นของตัวเลือกที่ตั้งไว้ (แสดงทางขวาของแถวในหน้าตั้งค่า)
String ruleChoiceLabel(RuleText r, RuleChoice c) => switch (c) {
      RuleChoice.ask => 'ถามทุกครั้ง',
      RuleChoice.recent => r.allowAverage ? r.recentLabel : 'นับ 2 รอบล่าสุด',
      RuleChoice.average => r.averageLabel,
    };

/// แผ่นเลือกกฎ 1 ข้อ (เปิดจากหน้าตั้งค่า) · คืนตัวเลือกใหม่ หรือ null ถ้าปิด
Future<RuleChoice?> pickRuleChoice(BuildContext context, RuleText r, RuleChoice current) =>
    showMiniChoice<RuleChoice>(context, title: 'เมื่อ${r.event}', current: current, items: [
      miniChoice(RuleChoice.ask, 'ถามทุกครั้ง',
          detail: r.allowAverage ? 'เด้งกล่องถาม' : 'ถามว่าใส่คะแนนถูกไหม (แนะนำ)'),
      miniChoice(RuleChoice.recent, '${ruleChoiceLabel(r, RuleChoice.recent)}อัตโนมัติ', detail: r.recentDetail),
      miniChoice(RuleChoice.average, '${r.averageLabel}${r.allowAverage ? 'อัตโนมัติ' : ''}',
          detail: r.averageDetail, enabled: r.allowAverage),
    ]);
