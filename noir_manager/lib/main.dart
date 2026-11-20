import 'dart:io';

import 'package:flutter/material.dart';

import 'data/backup.dart';
import 'app.dart';
import 'calendar/sqlite_calendar_repository.dart';
import 'data/app_database.dart';
import 'data/demo_year.dart';
import 'data/sqlite_study_repository.dart';
import 'sync/cloud_sync.dart';
import 'sync/phone_sync.dart';

/// จุดเริ่มต้นของแอป: Dart เรียกฟังก์ชัน main() เป็นอย่างแรกเสมอ
///
/// `async` เพราะต้องรอเปิดไฟล์ฐานข้อมูลให้เสร็จก่อนวาดหน้าจอ
Future<void> main() async {
  // ต้องเรียกก่อนใช้ plugin ใด ๆ (path_provider, sqflite) ก่อน runApp
  WidgetsFlutterBinding.ensureInitialized();

  final db = await openAppDatabase();
  final backup = BackupService(db: db, dbPath: appDatabasePath!);
  // สำรองอัตโนมัติวันละครั้ง (ไม่รอ · พลาดก็ไม่กระทบการเปิดแอป)
  backup.dailyIfNeeded().catchError((_) => null);

  final calendar = SqliteCalendarRepository(db);
  // รอบ 14: เชื่อม iPhone ผ่าน iCloud (เฉพาะข้อมูลจริงบนคอม · ปิดอยู่จนกว่าจะเปิดในตั้งค่า)
  if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    PhoneSyncService.instance = PhoneSyncService(calendar)..start().catchError((_) {});
    // รอบ 16: บัญชี + ซิงก์ (ยังไม่เข้าระบบ = ไม่ทำอะไร)
    CloudSyncService.instance = CloudSyncService(db, calendar, backup: backup)..start().catchError((_) {});
  }
  final real = NoirManagerApp(
    key: const ValueKey('real'),
    studyRepository: SqliteStudyRepository(db),
    calendarRepository: calendar,
    askOnboarding: true,
    backup: backup,
  );
  runApp(DemoRoot(real: real));
}

/// สลับข้อมูลจริง ↔ ข้อมูลตัวอย่าง 1 ปี (ในหน่วยความจำ) โดยไม่แตะไฟล์ฐานข้อมูล
class DemoRoot extends StatefulWidget {
  const DemoRoot({super.key, required this.real});
  final Widget real;

  @override
  State<DemoRoot> createState() => _DemoRootState();
}

class _DemoRootState extends State<DemoRoot> {
  Future<DemoYear>? _demo;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: demoMode,
        builder: (context, on, _) {
          if (!on) {
            _demo = null; // ปิดแล้วทิ้งข้อมูลตัวอย่าง
            return widget.real;
          }
          _demo ??= buildDemoYear();
          return FutureBuilder(
            future: _demo,
            builder: (context, snap) {
              final d = snap.data;
              if (d == null) {
                return const Directionality(
                  textDirection: TextDirection.ltr,
                  child: ColoredBox(
                    color: Color(0xFF0F1418),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                );
              }
              return NoirManagerApp(key: const ValueKey('demo'), studyRepository: d.study, calendarRepository: d.calendar);
            },
          );
        },
      );
}
