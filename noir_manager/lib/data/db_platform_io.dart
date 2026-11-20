/// ที่อยู่ + ตัวเปิด SQLite บนคอม / มือถือ (รอบ 17 แยกจากเว็บ)
library;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;

/// Windows/Linux ไม่มี SQLite ในตัวแบบ Android → ใช้ตัว FFI · คืนที่อยู่ไฟล์
Future<String> prepareDatabase(String name) async {
  if (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.linux) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  // Windows: C:\Users\<ชื่อ>\AppData\Roaming\<บริษัท>\noir_manager\
  final dir = await getApplicationSupportDirectory();
  return p.join(dir.path, name);
}
