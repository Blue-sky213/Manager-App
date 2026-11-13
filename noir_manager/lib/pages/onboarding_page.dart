import 'package:flutter/material.dart';

import '../calendar/calendar_models.dart';
import '../calendar/calendar_repository.dart';
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import 'settings_page.dart' show appModeKey, appModes;

/// setting keys ที่ได้จากคำถามแรกเข้า (ใช้ต่อในข้อความสะท้อนผลรายปี)
const onboardedKey = 'onboarded';
const selfGoalKey = 'self_goal'; // "อยากเปลี่ยนอะไรในตัวเอง" คำของผู้ใช้เอง
const selfGoalDateKey = 'self_goal_date';
const gpaTargetKey = 'gpa_target';

/// คำถามแรกเข้า 4 ข้อ → เติมค่าตั้งต้นให้เอง ลดการตั้งค่าเยอะ ๆ ตอนเริ่ม · ข้ามได้ทุกข้อ
class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key, required this.onDone, this.onTheme});

  final VoidCallback onDone;

  /// ลองธีมสดระหว่างตอบ (แอปจำเลย)
  final ValueChanged<String>? onTheme;

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  int _step = 0;
  String _mode = 'study';
  TimeOfDay _wake = const TimeOfDay(hour: 7, minute: 0);
  TimeOfDay _bed = const TimeOfDay(hour: 23, minute: 30);
  final _goal = TextEditingController();
  double _gpa = 3.0;

  static const _steps = 5;
  String _bright = 'dark';
  String _color = '';

  void _applyTheme() => widget.onTheme?.call(themeIdFor(_color, _bright));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _prefill();
  }

  bool _prefilled = false;

  /// แตะเปลี่ยนเวลาเองเท่านั้นถึงเขียนทับ (กันเวลานอนรายวันที่ตั้งไว้แล้วหาย)
  bool _timeTouched = false;

  /// ผู้ใช้เดิม (เคยตั้งเวลานอนแล้ว) → เริ่มจากค่าเดิม ไม่ทับของเก่าด้วยค่าตั้งต้น
  Future<void> _prefill() async {
    if (_prefilled) return;
    _prefilled = true;
    final base = await CalendarScope.of(context).lifeBase();
    if (!mounted || base.isEmpty) return;
    final d = base.first;
    setState(() {
      _wake = TimeOfDay(hour: d.wakeMinute ~/ 60, minute: d.wakeMinute % 60);
      _bed = TimeOfDay(hour: (d.bedMinute ~/ 60) % 24, minute: d.bedMinute % 60);
    });
  }

  Future<void> _finish() async {
    final study = StudyScope.of(context);
    final cal = CalendarScope.of(context);
    await study.setSetting(appModeKey, _mode);
    if (_timeTouched || (await cal.lifeBase()).isEmpty) {
      await cal.setLifeBase([
        for (var wd = 1; wd <= 7; wd++)
          LifeBaseDay(weekday: wd, bedMinute: _bed.hour * 60 + _bed.minute, wakeMinute: _wake.hour * 60 + _wake.minute),
      ]);
    }
    final goal = _goal.text.trim();
    if (goal.isNotEmpty) {
      await study.setSetting(selfGoalKey, goal);
      await study.setSetting(selfGoalDateKey, DateTime.now().toIso8601String().substring(0, 10));
    }
    if (_mode != 'work') await study.setSetting(gpaTargetKey, _gpa.toStringAsFixed(2));
    await study.setSetting(onboardedKey, '1');
    widget.onDone();
  }

  Future<void> _skipAll() async {
    await StudyScope.of(context).setSetting(onboardedKey, '1');
    widget.onDone();
  }

  Future<void> _pick(bool wake) async {
    // 24 ชม. เสมอ: กันเลือก "12:00" (เที่ยง) ทั้งที่ตั้งใจเที่ยงคืน
    final t = await showTimePicker(
      context: context,
      initialTime: wake ? _wake : _bed,
      builder: (ctx, child) =>
          MediaQuery(data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true), child: child!),
    );
    if (t == null) return;
    _timeTouched = true;
    setState(() {
      if (wake) {
        _wake = t;
      } else {
        _bed = t;
      }
    });
  }

  String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final title = TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: c.text, height: 1.3);
    final sub = TextStyle(fontSize: 15, color: c.muted);

    final body = switch (_step) {
      0 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ยินดีต้อนรับ · ใช้แอปนี้ทำอะไรเป็นหลัก?', style: title),
          const SizedBox(height: 6),
          Text('แอปจะเปิดเครื่องมือให้ตรงกับที่ใช้ เปลี่ยนทีหลังได้ในตั้งค่า', style: sub),
          const SizedBox(height: 18),
          for (final (id, name, hint) in appModes)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Choice(selected: _mode == id, title: name, hint: hint, onTap: () => setState(() => _mode = id)),
            ),
        ]),
      1 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('เวลาตั้งใจทำอะไรสักอย่าง คุณชอบบรรยากาศแบบไหน?', style: title),
          const SizedBox(height: 6),
          Text('แอปจะเปลี่ยนหน้าตาให้ดูทันที ลองเลือกจนรู้สึกสบายใจ', style: sub),
          const SizedBox(height: 18),
          for (final (id, name, hint) in const [
            ('light', 'ห้องสว่าง โปร่ง', 'เหมือนนั่งริมหน้าต่างตอนเช้า'),
            ('dark', 'ห้องมืด เงียบ', 'มีแค่ไฟโต๊ะ ไม่มีอะไรรบกวน'),
            (autoThemeId, 'ตามเวลาจริง', 'กลางวันสว่าง กลางคืนมืด'),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _Choice(
                selected: _bright == id,
                title: name,
                hint: hint,
                onTap: () {
                  setState(() => _bright = id);
                  _applyTheme();
                },
              ),
            ),
          if (_bright != autoThemeId) ...[
            const SizedBox(height: 8),
            Text('สีไหนทำให้คุณรู้สึกอยากเริ่มทำ?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final (id, name, mood) in themeColorMoods)
                ChoiceChip(
                  label: Text('$name · $mood'),
                  selected: _color == id,
                  onSelected: (_) {
                    setState(() => _color = id);
                    _applyTheme();
                  },
                ),
            ]),
          ],
        ]),
      2 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('ปกติตื่นกี่โมง นอนกี่โมง?', style: title),
          const SizedBox(height: 6),
          Text('ใช้คิดชั่วโมงนอน และไม่วางงานทับเวลานอน · ตั้งแยกรายวันได้ทีหลัง', style: sub),
          const SizedBox(height: 18),
          Wrap(spacing: 12, runSpacing: 12, children: [
            OutlinedButton.icon(
                onPressed: () => _pick(true), icon: const Icon(Icons.wb_sunny_outlined), label: Text('ตื่น ${_hm(_wake)}')),
            OutlinedButton.icon(
                onPressed: () => _pick(false), icon: const Icon(Icons.bedtime_outlined), label: Text('นอน ${_hm(_bed)}')),
          ]),
        ]),
      3 => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('อยากเปลี่ยนอะไรในตัวเองบ้าง?', style: title),
          const SizedBox(height: 6),
          Text('เขียนด้วยคำของตัวเอง ไม่มีถูกผิด · ปลายปีแอปจะเอาคำนี้มาเทียบกับสิ่งที่ทำได้จริง', style: sub),
          const SizedBox(height: 18),
          TextField(
            controller: _goal,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: 'เช่น อยากเป็นคนขยันขึ้น ทำตามแผนได้จริง และมั่นใจในตัวเองมากกว่านี้',
            ),
          ),
        ]),
      _ => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(_mode == 'work' ? 'พร้อมแล้ว' : 'เทอมนี้ตั้งเป้าเกรดเฉลี่ยไว้เท่าไหร่?', style: title),
          const SizedBox(height: 6),
          Text(
            _mode == 'work'
                ? 'โหมดทำงานเต็มรูปแบบ (โปรเจกต์ · รายรับรายจ่าย) มาในรอบ v2 · ตอนนี้ใช้ปฏิทินและวันนี้ได้เลย'
                : 'ใช้วัดว่าทำได้ตามเป้ากี่ % · แก้ได้ทีหลัง',
            style: sub,
          ),
          if (_mode != 'work') ...[
            const SizedBox(height: 18),
            Text('GPA ${_gpa.toStringAsFixed(2)}',
                style: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, color: c.accent)),
            Slider(
              value: _gpa,
              min: 2.0,
              max: 4.0,
              divisions: 8,
              label: _gpa.toStringAsFixed(2),
              onChanged: (v) => setState(() => _gpa = v),
            ),
          ],
        ]),
    };

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
              children: [
                Row(children: [
                  for (var i = 0; i < _steps; i++)
                    Expanded(
                      child: Container(
                        height: 4,
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(
                          color: i <= _step ? c.accent : c.surface2,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                ]),
                const SizedBox(height: 28),
                body,
                const SizedBox(height: 28),
                Row(children: [
                  TextButton(onPressed: _skipAll, child: const Text('ข้ามทั้งหมด')),
                  const Spacer(),
                  if (_step > 0)
                    TextButton(onPressed: () => setState(() => _step--), child: const Text('ย้อน')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _step < _steps - 1 ? () => setState(() => _step++) : _finish,
                    child: Text(_step < _steps - 1 ? 'ถัดไป' : 'เริ่มใช้งาน'),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({required this.selected, required this.title, required this.hint, required this.onTap});

  final bool selected;
  final String title;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return Material(
      color: selected ? c.navBg : c.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: selected ? c.accent : c.line2, width: selected ? 2 : 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: c.text)),
                Text(hint, style: TextStyle(fontSize: 13, color: c.muted)),
              ]),
            ),
            Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off, color: selected ? c.accent : c.muted),
          ]),
        ),
      ),
    );
  }
}
