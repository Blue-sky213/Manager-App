/// WebSocket แบบไม่เพิ่ม package (รอบ 21): คอม/มือถือ = dart:io · เว็บ = WebSocket ของเบราว์เซอร์
library;

export 'ws_io.dart' if (dart.library.js_interop) 'ws_web.dart';
