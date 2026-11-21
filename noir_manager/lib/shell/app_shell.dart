import 'package:flutter/material.dart';

import '../pages/calendar_page.dart';
import '../pages/learn_page.dart';
import '../theme/noir_colors.dart';
import '../data/backup.dart';
import '../pages/settings_page.dart';
import '../data/study_scope.dart';
import '../sync/cloud_sync.dart';
import '../widgets/toast.dart';
import 'app_nav.dart';
import 'destinations.dart';

/// "โครงบ้าน" ของแอป: เมนู + พื้นที่แสดงหน้า
///
/// จอกว้าง (Windows / แท็บเล็ต)  → เมนูอยู่ซ้าย (Sidebar)
/// จอแคบ (มือถือ Android)       → เมนูอยู่ล่าง (Bottom bar)
class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.isDark,
    required this.onToggleTheme,
    this.themeId = 'dark',
    this.onTheme,
    this.backup,
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final String themeId;
  final ValueChanged<String>? onTheme;
  final BackupService? backup;

  /// ความกว้างที่ใช้แบ่ง "จอกว้าง" กับ "จอแคบ" (หน่วย logical pixel)
  static const double wideBreakpoint = 720;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // เมนูที่เลือกอยู่ (0 = วันนี้)

  /// เมนูก่อนหน้าที่ถูกพามา (เปิดวิชาจากปฏิทิน ฯลฯ) → ย้อนกลับไปทีละขั้น
  final List<int> _history = [];

  /// เมนูที่โชว์ (ไม่รวมที่ซ่อนในตั้งค่า)
  List<int> get _visible => [
        for (var i = 0; i < appDestinations.length; i++)
          if (!hiddenMenus.value.contains(appDestinations[i].label)) i,
      ];

  bool _menusLoaded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_menusLoaded) return;
    _menusLoaded = true;
    StudyScope.of(context).getSetting(hiddenMenusKey).then((v) {
      final set = {for (final x in (v ?? '').split(',')) if (hideableMenus.contains(x)) x};
      if (set.isNotEmpty) hiddenMenus.value = set;
    });
  }

  // ซ่อนเมนูที่เปิดอยู่ → กลับหน้าแรก
  void _onHidden() {
    if (!mounted) return;
    if (hiddenMenus.value.contains(appDestinations[_index].label)) {
      _select(0);
    } else {
      setState(() {});
    }
  }

  void _select(int i) {
    setState(() => _index = i);
    currentTab.value = appDestinations[i].label;
  }

  // ผู้ใช้กดเมนูเอง = เริ่มใหม่ ไม่ต้องจำทางกลับ
  void _userSelect(int i) {
    _history.clear();
    appForward.clear();
    _select(i);
  }

  void _jumpTo(bool Function(Widget page) isTarget) {
    final i = appDestinations.indexWhere((d) => isTarget(d.page));
    if (i < 0 || i == _index) return;
    _history.add(_index);
    appForward.clear(); // ไปที่ใหม่ = ทางข้างหน้าเดิมใช้ไม่ได้แล้ว
    _select(i);
  }

  // หน้าอื่นขอเปิดปฏิทิน (เช่น แตะวันสอบ) / เปิดวิชา (คลิกคาบในปฏิทิน) → สลับเมนู
  void _onJump() => _jumpTo((p) => p is CalendarPage);
  void _onSubjectJump() => _jumpTo((p) => p is LearnPage); // การเรียน = มหาลัย | สกิล (รอบ 8C)

  bool _onBack() {
    if (_history.isEmpty) return false;
    final from = _index;
    _select(_history.removeLast());
    // ปุ่ม 5 → กลับไปหน้าที่เพิ่งย้อนออกมา
    appForward.push(() {
      if (!mounted || from == _index) return;
      _history.add(_index);
      _select(from);
    });
    return true;
  }

  @override
  void initState() {
    super.initState();
    currentTab.value = appDestinations[_index].label;
    calendarJump.addListener(_onJump);
    subjectJump.addListener(_onSubjectJump);
    appBack.add(_onBack);
    appForward.clear(); // เปิดแอปใหม่ = ไม่มีทางข้างหน้าค้าง
    hiddenMenus.value = const {}; // โหลดจากตั้งค่าใน didChangeDependencies
    hiddenMenus.addListener(_onHidden);
    CloudSyncService.instance?.conflictNotice.addListener(_onCloudConflict);
  }

  /// รอบ 16: ซิงก์แล้วเจอค่าต่างกัน → เม็ดเตือน (ใช้ค่าล่าสุดไปแล้ว · ดู/สลับที่ ตั้งค่า › บัญชี)
  void _onCloudConflict() {
    final n = CloudSyncService.instance?.conflictNotice;
    final msg = n?.value;
    if (msg == null || !mounted) return;
    n!.value = null;
    showToast(context, '$msg · ดูที่ ตั้งค่า › บัญชี', kind: ToastKind.warn);
  }

  @override
  void dispose() {
    calendarJump.removeListener(_onJump);
    subjectJump.removeListener(_onSubjectJump);
    appBack.remove(_onBack);
    hiddenMenus.removeListener(_onHidden);
    CloudSyncService.instance?.conflictNotice.removeListener(_onCloudConflict);
    super.dispose();
  }

  /// ☰ เพิ่มเติม (มือถือ): เมนูที่ไม่อยู่บนแถบล่าง + ตั้งค่า
  Future<void> _openMore(BuildContext context, List<int> more) async {
    final i = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        // จอเตี้ย (มือถือแนวนอน) รายการยาวกว่าจอ → เลื่อนได้
        child: ListView(shrinkWrap: true, children: [
          for (final k in more)
            ListTile(
              leading: Icon(k == _index ? appDestinations[k].selectedIcon : appDestinations[k].icon),
              title: Text(appDestinations[k].label),
              subtitle: Text(appDestinations[k].group),
              selected: k == _index,
              onTap: () => Navigator.pop(ctx, k),
            ),
          ListTile(leading: const Icon(Icons.settings_outlined), title: const Text('ตั้งค่า'), onTap: () => Navigator.pop(ctx, -1)),
        ]),
      ),
    );
    if (i == null || !mounted) return;
    if (i < 0) {
      _openSettings();
    } else {
      _userSelect(i);
    }
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(themeId: widget.themeId, onTheme: widget.onTheme, backup: widget.backup),
    ));
  }

  @override
  Widget build(BuildContext context) {
    // IndexedStack = เก็บทุกหน้าไว้ แต่โชว์ทีละหน้า → สลับเมนูแล้วหน้าเดิมไม่ถูกรีเซ็ต
    final body = IndexedStack(
      index: _index,
      children: [for (final d in appDestinations) d.page],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= AppShell.wideBreakpoint;

        if (isWide) {
          return Scaffold(
            body: Row(
              children: [
                _Sidebar(
                  visible: _visible,
                  selectedIndex: _index,
                  onSelect: _userSelect,
                  isDark: widget.isDark,
                  onToggleTheme: widget.onToggleTheme,
                  onSettings: _openSettings,
                ),
                Expanded(child: body),
              ],
            ),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Noir Manager'),
            actions: [
              IconButton(tooltip: 'ตั้งค่า', icon: const Icon(Icons.settings_outlined), onPressed: _openSettings),
              IconButton(
                tooltip: widget.isDark ? 'โหมดสว่าง' : 'โหมดมืด',
                icon: Icon(
                  widget.isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                ),
                onPressed: widget.onToggleTheme,
              ),
            ],
          ),
          body: body,
          // มือถือ: 4 เมนูหลัก + ☰ เพิ่มเติม (รอบ 9A · แถบล่างได้ 5 ช่อง)
          bottomNavigationBar: Builder(builder: (context) {
            final bar = [for (final i in _visible) if (phoneBarMenus.contains(appDestinations[i].label)) i];
            final more = [for (final i in _visible) if (!bar.contains(i)) i];
            final sel = bar.indexOf(_index);
            return NavigationBar(
              selectedIndex: sel < 0 ? bar.length : sel,
              onDestinationSelected: (k) => k < bar.length ? _userSelect(bar[k]) : _openMore(context, more),
              destinations: [
                for (final i in bar)
                  NavigationDestination(
                    icon: Icon(appDestinations[i].icon),
                    selectedIcon: Icon(appDestinations[i].selectedIcon),
                    label: appDestinations[i].label,
                  ),
                NavigationDestination(
                  key: const Key('nav-more'),
                  icon: const Icon(Icons.menu),
                  label: 'เพิ่มเติม',
                ),
              ],
            );
          }),
        );
      },
    );
  }
}

/// แถบเมนูด้านซ้าย หน้าตาตาม Mockup 2D
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.visible,
    required this.selectedIndex,
    required this.onSelect,
    required this.isDark,
    required this.onToggleTheme,
    required this.onSettings,
  });

  final VoidCallback onSettings;
  final List<int> visible;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final bool isDark;
  final VoidCallback onToggleTheme;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;

    return Container(
      width: 232,
      decoration: BoxDecoration(
        color: c.side,
        border: Border(right: BorderSide(color: c.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
      // จอเตี้ย (เช่น มือถือแนวนอน) → เมนูเลื่อนได้แทนล้นจอ · จอปกติ ปุ่มล่างยังติดขอบล่าง
      child: CustomScrollView(slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
            child: Text(
              'Noir Manager',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
          ),
          // จัดเป็นกลุ่ม (รอบ 9A): ทุกวัน · พัฒนาตัวเอง · งาน & เงิน · ภาพรวม
          for (final (k, i) in visible.indexed) ...[
            if (k == 0 || appDestinations[visible[k - 1]].group != appDestinations[i].group)
              Padding(
                padding: EdgeInsets.fromLTRB(12, k == 0 ? 0 : 10, 12, 4),
                child: Text(appDestinations[i].group, style: TextStyle(fontSize: 11, color: c.muted, letterSpacing: 0.3)),
              ),
            _SidebarItem(
              destination: appDestinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          ],
          const Spacer(), // ดันปุ่มตั้งค่า + สลับธีมลงไปล่างสุด
          // รอบ 21: สถานะบัญชี (ออนไลน์ / กำลังบันทึก / ออฟไลน์ · รอส่ง)
          if (CloudSyncService.instance case final cloud?) CloudStatusChip(service: cloud),
          OutlinedButton.icon(
            onPressed: onSettings,
            icon: const Icon(Icons.settings_outlined),
            label: const Text('ตั้งค่า'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: c.text,
              side: BorderSide(color: c.line2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onToggleTheme,
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            label: Text(isDark ? 'โหมดสว่าง' : 'โหมดมืด'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: c.text,
              side: BorderSide(color: c.line2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ],
          ),
        ),
      ]),
    );
  }
}

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.destination,
    required this.selected,
    required this.onTap,
  });

  final AppDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    final fg = selected ? c.navText : c.muted;

    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: selected ? c.navBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Icon(
                  selected ? destination.selectedIcon : destination.icon,
                  size: 20,
                  color: fg,
                ),
                const SizedBox(width: 12),
                Text(
                  destination.label,
                  style: TextStyle(
                    color: fg,
                    fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// แถบสถานะเล็ก ๆ เหนือปุ่มตั้งค่า (รอบ 21)
class CloudStatusChip extends StatelessWidget {
  const CloudStatusChip({super.key, required this.service});
  final CloudSyncService service;

  @override
  Widget build(BuildContext context) {
    final c = context.noir;
    return ValueListenableBuilder(
      valueListenable: service.status,
      builder: (context, st, _) {
        if (st.state == CloudState.signedOut) return const SizedBox.shrink();
        final (color, text) = switch (st.state) {
          CloudState.syncing => (c.accent, 'กำลังบันทึก…'),
          CloudState.offline => (c.warn, 'ออฟไลน์ · ${st.pending} รายการรอส่ง'),
          CloudState.error => (c.bad, 'บันทึกไม่สำเร็จ · ดูในตั้งค่า'),
          _ => (c.good, st.pending > 0 ? 'รอส่ง ${st.pending} รายการ' : 'ออนไลน์ · บันทึกแล้ว'),
        };
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(key: const Key('cloud-chip'), children: [
            Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: TextStyle(fontSize: 13, color: c.muted), overflow: TextOverflow.ellipsis)),
          ]),
        );
      },
    );
  }
}
