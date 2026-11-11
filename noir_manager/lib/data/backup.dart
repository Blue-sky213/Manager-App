import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' show Database;

/// สำรอง / กู้ข้อมูลในแอป
/// - เก็บไว้ในโฟลเดอร์ `backups` ข้างไฟล์ DB · ชื่อ noir_YYYY-MM-DD.db (วันเดียวกันเขียนทับ)
/// - เก็บ 30 วันล่าสุด เก่ากว่านั้นลบทิ้ง
/// - กู้คืน: ไฟล์ DB ใช้อยู่ทับตรง ๆ ไม่ได้ → จองไว้ แล้วทับตอนเปิดแอปครั้งถัดไป (ก่อนเปิด DB)
class BackupService {
  BackupService({required this.db, required this.dbPath, this.keepDays = 30});

  final Database db;
  final String dbPath;
  final int keepDays;

  Directory get folder => Directory(p.join(p.dirname(dbPath), 'backups'));
  static String pendingMarker(String dbPath) => p.join(p.dirname(dbPath), 'restore.pending');

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  /// ไฟล์สำรองทั้งหมด ใหม่ → เก่า
  Future<List<File>> list() async {
    if (!await folder.exists()) return const [];
    final files = await folder
        .list()
        .where((e) => e is File && p.basename(e.path).startsWith('noir_') && e.path.endsWith('.db'))
        .cast<File>()
        .toList();
    files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
    return files;
  }

  /// สำรองตอนนี้ · [label] ต่อท้ายชื่อ (เช่น ก่อนกู้คืน) · คืนไฟล์ที่ได้
  Future<File> backupNow({DateTime? now, String? label}) async {
    await folder.create(recursive: true);
    final name = 'noir_${_day(now ?? DateTime.now())}${label == null ? '' : '_$label'}.db';
    final out = File(p.join(folder.path, name));
    if (await out.exists()) await out.delete(); // วันเดียวกัน = ทับ
    try {
      // VACUUM INTO = สำเนาที่ถูกต้องแม้แอปเปิด DB อยู่ (SQLite 3.27+)
      await db.execute('VACUUM INTO ?', [out.path]);
    } catch (_) {
      // SQLite เก่า (Android บางรุ่น) → คัดลอกไฟล์ตรง ๆ
      await File(dbPath).copy(out.path);
    }
    await _prune(now ?? DateTime.now());
    await _syncStickers(stickerDir, Directory(p.join(folder.path, 'stickers')));
    return out;
  }

  /// สำรองอัตโนมัติวันละครั้ง (เรียกตอนเปิดแอป) · วันนี้มีแล้ว = ข้าม
  Future<File?> dailyIfNeeded({DateTime? now}) async {
    final today = 'noir_${_day(now ?? DateTime.now())}.db';
    if ((await list()).any((f) => p.basename(f.path) == today)) return null;
    return backupNow(now: now);
  }

  /// รูปสติกเกอร์ (ไฟล์ชื่อไม่ซ้ำ ไม่ถูกแก้) → คัดลอกเฉพาะที่ยังไม่มี
  Directory get stickerDir => Directory(p.join(p.dirname(dbPath), 'stickers'));

  static Future<void> _syncStickers(Directory from, Directory to) async {
    if (!await from.exists()) return;
    await to.create(recursive: true);
    await for (final e in from.list()) {
      if (e is! File) continue;
      final dest = File(p.join(to.path, p.basename(e.path)));
      if (!await dest.exists()) await e.copy(dest.path);
    }
  }

  Future<void> _prune(DateTime now) async {
    final cutoff = DateTime(now.year, now.month, now.day - keepDays);
    for (final f in await list()) {
      final m = RegExp(r'noir_(\d{4})-(\d{2})-(\d{2})').firstMatch(p.basename(f.path));
      if (m == null) continue;
      final d = DateTime(int.parse(m[1]!), int.parse(m[2]!), int.parse(m[3]!));
      if (d.isBefore(cutoff)) await f.delete();
    }
  }

  /// จองกู้คืน: สำรองของตอนนี้ไว้ก่อน (เผื่อเปลี่ยนใจ) แล้วจดว่าจะเอาไฟล์ไหนกลับ
  Future<void> scheduleRestore(File backup, {DateTime? now}) async {
    await backupNow(now: now, label: 'before-restore');
    await File(pendingMarker(dbPath)).writeAsString(backup.path);
  }

  /// เรียกใน main ก่อนเปิด DB: มีการจองกู้คืน → เอาไฟล์สำรองทับ DB · คืน true ถ้ากู้แล้ว
  static Future<bool> applyPendingRestore(String dbPath) async {
    final marker = File(pendingMarker(dbPath));
    if (!await marker.exists()) return false;
    final src = File((await marker.readAsString()).trim());
    await marker.delete();
    if (!await src.exists()) return false;
    await src.copy(dbPath);
    // รูปสติกเกอร์ที่ DB เก่าอ้างถึงแต่หายไป → เอากลับจากที่สำรองไว้
    final base = p.dirname(dbPath);
    await _syncStickers(Directory(p.join(base, 'backups', 'stickers')), Directory(p.join(base, 'stickers')));
    return true;
  }
}
