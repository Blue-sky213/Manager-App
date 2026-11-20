/// เปิดลิงก์บนเว็บ (รอบ 17): แท็บใหม่ของเบราว์เซอร์ · ไม่ใช้ dart:ffi / dart:io
library;

import 'dart:js_interop';

import 'package:flutter/widgets.dart';

@JS('window.open')
external JSAny? _windowOpen(JSString url, JSString target);

(String, List<String>)? openCommand(String url, {String? os}) => null;

bool isWebLink(String? url) {
  final u = Uri.tryParse(url?.trim() ?? '');
  return u != null && (u.scheme == 'http' || u.scheme == 'https') && u.host.isNotEmpty;
}

List<int> utf16z(String s) => [...s.codeUnits, 0];

Future<void> openLink(BuildContext context, String url) async {
  url = url.trim();
  if (isWebLink(url)) _windowOpen(url.toJS, '_blank'.toJS);
}
