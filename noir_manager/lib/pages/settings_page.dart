import 'package:flutter/material.dart';

import '../calendar/calendar_repository.dart' show CalendarScope;
import '../calendar/lock_flow.dart' show lockSettingKey;
import '../study/mastery.dart' show GradingMode;
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../widgets/mini_dropdown.dart';

/// โหมดแอป: เรียน / ทำงาน / ทั้งคู่ (เก็บใน setting key = app_mode)
const appModeKey = 'app_mode';
const appModes = [
  ('study', 'เรียน', 'แผน 4 ปี · ติว · เกรด'),
  ('work', 'ทำงาน', 'โปรเจกต์ · รายรับรายจ่าย · เวลาเผื่อ (เร็ว ๆ นี้)'),
  ('both', 'ทั้งคู่', 'เรียนไปด้วย ทำงานไปด้วย'),
];

/// หน้า "ตั้งค่า": ธีม · โหมดแอป · การให้คะแนน · สีแผน 4 ปี
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.themeId, this.onTheme});

  final String themeId;
  final ValueChanged<String>? onTheme;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  late String _theme = widget.themeId;
  String _mode = 'study';
  GradingMode _grading = GradingMode.ez;
  String _mapColor = 'default';
  bool _lock = true;
  bool _loaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) _load();
  }

  Future<void> _load() async {
    final repo = StudyScope.of(context);
    final cal = CalendarScope.of(context);
    final mode = await repo.getSetting(appModeKey);
    final grading = await repo.gradingMode();
    final map = await repo.getSetting('map_color');
    final lock = await cal.getSetting(lockSettingKey);
    if (!mounted) return;
    setState(() {
      _mode = mode ?? 'study';
      _grading = grading;
      _mapColor = map ?? 'default';
      _lock = lock != 'off';
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final repo = StudyScope.of(context);

    Widget section(String title, List<Widget> children) => Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: c.text)),
              const SizedBox(height: 10),
              ...children,
            ]),
          ),
        );

    Widget row(String label, Widget control, {String? hint}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 6,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(label, style: TextStyle(color: c.text)),
                if (hint != null) Text(hint, style: TextStyle(fontSize: 12, color: c.muted)),
              ]),
              control,
            ],
          ),
        );

    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า')),
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                // จอกว้างมากไม่ยืดเต็มจอ → อ่านง่าย
                constraints: const BoxConstraints(maxWidth: 760),
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  children: [
                    section('หน้าตา', [
                      Text('ธีม', style: TextStyle(color: c.muted, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final t in themeChoices)
                          _ThemeSwatch(
                            choice: t,
                            selected: t.id == _theme,
                            onTap: () {
                              setState(() => _theme = t.id);
                              widget.onTheme?.call(t.id);
                            },
                          ),
                      ]),
                      const SizedBox(height: 12),
                      row(
                        'สีกล่องในแผน 4 ปี',
                        MiniDropdown<String>(
                          value: _mapColor,
                          items: const [('default', 'สีเดียวกันหมด'), ('subject', 'ตามสีวิชา')],
                          onChanged: (v) {
                            setState(() => _mapColor = v);
                            repo.setSetting('map_color', v);
                          },
                        ),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    section('โหมดแอป', [
                      RadioGroup<String>(
                        groupValue: _mode,
                        onChanged: (v) {
                          if (v == null) return;
                          setState(() => _mode = v);
                          repo.setSetting(appModeKey, v);
                        },
                        child: Column(children: [
                          for (final (id, name, hint) in appModes)
                            RadioListTile<String>(
                              contentPadding: EdgeInsets.zero,
                              value: id,
                              title: Text(name),
                              subtitle: Text(hint),
                            ),
                        ]),
                      ),
                      if (_mode != 'study')
                        Text('โหมดทำงานเต็มรูปแบบมาในรอบ v2 · ตอนนี้ใช้ปฏิทินและวันนี้ได้ตามปกติ',
                            style: TextStyle(fontSize: 13, color: c.warn)),
                    ]),
                    const SizedBox(height: 14),
                    section('การให้คะแนนความเข้าใจ', [
                      row(
                        'โหมด',
                        SegmentedButton<GradingMode>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: GradingMode.ez, label: Text('EZ')),
                            ButtonSegment(value: GradingMode.advanced, label: Text('Advanced')),
                          ],
                          selected: {_grading},
                          onSelectionChanged: (v) {
                            setState(() => _grading = v.first);
                            repo.setGradingMode(v.first);
                          },
                        ),
                        hint: _grading == GradingMode.ez ? 'สีตามคะแนนล่าสุด' : 'เฉลี่ยทุกครั้ง + กฎเช็กซ้ำ',
                      ),
                    ]),
                    const SizedBox(height: 14),
                    section('ล็อก', [
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _lock,
                        onChanged: (v) {
                          setState(() => _lock = v);
                          CalendarScope.of(context).setSetting(lockSettingKey, v ? 'on' : 'off');
                        },
                        title: const Text('🔒 ล็อกงานที่เริ่มไปแล้ว'),
                        subtitle: const Text('กรอกผลได้ตามปกติ · เลื่อน / ยกเลิก / แก้ / ลบ ต้องยืนยันก่อน · ตั้งคำมั่นได้ที่คลิกขวา → คำมั่น'),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    section('เกี่ยวกับ', [
                      Text('Noir Manager v1 · ฐานข้อมูล v15', style: TextStyle(color: c.muted)),
                    ]),
                  ],
                ),
              ),
            ),
    );
  }
}

/// ปุ่มเลือกธีม: วงสีตัวอย่าง (พื้น + สีเน้น) + ชื่อ
class _ThemeSwatch extends StatelessWidget {
  const _ThemeSwatch({required this.choice, required this.selected, required this.onTap});

  final ThemeChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final t = choice.colors;
    return Semantics(
      button: true,
      selected: selected,
      label: 'ธีม${choice.name}',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 104,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? c.accent : c.line2, width: selected ? 2 : 1),
          ),
          child: Column(children: [
            Container(
              height: 44,
              decoration: BoxDecoration(
                color: t.bg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: t.line),
              ),
              child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Container(width: 18, height: 18, decoration: BoxDecoration(color: t.navBg, shape: BoxShape.circle)),
                const SizedBox(width: 6),
                Container(width: 18, height: 18, decoration: BoxDecoration(color: t.accent, shape: BoxShape.circle)),
              ]),
            ),
            const SizedBox(height: 6),
            Text(choice.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}
