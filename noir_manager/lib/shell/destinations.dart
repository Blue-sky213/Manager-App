import 'package:flutter/material.dart';

import '../pages/calendar_page.dart';
import '../pages/files_page.dart';
import '../pages/learn_page.dart';
import '../pages/stats_page.dart';
import '../pages/today_page.dart';

/// ข้อมูลของเมนู 1 ปุ่ม: ชื่อ + ไอคอน + หน้าที่จะเปิด
class AppDestination {
  const AppDestination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.page,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget page;
}

/// รายการเมนูหลักทั้ง 5 (เรียงตาม Mockup)
/// อยากเพิ่ม/ย้ายเมนู แก้ที่นี่ที่เดียว ทั้ง Sidebar และ Bottom bar เปลี่ยนตาม
const List<AppDestination> appDestinations = [
  AppDestination(
    label: 'วันนี้',
    icon: Icons.today_outlined,
    selectedIcon: Icons.today,
    page: TodayPage(),
  ),
  AppDestination(
    label: 'ปฏิทิน',
    icon: Icons.calendar_month_outlined,
    selectedIcon: Icons.calendar_month,
    page: CalendarPage(),
  ),
  AppDestination(
    label: 'การเรียน',
    icon: Icons.account_tree_outlined,
    selectedIcon: Icons.account_tree,
    page: LearnPage(), // มหาลัย | สกิล (รอบ 8C)
  ),
  AppDestination(
    label: 'ไฟล์',
    icon: Icons.folder_outlined,
    selectedIcon: Icons.folder,
    page: FilesPage(),
  ),
  AppDestination(
    label: 'สถิติ',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
    page: StatsPage(),
  ),
];
