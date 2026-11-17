/// เปิดลิงก์ในเบราว์เซอร์ (รอบ 13) โดยไม่เพิ่ม dependency (url_launcher)
/// Windows = ShellExecuteW ผ่าน dart:ffi (วิธีเดียวกับ url_launcher) · mac / linux = คำสั่งของระบบ
/// มือถือ / ระหว่างเทส / เปิดไม่ได้ = คัดลอกลิงก์แทน
library;

import 'dart:ffi';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../widgets/toast.dart';

/// คำสั่งเปิดลิงก์ของระบบ (mac / linux) · null = ไม่ใช้คำสั่ง
/// Windows ไม่ใช้คำสั่ง: rundll32 url.dll ทำให้ Chrome บล็อกไฟล์ติดตั้ง · explorer.exe เปิดเป็นโฟลเดอร์ Error แทนเบราว์เซอร์
(String, List<String>)? openCommand(String url, {String? os}) => switch (os ?? Platform.operatingSystem) {
      'macos' => ('open', [url]),
      'linux' => ('xdg-open', [url]),
      _ => null,
    };

/// ลิงก์ที่เปิดได้ (http / https เท่านั้น · กันคำสั่งแปลก ๆ)
bool isWebLink(String? url) {
  final u = Uri.tryParse(url?.trim() ?? '');
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
}

/// ข้อความแบบ Windows (UTF-16 + 0 ปิดท้าย) · String ของ Dart เป็น UTF-16 อยู่แล้ว
List<int> utf16z(String s) => [...s.codeUnits, 0];

typedef _AllocN = Pointer<Uint16> Function(Uint32 flags, IntPtr bytes);
typedef _AllocD = Pointer<Uint16> Function(int flags, int bytes);
typedef _FreeN = IntPtr Function(Pointer<Uint16> p);
typedef _FreeD = int Function(Pointer<Uint16> p);
typedef _ShellN = IntPtr Function(
    IntPtr hwnd, Pointer<Uint16> op, Pointer<Uint16> file, Pointer<Uint16> params, Pointer<Uint16> dir, Int32 show);
typedef _ShellD = int Function(int hwnd, Pointer<Uint16> op, Pointer<Uint16> file, Pointer<Uint16> params, Pointer<Uint16> dir, int show);

/// เปิดด้วยโปรแกรมเริ่มต้นของ Windows · true = สำเร็จ (ShellExecute คืนค่า > 32)
bool _shellOpenWindows(String url) {
  final k32 = DynamicLibrary.open('kernel32.dll');
  final alloc = k32.lookupFunction<_AllocN, _AllocD>('LocalAlloc');
  final free = k32.lookupFunction<_FreeN, _FreeD>('LocalFree');
  final exec = DynamicLibrary.open('shell32.dll').lookupFunction<_ShellN, _ShellD>('ShellExecuteW');
  Pointer<Uint16> wide(String s) {
    final units = utf16z(s);
    final p = alloc(0x40, units.length * 2); // LPTR = จองแล้วล้างเป็น 0
    p.asTypedList(units.length).setAll(0, units);
    return p;
  }

  final op = wide('open'), file = wide(url);
  try {
    return exec(0, op, file, nullptr, nullptr, 1) > 32; // 1 = SW_SHOWNORMAL
  } finally {
    free(op);
    free(file);
  }
}

Future<void> openLink(BuildContext context, String url) async {
  url = url.trim();
  if (!Platform.environment.containsKey('FLUTTER_TEST') && isWebLink(url)) {
    try {
      if (Platform.isWindows) {
        if (_shellOpenWindows(url)) return;
      } else {
        final cmd = openCommand(url);
        if (cmd != null) {
          await Process.start(cmd.$1, cmd.$2, mode: ProcessStartMode.detached);
          return;
        }
      }
    } catch (_) {/* เปิดไม่ได้ → คัดลอกแทน */}
  }
  await Clipboard.setData(ClipboardData(text: url));
  if (context.mounted) showToast(context, 'คัดลอกลิงก์แล้ว · วางในเบราว์เซอร์ได้เลย');
}
