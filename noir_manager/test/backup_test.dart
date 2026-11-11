import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:noir_manager/data/backup.dart';

void main() {
  late Directory dir;
  late String path;
  late Database db;

  setUp(() async {
    sqfliteFfiInit();
    dir = await Directory.systemTemp.createTemp('noir_backup_');
    path = p.join(dir.path, 'noir_manager.db');
    db = await databaseFactoryFfi.openDatabase(path);
    await db.execute('CREATE TABLE t (v TEXT)');
    await db.insert('t', {'v': 'ข้อมูลเดิม'});
  });

  tearDown(() async {
    await db.close();
    await dir.delete(recursive: true);
  });

  Future<List<String>> rows(String file) async {
    final d = await databaseFactoryFfi.openDatabase(file);
    final r = (await d.query('t')).map((e) => e['v'] as String).toList();
    await d.close();
    return r;
  }

  test('สำรองตอนนี้ · วันเดียวกันทับ · อัตโนมัติวันละครั้ง · เก็บ 30 วัน', () async {
    final b = BackupService(db: db, dbPath: path);
    final day = DateTime(2026, 11, 11);
    final f = await b.backupNow(now: day);
    expect(p.basename(f.path), 'noir_2026-11-11.db');
    expect(await rows(f.path), ['ข้อมูลเดิม']);

    await db.insert('t', {'v': 'เพิ่มทีหลัง'});
    await b.backupNow(now: day); // วันเดียวกัน = ทับ
    expect(await b.list(), hasLength(1));
    expect(await rows(f.path), ['ข้อมูลเดิม', 'เพิ่มทีหลัง']);

    expect(await b.dailyIfNeeded(now: day), isNull); // วันนี้มีแล้ว
    expect(await b.dailyIfNeeded(now: DateTime(2026, 11, 12)), isNotNull);

    // 31 วันถัดไป → ไฟล์วันที่ 11 เก่าเกิน 30 วัน ถูกลบ
    await b.backupNow(now: DateTime(2026, 12, 12));
    final names = (await b.list()).map((f) => p.basename(f.path)).toList();
    expect(names, ['noir_2026-12-12.db', 'noir_2026-11-12.db']);
  });

  test('กู้คืน: สำรองของตอนนี้ก่อน · ทับ DB ตอนเปิดแอปครั้งถัดไป', () async {
    final b = BackupService(db: db, dbPath: path);
    final old = await b.backupNow(now: DateTime(2026, 11, 10));
    await db.insert('t', {'v': 'พิมพ์ผิด'});
    await b.scheduleRestore(old, now: DateTime(2026, 11, 11));
    expect(File(BackupService.pendingMarker(path)).existsSync(), isTrue);
    expect((await b.list()).map((f) => p.basename(f.path)), contains('noir_2026-11-11_before-restore.db'));

    await db.close();
    expect(await BackupService.applyPendingRestore(path), isTrue);
    expect(File(BackupService.pendingMarker(path)).existsSync(), isFalse);
    expect(await rows(path), ['ข้อมูลเดิม']);
    expect(await BackupService.applyPendingRestore(path), isFalse); // ไม่มีจองแล้ว
    db = await databaseFactoryFfi.openDatabase(path); // ให้ tearDown ปิดได้
  });
}
