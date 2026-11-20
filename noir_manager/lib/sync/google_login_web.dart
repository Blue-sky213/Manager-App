library;

import 'dart:js_interop';

@JS('window.location.href')
external JSString get _href;

@JS('window.location.hash')
external JSString get _hash;

@JS('window.location.assign')
external void _assign(JSString url);

@JS('window.history.replaceState')
external void _replaceState(JSAny? data, JSString title, JSString url);

/// กลับมาจาก Google: token อยู่หลัง # → เก็บไว้ + ล้างออกจากแถบที่อยู่ (ทำก่อน runApp)
String? takeAuthFragment() {
  final h = _hash.toDart;
  if (!h.contains('access_token') && !h.contains('error_description')) return null;
  final clean = _href.toDart.split('#').first;
  _replaceState(null, ''.toJS, clean.toJS);
  return h.substring(1);
}

/// เว็บ: เปลี่ยนหน้าไป Google เลย (หน้านี้จะโหลดใหม่ตอนกลับมา) → คืน null
Future<String?> googleSignInFlow(Uri Function(String redirectTo) urlFor, Future<void> Function(String url) open) async {
  final back = _href.toDart.split('#').first;
  _assign(urlFor(back).toString().toJS);
  return null;
}
