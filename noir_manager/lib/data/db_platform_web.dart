/// SQLite บนเว็บ (รอบ 17): WebAssembly + เก็บใน IndexedDB ของเบราว์เซอร์
/// ต้องมี web/sqlite3.wasm (CI รัน `dart run sqflite_common_ffi_web:setup` ก่อน build)
library;

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart' show databaseFactoryFfiWebNoWebWorker;

/// แท็บเดียวใช้พอ → ไม่ใช้ shared worker (Safari บน iPhone รองรับแน่นอนกว่า)
Future<String> prepareDatabase(String name) async {
  databaseFactory = databaseFactoryFfiWebNoWebWorker;
  return name;
}
