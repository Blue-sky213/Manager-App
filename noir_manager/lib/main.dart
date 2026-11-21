import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import 'data/backup.dart';
import 'app.dart';
import 'calendar/sqlite_calendar_repository.dart';
import 'data/app_database.dart';
import 'data/demo_year.dart';
import 'data/sqlite_study_repository.dart';
import 'calendar/sticker_images.dart' show stickerFolder;
import 'sync/cloud_sync.dart';
import 'sync/sticker_files.dart' show localStickerDir;
import 'sync/google_login.dart' show takeAuthFragment;
import 'sync/phone_sync.dart';

/// จุดเริ่มต้นของแอป: Dart เรียกฟังก์ชัน main() เป็นอย่างแรกเสมอ
///
/// `async` เพราะต้องรอเปิดไฟล์ฐานข้อมูลให้เสร็จก่อนวาดหน้าจอ
Future<void> main() async {
  // ต้องเรียกก่อนใช้ plugin ใด ๆ (path_provider, sqflite) ก่อน runApp
  WidgetsFlutterBinding.ensureInitialized();

  // เว็บเพิ่งกลับมาจาก Google → เก็บ token + ล้างแถบที่อยู่ก่อน Flutter อ่านลิงก์ (รอบ 19)
  final googleBack = takeAuthFragment();
  final db = await openAppDatabase();
  // เว็บ (รอบ 17): ไม่มีไฟล์ให้สำรอง · ข้อมูลอยู่ในบัญชี
  final backup = kIsWeb ? null : BackupService(db: db, dbPath: appDatabasePath!);
  // สำรองอัตโนมัติวันละครั้ง (ไม่รอ · พลาดก็ไม่กระทบการเปิดแอป)
  backup?.dailyIfNeeded().catchError((_) => null);

  final calendar = SqliteCalendarRepository(db);
  // รอบ 20: โฟลเดอร์รูปสติกเกอร์ของเครื่องนี้ (รับรูปที่ดึงมาจากบัญชี)
  if (!kIsWeb) localStickerDir = (await stickerFolder()).path;
  if (kIsWeb) {
    // เว็บ = ใช้บัญชีเป็นหลัก (เข้าระบบใน ตั้งค่า › บัญชี)
    CloudSyncService.instance = CloudSyncService(db, calendar, devicePrefix: 'Web')
      ..start(authFragment: googleBack).catchError((_) {});
  } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
    // รอบ 14: เชื่อม iPhone ผ่าน iCloud (เฉพาะข้อมูลจริงบนคอม · ปิดอยู่จนกว่าจะเปิดในตั้งค่า)
    PhoneSyncService.instance = PhoneSyncService(calendar)..start().catchError((_) {});
    // รอบ 16: บัญชี + ซิงก์ (ยังไม่เข้าระบบ = ไม่ทำอะไร)
    CloudSyncService.instance = CloudSyncService(db, calendar, backup: backup)..start().catchError((_) {});
  }
  final real = NoirManagerApp(
    key: const ValueKey('real'),
    studyRepository: SqliteStudyRepository(db),
    calendarRepository: calendar,
    askOnboarding: !kIsWeb, // เว็บ: เข้าบัญชีแล้วได้ข้อมูลเดิม ไม่ต้องตั้งค่าใหม่
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
