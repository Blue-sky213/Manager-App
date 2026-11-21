import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/sync/sticker_files.dart';
import 'package:noir_manager/sync/supabase_api.dart';

/// Supabase Storage จำลองบนเครื่อง (เก็บไฟล์ในหน่วยความจำ)
Future<(HttpServer, Map<String, Uint8List>)> fakeStorage() async {
  final files = <String, Uint8List>{};
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final path = req.uri.path;
    if (req.method == 'POST' && path.startsWith('/storage/v1/object/stickers/')) {
      final b = BytesBuilder();
      await for (final c in req) {
        b.add(c);
      }
      files[path.substring('/storage/v1/object/stickers/'.length)] = b.takeBytes();
      req.response.statusCode = 200;
    } else if (req.method == 'GET' && path.startsWith('/storage/v1/object/authenticated/stickers/')) {
      final f = files[path.substring('/storage/v1/object/authenticated/stickers/'.length)];
      if (f == null) {
        req.response.statusCode = 400;
        req.response.write('{"error":"not_found","message":"Object not found"}');
      } else {
        req.response.add(f);
      }
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return (server, files);
}

SupabaseApi api(HttpServer s) => SupabaseApi(url: 'http://127.0.0.1:${s.port}', key: 'k')
  ..session = const CloudSession(accessToken: 't', refreshToken: 'r', expiresAt: 4102444800, userId: 'u1', email: 'a@b.c');

void main() {
  test('ย้ายเครื่อง: เครื่องเก่าส่งรูปขึ้น (ครั้งเดียว) → เครื่องใหม่ดึงมาเก็บในโฟลเดอร์ตัวเอง → วาดได้', () async {
    final (server, files) = await fakeStorage();
    final oldPc = await Directory.systemTemp.createTemp('old_pc_');
    final newPc = await Directory.systemTemp.createTemp('new_pc_');
    final png = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]);
    final oldPath = '${oldPc.path}${Platform.pathSeparator}st_1795.png';
    await File(oldPath).writeAsBytes(png);

    // เครื่องเก่า
    localStickerDir = oldPc.path;
    final settingsA = <String, String>{};
    final a = StickerFileSync(api(server),
        readSetting: (k) async => settingsA[k], writeSetting: (k, v) async => settingsA[k] = v);
    expect(await a.run([oldPath]), 0);
    expect(files['u1/st_1795.png'], png);
    files.clear();
    expect(await a.run([oldPath]), 0);
    expect(files, isEmpty); // ส่งแล้วไม่ส่งซ้ำ
    await a.run([oldPath]);

    // ส่งใหม่ให้มีในที่เก็บ (เคลียร์ไปตอนเทสส่งซ้ำ)
    settingsA.clear();
    await a.run([oldPath]);

    // เครื่องใหม่: ที่อยู่ในฐานข้อมูลเป็นของเครื่องเก่า (Windows) · ไฟล์ไม่มี
    localStickerDir = newPc.path;
    const winPath = r'C:\Users\Noir\AppData\Roaming\noir_manager\stickers\st_1795.png';
    expect(resolveStickerFile(winPath), isNull);
    final b = StickerFileSync(api(server), readSetting: (_) async => null, writeSetting: (_, _) async {});
    expect(await b.run([winPath, winPath]), 1);
    final got = resolveStickerFile(winPath);
    expect(got, isNotNull);
    expect(await File(got!).readAsBytes(), png);
    expect(stickerFileName(winPath), 'st_1795.png');

    // รูปที่ไม่มีที่ไหนเลย = ข้ามเงียบ ๆ
    expect(await b.run([r'C:\x\st_none.png', '../../evil']), 0);
    await server.close(force: true);
  });
}
