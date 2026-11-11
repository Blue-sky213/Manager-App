import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../calendar/calendar_repository.dart' show CalendarScope;
import '../data/app_database.dart' show appSchemaVersion;
import '../data/backup.dart';
import '../calendar/lock_flow.dart' show lockSettingKey, refreshLockState;
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
  const SettingsPage({super.key, required this.themeId, this.onTheme, this.backup});

  final String themeId;
  final BackupService? backup;
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

  void _pickTheme(String id) {
    setState(() => _theme = id);
    widget.onTheme?.call(id);
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
                      Text('โหมด', style: TextStyle(color: c.muted, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final id in const ['dark', 'light', autoThemeId])
                          _ThemeSwatch(
                            choice: id == autoThemeId ? null : themeChoiceOf(id),
                            name: id == autoThemeId ? 'ตามเวลา' : null,
                            selected: id == _theme,
                            onTap: () => _pickTheme(id),
                          ),
                      ]),
                      if (_theme == autoThemeId)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text('06:00–17:59 สว่าง · 18:00–05:59 มืด', style: TextStyle(fontSize: 12, color: c.muted)),
                        ),
                      const SizedBox(height: 14),
                      Text('สีพาสเทล · สว่าง', style: TextStyle(color: c.muted, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final t in themeChoices.where((t) => !t.dark && t.id != 'light'))
                          _ThemeSwatch(choice: t, selected: t.id == _theme, onTap: () => _pickTheme(t.id)),
                      ]),
                      const SizedBox(height: 14),
                      Text('สีพาสเทล · มืด', style: TextStyle(color: c.muted, fontSize: 13)),
                      const SizedBox(height: 8),
                      Wrap(spacing: 10, runSpacing: 10, children: [
                        for (final t in themeChoices.where((t) => t.dark && t.id != 'dark'))
                          _ThemeSwatch(choice: t, selected: t.id == _theme, onTap: () => _pickTheme(t.id)),
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
                          final cal = CalendarScope.of(context);
                          cal.setSetting(lockSettingKey, v ? 'on' : 'off').then((_) => refreshLockState(cal));
                        },
                        title: const Text('🔒 ล็อกงานที่เริ่มไปแล้ว'),
                        subtitle: const Text('กรอกผลได้ตามปกติ · เลื่อน / ยกเลิก / แก้ / ลบ ต้องยืนยันก่อน · ตั้งคำมั่นได้ที่คลิกขวา → คำมั่น'),
                      ),
                    ]),
                    const SizedBox(height: 14),
                    section('สำรองข้อมูล', [_BackupSection(backup: widget.backup)]),
                    const SizedBox(height: 14),
                    section('เกี่ยวกับ', [
                      Text('Noir Manager v1 · ฐานข้อมูล v$appSchemaVersion', style: TextStyle(color: c.muted)),
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
  const _ThemeSwatch({required this.choice, this.name, required this.selected, required this.onTap});

  /// null = "ตามเวลา" (วาดครึ่งสว่างครึ่งมืด)
  final ThemeChoice? choice;
  final String? name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final auto = choice == null;
    final t = choice?.colors ?? NoirColors.light;
    final label = name ?? choice!.name;
    return Semantics(
      button: true,
      selected: selected,
      label: 'ธีม$label',
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
            if (auto)
              Container(
                height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: c.line2),
                  gradient: LinearGradient(colors: [
                    NoirColors.light.bg,
                    NoirColors.light.bg,
                    NoirColors.dark.bg,
                    NoirColors.dark.bg,
                  ], stops: const [0, 0.5, 0.5, 1]),
                ),
                child: const Center(child: Icon(Icons.schedule, size: 20, color: Color(0xFF8A93A3))),
              )
            else
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
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: c.text, fontWeight: selected ? FontWeight.w600 : FontWeight.w400)),
          ]),
        ),
      ),
    );
  }
}

/// สำรองตอนนี้ · รายการสำรอง 30 วัน · กู้คืน (มีผลเมื่อเปิดแอปใหม่)
class _BackupSection extends StatefulWidget {
  const _BackupSection({required this.backup});
  final BackupService? backup;

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  List<File> _files = const [];
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final files = await widget.backup?.list() ?? const <File>[];
    if (mounted) setState(() => _files = files);
  }

  void _toast(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _backupNow() async {
    setState(() => _busy = true);
    try {
      await widget.backup!.backupNow();
      if (mounted) _toast('สำรองแล้ว');
    } catch (e) {
      if (mounted) _toast('สำรองไม่สำเร็จ: $e');
    }
    if (mounted) setState(() => _busy = false);
    await _load();
  }

  Future<void> _restore(File f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('กู้คืนข้อมูล?'),
        content: Text('ข้อมูลจะกลับไปเป็นของไฟล์ ${p.basename(f.path)}\n'
            'แอปจะสำรองข้อมูลตอนนี้ไว้ก่อน (เผื่อเปลี่ยนใจ) แล้วกู้คืนเมื่อเปิดแอปครั้งถัดไป'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('กู้คืนเมื่อเปิดใหม่')),
        ],
      ),
    );
    if (ok != true) return;
    await widget.backup!.scheduleRestore(f);
    if (mounted) _toast('ปิดแล้วเปิดแอปใหม่ เพื่อกู้คืน');
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    if (widget.backup == null) {
      return Text('สำรองข้อมูลใช้ได้ในแอปจริงเท่านั้น', style: TextStyle(color: c.muted));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('สำรองอัตโนมัติวันละครั้งตอนเปิดแอป · เก็บ 30 วัน', style: TextStyle(fontSize: 13, color: c.muted)),
      const SizedBox(height: 8),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton.icon(
          onPressed: _busy ? null : _backupNow,
          icon: const Icon(Icons.backup_outlined),
          label: const Text('สำรองตอนนี้'),
        ),
      ),
      const SizedBox(height: 8),
      for (final f in _files.take(7))
        ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.history),
          title: Text(p.basename(f.path)),
          trailing: TextButton(onPressed: () => _restore(f), child: const Text('กู้คืน…')),
        ),
      if (_files.length > 7) Text('และอีก ${_files.length - 7} ไฟล์', style: TextStyle(fontSize: 12, color: c.muted)),
    ]);
  }
}
