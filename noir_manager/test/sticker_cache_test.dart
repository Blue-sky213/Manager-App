// สติกเกอร์ช่องว่างในสมุด (19 พ.ย.): ถอดรูปเป็นขั้นขนาดเดียวกัน + ล้างรูปที่จำไว้หลังเพิ่ม / ปรับ
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/calendar/sticker_images.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ขนาดถอดรูปปัดเป็นขั้น 64 / 128 / 256 (ไม่เกินไฟล์จริง)', () {
    expect([for (final v in [20.0, 48, 64, 64.5, 120, 128, 129, 400]) stickerCacheWidth(v)], [64, 64, 64, 128, 128, 128, 256, 256]);
  });

  test('ล้างรูปที่จำไว้', () {
    final cache = PaintingBinding.instance.imageCache;
    cache.putIfAbsent('x', () => throw 'unused').ignore;
    refreshStickerImages();
    expect(cache.currentSize, 0);
    expect(cache.liveImageCount, 0);
  });
}
