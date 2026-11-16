import 'package:flutter/material.dart';

import '../pages/calendar_page.dart';
import '../pages/files_page.dart';
import '../pages/learn_page.dart';
import '../pages/money_page.dart';
import '../pages/skill_menu_page.dart';
import '../pages/stats_tabs.dart';
import '../pages/today_page.dart';
import '../pages/work_page.dart';

/// ข้อมูลของเมนู 1 ปุ่ม: ชื่อ + ไอคอน + หน้าที่จะเปิด + กลุ่ม (หัวข้อเล็กในแถบซ้าย)
class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
    required this.group,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
  final String group;
}

/// เมนูหลัก (รอบ 9A) · จัดเป็นกลุ่ม · เมนูใน [hiddenMenus] ไม่โชว์
/// อยากเพิ่ม/ย้ายเมนู แก้ที่นี่ที่เดียว ทั้งแถบซ้ายและแถบล่างเปลี่ยนตาม
const List<AppDestination> appDestinations = [
  AppDestination(label: 'วันนี้', group: 'ทุกวัน', icon: Icons.today_outlined, selectedIcon: Icons.today, page: TodayPage()),
  AppDestination(
      label: 'ปฏิทิน', group: 'ทุกวัน', icon: Icons.calendar_month_outlined, selectedIcon: Icons.calendar_month, page: CalendarPage()),
  AppDestination(
      label: 'การเรียน', group: 'พัฒนาตัวเอง', icon: Icons.school_outlined, selectedIcon: Icons.school, page: LearnPage()),
  AppDestination(
      label: 'สกิล', group: 'พัฒนาตัวเอง', icon: Icons.auto_awesome_outlined, selectedIcon: Icons.auto_awesome, page: SkillMenuPage()),
  AppDestination(label: 'งาน', group: 'งาน & เงิน', icon: Icons.work_outline, selectedIcon: Icons.work, page: WorkPage()),
  AppDestination(
      label: 'เงิน',
      group: 'งาน & เงิน',
      icon: Icons.account_balance_wallet_outlined,
      selectedIcon: Icons.account_balance_wallet,
      page: MoneyPage()),
  AppDestination(label: 'สถิติ', group: 'สรุป', icon: Icons.insights_outlined, selectedIcon: Icons.insights, page: StatsPage()),
  AppDestination(label: 'ไฟล์', group: 'สรุป', icon: Icons.folder_outlined, selectedIcon: Icons.folder, page: FilesPage()),
];

/// มือถือ: แถบล่างได้ 4 เมนู + ☰ เพิ่มเติม (ที่เหลือ)
const phoneBarMenus = ['วันนี้', 'ปฏิทิน', 'การเรียน', 'เงิน'];
