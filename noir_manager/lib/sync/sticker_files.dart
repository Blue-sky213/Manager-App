/// รูปสติกเกอร์ข้ามเครื่อง (รอบ 20 · นัวร์ย้ายคอมแล้วรูปหาย)
/// - ชื่อไฟล์ไม่ซ้ำ (st_<เวลา>.png) → ใช้ชื่อไฟล์เป็นกุญแจ: Storage `stickers/<บัญชี>/<ชื่อไฟล์>`
/// - เครื่องที่มีไฟล์ = ส่งขึ้น (ครั้งเดียวต่อไฟล์) · เครื่องที่ไม่มี = ดึงมาเก็บในโฟลเดอร์สติกเกอร์ของเครื่องนั้น
/// - ที่อยู่ไฟล์ในฐานข้อมูลไม่แก้ (เป็นค่าที่ซิงก์) → ตอนวาดค่อยหาไฟล์ชื่อเดียวกันในโฟลเดอร์ของเครื่องนี้
/// - เว็บ: เก็บรูปในหน่วยความจำ (โหลดใหม่ทุกครั้งที่เปิดหน้า · รูปละไม่กี่ KB)
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'supabase_api.dart';

const stickerBucket = 'stickers';
const stickerUploadedKey = 'cloud_sticker_up';

/// โฟลเดอร์รูปสติกเกอร์ของเครื่องนี้ (ตั้งตอนเปิดแอป) · null = เว็บ / เทส
String? localStickerDir;

/// เว็บ: รูปที่ดึงมาแล้ว (ชื่อไฟล์ → ไฟล์) · เปลี่ยน = วาดใหม่
final webStickerBytes = ValueNotifier<Map<String, Uint8List>>(const {});

/// ชื่อไฟล์จากที่อยู่ของเครื่องไหนก็ได้ (Windows ใช้ \ · ที่อื่นใช้ /)
String stickerFileName(String path) => path.split(RegExp(r'[\\/]')).last;

bool _safeName(String n) => RegExp(r'^[A-Za-z0-9_.\-]+$').hasMatch(n) && !n.startsWith('.');

/// ไฟล์จริงบนเครื่องนี้: ที่เดิม หรือ ชื่อเดียวกันในโฟลเดอร์สติกเกอร์ของเครื่องนี้ · null = ยังไม่มี
String? resolveStickerFile(String path) {
  if (kIsWeb) return null;
  if (File(path).existsSync()) return path;
  final d = localStickerDir;
  if (d == null) return null;
  final alt = '$d${Platform.pathSeparator}${stickerFileName(path)}';
  return File(alt).existsSync() ? alt : null;
}

class StickerFileSync {
  StickerFileSync(this.api, {required this.readSetting, required this.writeSetting});

  final SupabaseApi api;
  final Future<String?> Function(String key) readSetting;
  final Future<void> Function(String key, String value) writeSetting;

  /// ส่งรูปที่ยังไม่เคยส่ง + ดึงรูปที่เครื่องนี้ไม่มี · คืนจำนวนรูปที่ดึงมาใหม่
  Future<int> run(Iterable<String> paths) async {
    final uid = api.session?.userId;
    if (uid == null || uid.isEmpty) return 0;
    final raw = await readSetting(stickerUploadedKey);
    final uploaded = <String>{if (raw != null && raw.isNotEmpty) ...(jsonDecode(raw) as List).cast<String>()};
    final before = uploaded.length;
    var got = 0;
    final web = {...webStickerBytes.value};
    for (final path in paths.toSet()) {
      final name = stickerFileName(path);
      if (!_safeName(name)) continue;
      final remote = 'object/$stickerBucket/$uid/$name';
      final local = resolveStickerFile(path);
      if (local != null) {
        if (uploaded.contains(name)) continue;
        final (code, body) = await api.storage('POST', remote, body: await File(local).readAsBytes());
        _check(code, body);
        if (code < 300) uploaded.add(name);
        continue;
      }
      if (kIsWeb && web.containsKey(name)) continue;
      final (code, bytes) = await api.storage('GET', 'object/authenticated/$stickerBucket/$uid/$name');
      if (code == 400 || code == 404) continue; // เครื่องที่มีรูปยังไม่ได้ส่งขึ้น
      _check(code, bytes);
      if (code >= 300) continue;
      if (kIsWeb) {
        web[name] = bytes;
      } else if (localStickerDir != null) {
        await Directory(localStickerDir!).create(recursive: true);
        await File('${localStickerDir!}${Platform.pathSeparator}$name').writeAsBytes(bytes);
      }
      got++;
    }
    if (uploaded.length != before) await writeSetting(stickerUploadedKey, jsonEncode(uploaded.toList()));
    if (kIsWeb && got > 0) webStickerBytes.value = web;
    return got;
  }

  void _check(int code, Uint8List body) {
    if (code < 300) return;
    final t = utf8.decode(body, allowMalformed: true);
    if (t.contains('Bucket not found') || (t.contains('row-level security') && t.contains('policy'))) {
      throw CloudError('ยังไม่ได้สร้างที่เก็บรูปบน Supabase (รัน SQL ใน docs/supabase/002_sticker_files.sql)', status: code);
    }
  }
}
