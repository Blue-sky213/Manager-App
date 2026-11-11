import 'package:flutter/material.dart';

import '../pages/calendar_page.dart';
import '../pages/study_page.dart';
import '../theme/noir_colors.dart';
import '../pages/settings_page.dart';
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
  });

  final bool isDark;
  final VoidCallback onToggleTheme;
  final String themeId;
  final ValueChanged<String>? onTheme;

  /// ความกว้างที่ใช้แบ่ง "จอกว้าง" กับ "จอแคบ" (หน่วย logical pixel)
  static const double wideBreakpoint = 720;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0; // เมนูที่เลือกอยู่ (0 = วันนี้)

  /// เมนูก่อนหน้าที่ถูกพามา (เปิดวิชาจากปฏิทิน ฯลฯ) → ย้อนกลับไปทีละขั้น
  final List<int> _history = [];

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
  void _onSubjectJump() => _jumpTo((p) => p is StudyPage);

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
  }

  @override
  void dispose() {
    calendarJump.removeListener(_onJump);
    subjectJump.removeListener(_onSubjectJump);
    appBack.remove(_onBack);
    super.dispose();
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => SettingsPage(themeId: widget.themeId, onTheme: widget.onTheme),
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
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: _userSelect,
            destinations: [
              for (final d in appDestinations)
                NavigationDestination(
                  icon: Icon(d.icon),
                  selectedIcon: Icon(d.selectedIcon),
                  label: d.label,
                ),
            ],
          ),
        );
      },
    );
  }
}

/// แถบเมนูด้านซ้าย หน้าตาตาม Mockup 2D
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedIndex,
    required this.onSelect,
    required this.isDark,
    required this.onToggleTheme,
    required this.onSettings,
  });

  final VoidCallback onSettings;
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
          for (var i = 0; i < appDestinations.length; i++)
            _SidebarItem(
              destination: appDestinations[i],
              selected: i == selectedIndex,
              onTap: () => onSelect(i),
            ),
          const Spacer(), // ดันปุ่มตั้งค่า + สลับธีมลงไปล่างสุด
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
      padding: const EdgeInsets.only(bottom: 4),
      child: Material(
        color: selected ? c.navBg : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
