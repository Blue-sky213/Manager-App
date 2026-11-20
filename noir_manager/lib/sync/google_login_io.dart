library;

import 'dart:async';
import 'dart:io';

/// พอร์ตที่ลงทะเบียนไว้ใน Supabase › Redirect URLs (http://localhost:43823/**)
const googleLoopbackPort = 43823;

/// เว็บเท่านั้น (คอมคืน null เสมอ)
String? takeAuthFragment() => null;

/// หน้าเล็ก ๆ ที่ Google พากลับมา: อ่าน token หลัง # (เบราว์เซอร์ไม่ส่งส่วนนี้ให้เซิร์ฟเวอร์) แล้วส่งกลับมาที่แอป
const _page = '''<!doctype html><meta charset="utf-8"><title>Noir Manager</title>
<body style="font-family:sans-serif;background:#11141b;color:#e4e8f0;display:grid;place-items:center;height:100vh;margin:0">
<p id="m">กำลังเข้าระบบ…</p>
<script>
const h = location.hash.length > 1 ? location.hash.substring(1) : location.search.substring(1);
fetch('/done?' + h).then(() => {
  document.getElementById('m').textContent = h.includes('access_token')
    ? '✓ เข้าระบบแล้ว · ปิดแท็บนี้แล้วกลับไปที่ Noir Manager ได้เลย'
    : 'เข้าระบบไม่สำเร็จ · กลับไปที่แอปแล้วลองใหม่';
});
</script>''';

/// เปิดหน้า Google ในเบราว์เซอร์ → รอให้กลับมาที่ localhost · คืน "access_token=…" (null = หมดเวลา 5 นาที)
Future<String?> googleSignInFlow(Uri Function(String redirectTo) urlFor, Future<void> Function(String url) open) async {
  final done = Completer<String?>();
  final servers = <HttpServer>[];
  // localhost อาจเป็น IPv4 หรือ IPv6 → ฟังทั้งคู่ (เฉพาะในเครื่อง ไม่เปิดออกเน็ต)
  for (final addr in [InternetAddress.loopbackIPv4, InternetAddress.loopbackIPv6]) {
    try {
      servers.add(await HttpServer.bind(addr, googleLoopbackPort));
    } catch (_) {}
  }
  if (servers.isEmpty) throw StateError('พอร์ต $googleLoopbackPort ถูกใช้อยู่ · ปิดแอปที่เปิดซ้อนแล้วลองใหม่');
  for (final s in servers) {
    s.listen((req) async {
      final res = req.response;
      if (req.uri.path == '/done') {
        res.statusCode = 200;
        await res.close();
        if (!done.isCompleted) done.complete(req.uri.query);
        return;
      }
      res.headers.contentType = ContentType.html;
      res.write(_page);
      await res.close();
    });
  }
  try {
    await open(urlFor('http://localhost:$googleLoopbackPort/').toString());
    return await done.future.timeout(const Duration(minutes: 5), onTimeout: () => null);
  } finally {
    for (final s in servers) {
      await s.close(force: true);
    }
  }
}
