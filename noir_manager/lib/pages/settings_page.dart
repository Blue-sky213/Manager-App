import 'dart:io';

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../sync/account_section.dart';
import '../sync/cloud_sync.dart';
import '../sync/phone_sync.dart';
import '../sync/phone_sync_settings.dart';
import '../calendar/calendar_repository.dart' show CalendarScope;
import '../data/app_database.dart' show appSchemaVersion;
import '../data/backup.dart';
import '../calendar/sticker_ui.dart' show StickerSettings;
import '../calendar/lock_flow.dart' show lockSettingKey, refreshLockState;
import '../study/advanced_rules.dart' show greenRule, redRule, RuleChoice, ruleChoiceLabel, pickRuleChoice;
import '../study/class_log.dart' show askClassLogKey;
import '../study/mastery.dart' show GradingMode;
import '../study/tutor_plan.dart' show defaultTutorPass, tutorPassKey;
import '../data/study_scope.dart';
import '../theme/noir_colors.dart';
import '../data/demo_year.dart' show demoMode;
import '../shell/window_mode.dart';
import '../widgets/device_preview.dart';
import '../widgets/mini_dropdown.dart';
import '../calendar/category_ui.dart' show CategorySettings;
import '../calendar/day_cards.dart' show AutoStickerSettings;
import '../shell/app_nav.dart' show hiddenMenus, hiddenMenusKey;
import '../widgets/mini_form.dart';
import '../widgets/mini_segments.dart';
import '../widgets/toast.dart';
import 'fresh_start.dart';
import 'settings_layout.dart';
import 'test_checklist.dart';

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
  bool _askLog = true;
  int _pass = defaultTutorPass;
  final Map<String, RuleChoice> _rules = {};
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
    final askLog = await repo.getSetting(askClassLogKey);
    final pass = int.tryParse(await repo.getSetting(tutorPassKey) ?? '');
    final rules = {for (final r in [greenRule, redRule]) r.key: r.choiceFrom(await repo.getSetting(r.key))};
    if (!mounted) return;
    setState(() {
      _mode = mode ?? 'study';
      _grading = grading;
      _mapColor = map ?? 'default';
      _lock = lock != 'off';
      _askLog = askLog != 'off';
      _pass = pass ?? defaultTutorPass;
      _rules.addAll(rules);
      _loaded = true;
    });
  }

  void _pickTheme(String id) {
    setState(() => _theme = id);
    widget.onTheme?.call(id);
  }

  /// เพิ่มทุกครั้งที่ state เปลี่ยน → หน้าหมวดที่เปิดซ้อนอยู่ (มือถือ) วาดใหม่ตาม
  final _tick = ValueNotifier(0);

  /// หมวดที่เลือก (จอกว้าง) · คำค้นหา
  String _cat = 'display';
  String _query = '';

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _tick.value++;
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  /// ตั้งค่าแยกหมวดแบบโทรศัพท์ (รอบ 21) · แต่ละหมวด = หลายกล่อง
  List<SettingsCategory> _cats(BuildContext context) {
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

    final look = section('ธีมและสี', [
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
                    ]);
    final mode = section('โหมดการใช้งาน', [
                      MiniSegments<String>(
                        value: _mode,
                        items: [for (final (id, name, _) in appModes) (id, name)],
                        onChanged: (v) {
                          setState(() => _mode = v);
                          repo.setSetting(appModeKey, v);
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(appModes.firstWhere((m) => m.$1 == _mode).$3, style: TextStyle(fontSize: 12, color: c.muted)),
                      const SizedBox(height: 6),
                      // รอบ 8D: เมนู "งาน" ซ่อนได้ (คนที่ใช้แค่เรียนไม่ต้องเห็น)
                      ValueListenableBuilder(
                        valueListenable: hiddenMenus,
                        builder: (ctx, hidden, _) => Column(children: [
                          for (final (key, menu, icon, detail) in const [
                            ('menu-work', 'งาน', Icons.work_outline, 'โปรเจกต์ · งวด · ทีม'),
                            ('menu-money', 'เงิน', Icons.account_balance_wallet_outlined, 'รายรับ-จ่าย · ค่าบริการ · ลงทุน'),
                          ])
                            MiniSwitchRow(
                              key: Key(key),
                              icon: icon,
                              label: 'เมนู "$menu"',
                              detail: detail,
                              value: !hidden.contains(menu),
                              last: menu == 'เงิน',
                              onChanged: (v) {
                                final next = {...hidden};
                                v ? next.remove(menu) : next.add(menu);
                                hiddenMenus.value = next;
                                repo.setSetting(hiddenMenusKey, next.join(','));
                              },
                            ),
                        ]),
                      ),
                    ]);
    final grading = section('การให้คะแนนความเข้าใจ', [
                      MiniSegments<GradingMode>(
                        value: _grading,
                        items: const [(GradingMode.ez, 'EZ'), (GradingMode.advanced, 'Advanced')],
                        onChanged: (v) {
                          setState(() => _grading = v);
                          repo.setGradingMode(v);
                        },
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _grading == GradingMode.ez
                            ? 'EZ = สีตามคะแนนล่าสุด'
                            : 'Advanced = เฉลี่ยทุกรอบ · เคยตกต้องเขียว 2 รอบติดถึงผ่าน',
                        style: TextStyle(fontSize: 12, color: c.muted),
                      ),
                      if (_grading == GradingMode.advanced)
                        for (final (i, r) in [greenRule, redRule].indexed)
                          MiniRow(
                            key: Key('rule-${r.key}'),
                            label: i == 0 ? 'เคยตก → เขียว 2 รอบติด' : 'เคยเขียว → ตก 2 รอบติด',
                            valueText: ruleChoiceLabel(r, _rules[r.key] ?? RuleChoice.ask),
                            last: i == 1,
                            onTap: () async {
                              final v = await pickRuleChoice(context, r, _rules[r.key] ?? RuleChoice.ask);
                              if (v == null) return;
                              setState(() => _rules[r.key] = v);
                              await repo.setSetting(r.key, v.name);
                            },
                          ),
                    ]);
    final study = section('การเรียนและติว', [
                      MiniSwitchRow(
                        label: 'กด "ทำแล้ว" ที่คาบเรียน → บันทึกเรียนถึงไหน',
                        value: _askLog,
                        onChanged: (v) {
                          setState(() => _askLog = v);
                          repo.setSetting(askClassLogKey, v ? 'on' : 'off');
                        },
                      ),
                      const MiniLabel('ผ่าน · พักติวได้ เมื่อบทที่เรียนแล้วเฉลี่ยถึง'),
                      MiniSegments<int>(
                        value: _pass,
                        items: const [(70, '70%'), (80, '80%'), (90, '90%')],
                        onChanged: (v) {
                          setState(() => _pass = v);
                          repo.setSetting(tutorPassKey, '$v');
                        },
                      ),
                    ]);
    final lock = section('การล็อกงาน', [
                      MiniSwitchRow(
                        label: '🔒 ล็อกงานที่เริ่มไปแล้ว',
                        detail: 'เลื่อน / ยกเลิก / แก้ / ลบ ต้องยืนยัน',
                        value: _lock,
                        last: true,
                        onChanged: (v) {
                          setState(() => _lock = v);
                          final cal = CalendarScope.of(context);
                          cal.setSetting(lockSettingKey, v ? 'on' : 'off').then((_) => refreshLockState(cal));
                        },
                      ),
                    ]);
    final mood = section('สติกเกอร์อารมณ์', [const StickerSettings()]);
    final window = section('หน้าต่างโปรแกรม', [
                        ValueListenableBuilder(
                          valueListenable: fullscreen,
                          builder: (context, on, _) => MiniSwitchRow(
                            label: 'เต็มจอไร้ขอบ (F11)',
                            detail: 'Esc / F11 = กลับหน้าต่างปกติ',
                            value: on,
                            last: true,
                            onChanged: (v) {
                              setFullscreen(v);
                              repo.setSetting(fullscreenKey, v ? 'on' : 'off');
                            },
                          ),
                        ),
                      ]);
    final demo = section('ข้อมูลตัวอย่าง', [
                      ValueListenableBuilder(
                        valueListenable: demoMode,
                        builder: (context, on, _) => MiniSwitchRow(
                          label: 'ใช้ข้อมูลตัวอย่างทั้งหมด (1 ปี · ทุกเมนู)',
                          detail: 'อยู่ในหน่วยความจำ · ไม่แตะข้อมูลจริง · ปิด = หายทั้งชุด',
                          value: on,
                          onChanged: (v) => demoMode.value = v,
                        ),
                      ),
                      MiniRow(
                        key: const Key('open-checklist'),
                        icon: Icons.checklist,
                        label: 'เช็กลิสต์ทดสอบ (สร้าง · แก้ · ลบ · ขอบ ๆ)',
                        last: true,
                        onTap: () => Navigator.of(context)
                            .push(MaterialPageRoute<void>(builder: (_) => const TestChecklistPage())),
                      ),
                    ]);
    final preview = section('ทดลองหน้าจออุปกรณ์', [const _DevicePreviewSettings()]);
    final cats = section('หมวดงาน', [const CategorySettings()]);
    final autoSt = section('สติกเกอร์อัตโนมัติ', [const AutoStickerSettings()]);
    final backup = section('สำรองข้อมูล', [_BackupSection(backup: widget.backup)]);
    final account = section('บัญชีและการซิงก์', [AccountSection(service: CloudSyncService.instance)]);
    final phone = section('วิดเจ็ต iPhone (ผ่าน iCloud)', [PhoneSyncSection(service: PhoneSyncService.instance)]);
    final fresh = section('ล้างข้อมูลแล้วเริ่มใหม่', [FreshStartSection(backup: widget.backup)]);
    final about = section('เกี่ยวกับ', [
                      Text('Noir Manager v1 · ฐานข้อมูล v$appSchemaVersion', style: TextStyle(color: c.muted)),
                    ]);
    final desktop = const {TargetPlatform.windows, TargetPlatform.linux, TargetPlatform.macOS}.contains(defaultTargetPlatform);
    return [
      SettingsCategory('display', 'การแสดงผล', Icons.palette_outlined, 'ธีม · สี · หน้าต่าง', [look, if (supportsFullscreen) window]),
      SettingsCategory('mode', 'โหมดการใช้งาน', Icons.tune, 'ง่าย / ขั้นสูง · เมนูที่แสดง', [mode]),
      SettingsCategory('calendar', 'ปฏิทินและงาน', Icons.calendar_month_outlined, 'หมวดงาน · การล็อก · สติกเกอร์อัตโนมัติ', [cats, lock, autoSt]),
      SettingsCategory('study', 'การเรียน', Icons.school_outlined, 'การให้คะแนนความเข้าใจ · ติว', [grading, study]),
      SettingsCategory('sticker', 'สติกเกอร์', Icons.emoji_emotions_outlined, 'สติกเกอร์อารมณ์', [mood]),
      SettingsCategory('account', 'บัญชีและการซิงก์', Icons.person_outline, 'เข้าระบบ · ซิงก์ข้ามเครื่อง', [account]),
      SettingsCategory('devices', 'อุปกรณ์ที่เชื่อมต่อ', Icons.phone_iphone, 'วิดเจ็ต iPhone', [phone]),
      SettingsCategory('data', 'ข้อมูล', Icons.save_outlined, 'สำรอง · ล้างข้อมูล', [backup, fresh]),
      SettingsCategory('test', 'สำหรับทดสอบ', Icons.science_outlined, 'ข้อมูลตัวอย่าง · จำลองหน้าจอ', [demo, if (desktop) preview]),
      SettingsCategory('about', 'เกี่ยวกับ', Icons.info_outline, 'เวอร์ชัน', [about]),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return Scaffold(appBar: AppBar(title: const Text('ตั้งค่า')), body: const Center(child: CircularProgressIndicator()));
    }
    final cats = _cats(context);
    return Scaffold(
      appBar: AppBar(title: const Text('ตั้งค่า')),
      body: LayoutBuilder(builder: (context, box) {
        // คอม / แท็บเล็ต = 2 ฝั่ง (หมวดซ้าย · รายละเอียดขวา) · มือถือ = กดเข้าทีละชั้น
        final wide = box.maxWidth >= 900;
        final list = SettingsCategoryList(
          cats: cats,
          selected: wide ? _cat : null,
          query: _query,
          onQuery: (q) => setState(() => _query = q),
          onOpen: (id) {
            if (wide) return setState(() => _cat = id);
            Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => ValueListenableBuilder(
                valueListenable: _tick,
                builder: (ctx, _, _) => SettingsCategoryPage(cat: _cats(ctx).firstWhere((x) => x.id == id)),
              ),
            ));
          },
        );
        if (!wide) return list;
        return Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(width: 320, child: list),
          VerticalDivider(width: 1, color: context.noir.line),
          Expanded(child: SettingsCategoryBody(cat: cats.firstWhere((x) => x.id == _cat, orElse: () => cats.first))),
        ]);
      }),
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

  void _toast(String m) => showToast(context, m);

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
    final ok = await confirmMini(
      context,
      title: 'กู้คืนข้อมูล?',
      message: 'ข้อมูลจะกลับไปเป็นของไฟล์ ${p.basename(f.path)}\n'
          'แอปจะสำรองข้อมูลตอนนี้ไว้ก่อน (เผื่อเปลี่ยนใจ) แล้วกู้คืนเมื่อเปิดแอปครั้งถัดไป',
      okLabel: 'กู้คืนเมื่อเปิดใหม่',
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

/// เลือกอุปกรณ์ + แนวตั้ง / แนวนอน · จำไว้ (เปิดแอปใหม่ยังจำลองต่อ)
class _DevicePreviewSettings extends StatelessWidget {
  const _DevicePreviewSettings();

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final repo = StudyScope.of(context);
    return ValueListenableBuilder(
      valueListenable: devicePreview,
      builder: (context, v, _) {
        void set(String? id, bool land) {
          devicePreview.value = (id: id, landscape: land);
          repo.setSetting(devicePreviewKey, id == null ? '' : (land ? '$id:land' : id));
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('วาดแอปในขนาดจอจริงของมือถือ / แท็บเล็ต ให้เช็กหน้าตาได้บนคอม · ไม่ใช่ระบบ iOS / Android จริง',
              style: TextStyle(fontSize: 13, color: c.muted)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            ChoiceChip(label: const Text('ปิด'), selected: v.id == null, onSelected: (_) => set(null, false)),
            for (final d in previewDevices)
              ChoiceChip(label: Text(d.name), selected: v.id == d.id, onSelected: (_) => set(d.id, v.landscape)),
          ]),
          if (v.id != null) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: false, icon: Icon(Icons.stay_current_portrait), label: Text('แนวตั้ง')),
                  ButtonSegment(value: true, icon: Icon(Icons.stay_current_landscape), label: Text('แนวนอน')),
                ],
                selected: {v.landscape},
                onSelectionChanged: (s) => set(v.id, s.first),
              ),
            ),
          ],
        ]);
      },
    );
  }
}
