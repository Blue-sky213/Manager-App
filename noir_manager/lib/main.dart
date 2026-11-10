import 'package:flutter/material.dart';

import 'app.dart';
import 'calendar/sqlite_calendar_repository.dart';
import 'data/app_database.dart';
import 'data/backup_service.dart';
import 'data/sqlite_study_repository.dart';

/// จุดเริ่มต้นของแอป: Dart เรียกฟังก์ชัน main() เป็นอย่างแรกเสมอ
///
/// `async` เพราะต้องรอเปิดไฟล์ฐานข้อมูลให้เสร็จก่อนวาดหน้าจอ
Future<void> main() async {
  // ต้องเรียกก่อนใช้ plugin ใด ๆ (path_provider, sqflite) ก่อน runApp
  WidgetsFlutterBinding.ensureInitialized();

  final path = await appDatabasePath();
  // กู้คืนต้องทำก่อนเปิด DB (ไฟล์ที่เปิดอยู่ทับไม่ได้)
  final restoredFrom = await applyPendingRestore(path);
  final db = await openAppDatabase(path);

  final backup = BackupService(db: db, dbPath: path, dir: BackupService.dirFor(path));
  // สำรองประจำวันทำเบื้องหลัง ไม่ให้เปิดแอปช้า · พังก็ไม่ล้มแอป
  backup.runDaily().ignore();
  backup.startHourly();

  runApp(BackupScope(
    service: backup,
    restoredFrom: restoredFrom,
    child: NoirManagerApp(
      studyRepository: SqliteStudyRepository(db),
      calendarRepository: SqliteCalendarRepository(db),
    ),
  ));
}
