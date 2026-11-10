import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// ไฟล์สำรอง 1 ไฟล์: noir_manager-2026-11-10.db (อัตโนมัติ) หรือ noir_manager-2026-11-10-1430.db (กดเอง / ก่อนกู้คืน)
class BackupInfo {
  const BackupInfo({required this.file, required this.taken, required this.auto, required this.bytes});
  final File file;
  final DateTime taken;

  /// true = สำรองอัตโนมัติประจำวัน
  final bool auto;
  final int bytes;

  String get name => p.basename(file.path);
}

final _nameRe = RegExp(r'^noir_manager-(\d{4})-(\d{2})-(\d{2})(?:-(\d{2})(\d{2}))?\.db$');
const _pendingFile = 'restore-pending.txt';

String _two(int n) => n.toString().padLeft(2, '0');
String _day(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

/// อ่านวัน/เวลาจากชื่อไฟล์ · ไม่ใช่ไฟล์สำรองของแอป → null (ไฟล์อื่นในโฟลเดอร์ไม่ถูกแตะ)
({DateTime taken, bool auto})? parseBackupName(String name) {
  final m = _nameRe.firstMatch(name);
  if (m == null) return null;
  int g(int i) => int.parse(m.group(i)!);
  final auto = m.group(4) == null;
  return (
    taken: DateTime(g(1), g(2), g(3), auto ? 0 : g(4), auto ? 0 : g(5)),
    auto: auto,
  );
}

/// สำรองข้อมูล: วันละครั้งอัตโนมัติ + กดเอง · ลบไฟล์ที่เก่ากว่า [keepDays] วัน · กู้คืนตอนเปิดแอปครั้งถัดไป
class BackupService {
  BackupService({
    required this.db,
    required this.dbPath,
    required this.dir,
    this.keepDays = 30,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Database db;
  final String dbPath;
  final Directory dir;
  final int keepDays;
  final DateTime Function() _clock;

  /// โฟลเดอร์สำรองข้าง ๆ ไฟล์ DB
  static Directory dirFor(String dbPath) => Directory(p.join(p.dirname(dbPath), 'backups'));

  /// ประจำวัน: ยังไม่มีไฟล์ของวันนี้ → สำรอง · แล้วลบไฟล์เก่าเกินกำหนด
  /// เปิดแอปครั้งแรกของวัน = เก็บสภาพข้อมูลตอนจบวันก่อนหน้า
  Future<File?> runDaily() async {
    final file = File(p.join(dir.path, 'noir_manager-${_day(_clock())}.db'));
    File? made;
    if (!await file.exists()) made = await _snapshot(file);
    await pruneOld();
    return made;
  }

  /// กดเอง: ได้ไฟล์ใหม่ทุกครั้ง (มีเวลาในชื่อ)
  Future<File> backupNow() async {
    final now = _clock();
    return _snapshot(File(p.join(dir.path, 'noir_manager-${_day(now)}-${_two(now.hour)}${_two(now.minute)}.db')));
  }

  Future<File> _snapshot(File target) async {
    await dir.create(recursive: true);
    if (await target.exists()) await target.delete();
    try {
      // VACUUM INTO = สำเนาที่สมบูรณ์แม้ DB เปิดใช้อยู่ (ไม่ได้ไฟล์ครึ่ง ๆ กลาง ๆ)
      await db.execute('VACUUM INTO ?', [target.path]);
    } on DatabaseException {
      // SQLite รุ่นเก่า (Android บางเครื่อง) ไม่มี VACUUM INTO → คัดลอกไฟล์ตรง ๆ
      await File(dbPath).copy(target.path);
    }
    return target;
  }

  /// ลบเฉพาะไฟล์สำรองของแอปที่เก่ากว่า keepDays วัน · คืนจำนวนที่ลบ
  Future<int> pruneOld() async {
    if (!await dir.exists()) return 0;
    final today = _clock();
    final cutoff = DateTime(today.year, today.month, today.day).subtract(Duration(days: keepDays));
    var removed = 0;
    for (final b in await list()) {
      if (b.taken.isBefore(cutoff)) {
        await b.file.delete();
        removed++;
      }
    }
    return removed;
  }

  /// ไฟล์สำรองทั้งหมด ใหม่สุดก่อน
  Future<List<BackupInfo>> list() async {
    if (!await dir.exists()) return [];
    final out = <BackupInfo>[];
    await for (final e in dir.list()) {
      if (e is! File) continue;
      final parsed = parseBackupName(p.basename(e.path));
      if (parsed == null) continue;
      out.add(BackupInfo(file: e, taken: parsed.taken, auto: parsed.auto, bytes: await e.length()));
    }
    out.sort((a, b) => b.taken.compareTo(a.taken));
    return out;
  }

  /// นัดกู้คืน: ทับไฟล์ DB ตอนแอปเปิดครั้งถัดไป (ตอนนี้ DB เปิดอยู่ ทับไม่ได้)
  Future<void> scheduleRestore(BackupInfo backup) async {
    await File(p.join(dir.path, _pendingFile)).writeAsString(backup.name);
  }

  Future<String?> pendingRestore() async {
    final f = File(p.join(dir.path, _pendingFile));
    return await f.exists() ? (await f.readAsString()).trim() : null;
  }

  Future<void> cancelRestore() async {
    final f = File(p.join(dir.path, _pendingFile));
    if (await f.exists()) await f.delete();
  }

  /// แอปค้างเปิดข้ามคืน → เช็กทุกชั่วโมง วันใหม่ก็ได้ไฟล์ใหม่
  Timer startHourly() => Timer.periodic(const Duration(hours: 1), (_) => runDaily());
}

/// เรียกก่อนเปิด DB: มีนัดกู้คืน → สำรองสภาพปัจจุบันก่อน แล้วค่อยทับ (กดพลาดก็ย้อนกลับได้)
/// คืนชื่อไฟล์ที่กู้คืน หรือ null ถ้าไม่มีนัด
Future<String?> applyPendingRestore(String dbPath, {DateTime? now}) async {
  final dir = BackupService.dirFor(dbPath);
  final marker = File(p.join(dir.path, _pendingFile));
  if (!await marker.exists()) return null;
  final name = (await marker.readAsString()).trim();
  await marker.delete(); // ลบก่อน: ถ้ากู้คืนพัง จะไม่วนพังทุกครั้งที่เปิดแอป
  final source = File(p.join(dir.path, name));
  if (parseBackupName(name) == null || !await source.exists()) return null;

  final t = now ?? DateTime.now();
  final current = File(dbPath);
  if (await current.exists()) {
    await current.copy(p.join(dir.path, 'noir_manager-${_day(t)}-${_two(t.hour)}${_two(t.minute)}.db'));
  }
  for (final extra in ['-journal', '-wal', '-shm']) {
    final f = File('$dbPath$extra');
    if (await f.exists()) await f.delete();
  }
  await source.copy(dbPath);
  return name;
}

/// ส่ง BackupService ลงไปให้หน้า "ไฟล์" · เทส / ไม่มี DB จริง → ไม่มี scope
class BackupScope extends InheritedWidget {
  const BackupScope({super.key, required this.service, this.restoredFrom, required super.child});

  final BackupService service;

  /// เปิดแอปรอบนี้เพิ่งกู้คืนจากไฟล์นี้
  final String? restoredFrom;

  static BackupScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<BackupScope>();

  @override
  bool updateShouldNotify(BackupScope old) => service != old.service || restoredFrom != old.restoredFrom;
}
