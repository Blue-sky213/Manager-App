import 'dart:io';
import 'dart:typed_data';
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

/// พอดีอัตโนมัติ (รอบ 8B): หากรอบภาพส่วนที่ไม่ใส (alpha > 16) จากพิกเซล RGBA [w]×[h]
/// แล้วคืน (ซูม, dx, dy) ที่ทำให้ส่วนนั้นเต็ม [fill] ของกรอบ และอยู่กลาง · ภาพใสทั้งภาพ = null
/// ภาพวาดใน BoxFit.contain → ด้านยาวเต็มกรอบ จึงคิดเทียบกับด้านยาว
(double, double, double)? fitFromAlpha(Uint8List rgba, int w, int h, {double fill = 0.8}) {
  var l = w, t = h, r = -1, b = -1;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      if (rgba[(y * w + x) * 4 + 3] > 16) {
        if (x < l) l = x;
        if (x > r) r = x;
        if (y < t) t = y;
        if (y > b) b = y;
      }
    }
  }
  if (r < l || b < t) return null;
  final side = (w > h ? w : h).toDouble();
  final bw = (r - l + 1) / side, bh = (b - t + 1) / side;
  final scale = (fill / (bw > bh ? bw : bh)).clamp(0.5, 2.5);
  final dx = (-(((l + r + 1) / 2 - w / 2) / side) * scale).clamp(-0.5, 0.5);
  final dy = (-(((t + b + 1) / 2 - h / 2) / side) * scale).clamp(-0.5, 0.5);
  double r3(double v) => (v * 1000).roundToDouble() / 1000;
  return (r3(scale), r3(dx), r3(dy));
}

/// อ่านรูปสติกเกอร์ (ย่อเหลือด้านยาว 128 ก่อน · เร็ว) แล้วคิดค่าพอดีอัตโนมัติ · อ่านไม่ได้ = null
Future<(double, double, double)?> autoFitImage(String path) async {
  try {
    final bytes = await File(path).readAsBytes();
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final desc = await ui.ImageDescriptor.encoded(buffer);
    final wide = desc.width >= desc.height;
    final codec = await desc.instantiateCodec(targetWidth: wide ? 128 : null, targetHeight: wide ? null : 128);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final w = img.width, h = img.height;
    img.dispose();
    codec.dispose();
    desc.dispose();
    buffer.dispose();
    if (data == null) return null;
    return fitFromAlpha(data.buffer.asUint8List(), w, h);
  } catch (_) {
    return null;
  }
}
