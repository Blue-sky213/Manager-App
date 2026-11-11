import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// รูปสติกเกอร์เก็บในโฟลเดอร์ `stickers` ของแอป (ข้างไฟล์ DB)
/// ย่อด้านยาวเหลือ 256px ก่อนเก็บ → ไฟล์เล็ก ลื่นบนเครื่องไม่แรง · ลบรูปต้นฉบับแล้วสติกเกอร์ยังอยู่
const stickerMaxSide = 256;

Future<Directory> stickerFolder() async {
  final dir = Directory(p.join((await getApplicationSupportDirectory()).path, 'stickers'));
  await dir.create(recursive: true);
  return dir;
}

/// ย่อ + แปลงเป็น PNG แล้วเก็บใน [dir] · คืนที่อยู่ไฟล์ใหม่
Future<String> saveStickerImage(String sourcePath, Directory dir) async {
  final bytes = await File(sourcePath).readAsBytes();
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final wide = desc.width >= desc.height;
  final big = (wide ? desc.width : desc.height) > stickerMaxSide;
  final codec = await desc.instantiateCodec(
    targetWidth: big && wide ? stickerMaxSide : null,
    targetHeight: big && !wide ? stickerMaxSide : null,
  );
  final frame = await codec.getNextFrame();
  final png = await frame.image.toByteData(format: ui.ImageByteFormat.png);
  frame.image.dispose();
  codec.dispose();
  desc.dispose();
  buffer.dispose();
  final out = File(p.join(dir.path, 'st_${DateTime.now().microsecondsSinceEpoch}.png'));
  await out.writeAsBytes(png!.buffer.asUint8List());
  return out.path;
}

/// เปิดหน้าต่างเลือกรูป · [many] = เลือกหลายรูป (ทำเป็นชุด) · ยกเลิก = []
Future<List<String>> pickImages({bool many = false}) async {
  final res = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: many);
  return [for (final f in res?.files ?? const <PlatformFile>[]) ?f.path];
}

/// ชื่อสติกเกอร์จากชื่อไฟล์ (ตัดนามสกุล · ยาวสุด 20 ตัว)
String stickerNameFromFile(String path) {
  final n = p.basenameWithoutExtension(path).replaceAll(RegExp(r'[_\-]+'), ' ').trim();
  return n.length > 20 ? n.substring(0, 20) : (n.isEmpty ? 'สติกเกอร์' : n);
}
