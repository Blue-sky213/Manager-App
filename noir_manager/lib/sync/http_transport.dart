/// ส่ง HTTP แบบไม่เพิ่ม package (รอบ 17): คอม/มือถือ = dart:io · เว็บ = fetch ของเบราว์เซอร์
library;

export 'http_transport_io.dart' if (dart.library.js_interop) 'http_transport_web.dart';

/// เชื่อมต่อไม่ได้ (ไม่มีเน็ต / ช้า / ขาดกลางทาง) · ข้อความภาษาไทย
class TransportError implements Exception {
  TransportError(this.message);
  final String message;
  @override
  String toString() => message;
}
