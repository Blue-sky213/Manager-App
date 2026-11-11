import 'package:flutter/material.dart';

import 'data/backup.dart';
import 'app.dart';
import 'calendar/sqlite_calendar_repository.dart';
import 'data/app_database.dart';
import 'data/sqlite_study_repository.dart';

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

  runApp(NoirManagerApp(
    studyRepository: SqliteStudyRepository(db),
    calendarRepository: SqliteCalendarRepository(db),
    askOnboarding: true,
    backup: backup,
  ));
}
