library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'http_transport.dart' show TransportError;

@JS('fetch')
external JSPromise<_Response> _fetch(JSString url, _Init init);

extension type _Init._(JSObject _) implements JSObject {
  external factory _Init({JSString method, JSAny? headers, JSAny? body});
}

extension type _Response._(JSObject _) implements JSObject {
  external int get status;
  external JSPromise<JSString> text();
  external JSPromise<JSArrayBuffer> arrayBuffer();
}

Future<(int, String)> httpSend(String method, Uri uri, Map<String, String> headers, String? body) async {
  try {
    final res = await _fetch(
      uri.toString().toJS,
      _Init(method: method.toJS, headers: headers.jsify(), body: body?.toJS),
    ).toDart.timeout(const Duration(seconds: 30));
    final text = (await res.text().toDart).toDart;
    return (res.status, text);
  } on TimeoutException {
    throw TransportError('เน็ตช้า · จะลองใหม่');
  } catch (_) {
    // fetch ล้ม = ไม่มีเน็ต / ถูกบล็อก
    throw TransportError('ไม่มีเน็ต · ข้อมูลยังอยู่ในเครื่อง จะซิงก์เมื่อออนไลน์');
  }
}

/// ไฟล์ (รูปสติกเกอร์ · รอบ 20)
Future<(int, Uint8List)> httpSendBytes(String method, Uri uri, Map<String, String> headers, List<int>? body) async {
  try {
    final res = await _fetch(
      uri.toString().toJS,
      _Init(method: method.toJS, headers: headers.jsify(), body: body == null ? null : Uint8List.fromList(body).toJS),
    ).toDart.timeout(const Duration(seconds: 60));
    final buf = (await res.arrayBuffer().toDart).toDart;
    return (res.status, buf.asUint8List());
  } on TimeoutException {
    throw TransportError('เน็ตช้า · จะลองใหม่');
  } catch (_) {
    throw TransportError('ไม่มีเน็ต · จะลองใหม่');
  }
}
