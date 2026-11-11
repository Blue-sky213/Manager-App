import 'package:flutter/material.dart';

/// โหมด "ทดลองหน้าจออุปกรณ์": บนคอม วาดแอปในกรอบขนาดเท่ามือถือ / แท็บเล็ตจริง
/// ใช้เช็กหน้าตา iPhone / iPad / Android โดยไม่ต้องมีเครื่องจริง (ไม่ใช่ตัวจำลองระบบ — แค่ขนาดจอ + ขอบจอ + ลักษณะ iOS)
class PreviewDevice {
  const PreviewDevice(this.id, this.name, this.size, {this.top = 24, this.bottom = 0, this.ios = false, this.radius = 36});
  final String id;
  final String name;
  final Size size; // แนวตั้ง (logical px)
  final double top; // แถบสถานะ / รอยบาก
  final double bottom; // แถบปัดกลับหน้าหลัก
  final bool ios;
  final double radius;
}

const previewDevices = [
  PreviewDevice('iphone15', 'iPhone 15', Size(393, 852), top: 59, bottom: 34, ios: true, radius: 48),
  PreviewDevice('iphone-se', 'iPhone SE', Size(375, 667), top: 20, ios: true, radius: 20),
  PreviewDevice('ipad', 'iPad 10.9"', Size(820, 1180), top: 24, bottom: 20, ios: true, radius: 24),
  PreviewDevice('ipad-mini', 'iPad mini', Size(744, 1133), top: 24, bottom: 20, ios: true, radius: 24),
  PreviewDevice('android', 'Android มือถือ', Size(412, 915), top: 24, bottom: 16, radius: 36),
  PreviewDevice('android-small', 'Android จอเล็ก', Size(360, 800), top: 24, bottom: 16, radius: 28),
  PreviewDevice('android-tab', 'Android แท็บเล็ต', Size(800, 1280), top: 24, bottom: 16, radius: 20),
];

/// อุปกรณ์ที่เลือก (null = ปิด) · แนวนอนไหม
final devicePreview = ValueNotifier<({String? id, bool landscape})>((id: null, landscape: false));
const devicePreviewKey = 'device_preview'; // เก็บ "id" หรือ "id:land"

PreviewDevice? previewDeviceOf(String? id) => previewDevices.where((d) => d.id == id).firstOrNull;

/// กรอบอุปกรณ์รอบตัวแอป · ย่อให้พอดีหน้าต่างคอม · ส่งขนาดจอ / ขอบจอ / ระบบ iOS ให้แอปข้างใน
class DevicePreviewFrame extends StatelessWidget {
  const DevicePreviewFrame({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: devicePreview,
      builder: (context, v, _) {
        final d = previewDeviceOf(v.id);
        if (d == null) return child;
        final size = v.landscape ? d.size.flipped : d.size;
        final mq = MediaQuery.of(context);
        final pad = v.landscape
            ? EdgeInsets.only(left: d.top, right: d.bottom)
            : EdgeInsets.only(top: d.top, bottom: d.bottom);
        final theme = Theme.of(context);
        return ColoredBox(
          color: const Color(0xFF2A2D33),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(6),
              child: Text(
                '${d.name} · ${size.width.toInt()}×${size.height.toInt()} · จำลองขนาดจอ (ปิดได้ที่ตั้งค่า)',
                style: const TextStyle(color: Color(0xFFB8BEC8), fontSize: 12, decoration: TextDecoration.none),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: FittedBox(
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(d.radius + 10)),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(d.radius),
                      child: SizedBox.fromSize(
                        size: size,
                        child: MediaQuery(
                          data: mq.copyWith(size: size, padding: pad, viewPadding: pad),
                          child: Theme(
                            // iPhone / iPad: การเลื่อน · ปุ่มย้อนกลับ · ฟอนต์ระบบแบบ iOS
                            data: theme.copyWith(platform: d.ios ? TargetPlatform.iOS : TargetPlatform.android),
                            child: child,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}
