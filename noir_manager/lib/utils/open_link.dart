/// เปิดลิงก์ในเบราว์เซอร์ (รอบ 13) โดยไม่เพิ่ม dependency (url_launcher)
/// คอม = เรียกคำสั่งของระบบ · มือถือ / ระหว่างเทส / เปิดไม่ได้ = คัดลอกลิงก์แทน
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/toast.dart';

/// คำสั่งเปิดลิงก์ของระบบ · null = ไม่รองรับ (มือถือ)
(String, List<String>)? openCommand(String url, {String? os}) => switch (os ?? Platform.operatingSystem) {
      'windows' => ('rundll32', ['url.dll,FileProtocolHandler', url]),
      'macos' => ('open', [url]),
      'linux' => ('xdg-open', [url]),
      _ => null,
    };

/// ลิงก์ที่เปิดได้ (http / https เท่านั้น · กันคำสั่งแปลก ๆ)
bool isWebLink(String? url) {
  final u = Uri.tryParse(url?.trim() ?? '');
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
}

Future<void> openLink(BuildContext context, String url) async {
  url = url.trim();
  final cmd = Platform.environment.containsKey('FLUTTER_TEST') || !isWebLink(url) ? null : openCommand(url);
  if (cmd != null) {
    try {
      await Process.start(cmd.$1, cmd.$2, mode: ProcessStartMode.detached);
      return;
    } catch (_) {/* เปิดไม่ได้ → คัดลอกแทน */}
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) showToast(context, 'คัดลอกลิงก์แล้ว · วางในเบราว์เซอร์ได้เลย');
}
