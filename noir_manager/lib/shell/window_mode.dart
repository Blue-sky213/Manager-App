/// เต็มจอไร้ขอบบน Windows (F11 · Esc = ออก) · คุยกับ C++ ผ่านช่อง "noir/window"
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const _channel = MethodChannel('noir/window');

/// เก็บใน setting · เปิดแอปครั้งถัดไปยังเต็มจอ
const fullscreenKey = 'fullscreen';

/// สถานะตอนนี้ (หน้าตั้งค่าฟังเพื่อขยับสวิตช์)
final fullscreen = ValueNotifier<bool>(false);

bool get supportsFullscreen => !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

/// สั่งเต็มจอ / ออก · ระบบที่ไม่รองรับ (มือถือ · เทส) = ไม่ทำอะไร
Future<void> setFullscreen(bool on) async {
  if (!supportsFullscreen) return;
  try {
    await _channel.invokeMethod<bool>('setFullscreen', on);
    fullscreen.value = on;
  } on Exception {
    // ตัว runner รุ่นเก่ายังไม่มีช่องนี้ → ข้าม
  }
}
