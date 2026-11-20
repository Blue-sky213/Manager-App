library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'http_transport.dart' show TransportError;

final _client = HttpClient();

Future<(int, String)> httpSend(String method, Uri uri, Map<String, String> headers, String? body) async {
  try {
    final req = await _client.openUrl(method, uri).timeout(const Duration(seconds: 20));
    headers.forEach(req.headers.set);
    if (body != null) req.add(utf8.encode(body));
    final res = await req.close().timeout(const Duration(seconds: 30));
    final text = await res.transform(utf8.decoder).join();
    return (res.statusCode, text);
  } on SocketException {
    throw TransportError('ไม่มีเน็ต · ข้อมูลยังอยู่ในเครื่อง จะซิงก์เมื่อออนไลน์');
  } on HandshakeException {
    throw TransportError('เชื่อมต่อไม่ปลอดภัย (เช็กวันเวลาเครื่อง)');
  } on HttpException {
    throw TransportError('เชื่อมต่อขาดกลางทาง · จะลองใหม่');
  } on TimeoutException {
    throw TransportError('เน็ตช้า · จะลองใหม่');
  }
}

/// ไฟล์ (รูปสติกเกอร์ · รอบ 20)
Future<(int, Uint8List)> httpSendBytes(String method, Uri uri, Map<String, String> headers, List<int>? body) async {
  try {
    final req = await _client.openUrl(method, uri).timeout(const Duration(seconds: 20));
    headers.forEach(req.headers.set);
    if (body != null) req.add(body);
    final res = await req.close().timeout(const Duration(seconds: 60));
    final out = BytesBuilder(copy: false);
    await for (final c in res) {
      out.add(c);
    }
    return (res.statusCode, out.takeBytes());
  } on SocketException {
    throw TransportError('ไม่มีเน็ต · จะลองใหม่');
  } on HandshakeException {
    throw TransportError('เชื่อมต่อไม่ปลอดภัย (เช็กวันเวลาเครื่อง)');
  } on HttpException {
    throw TransportError('เชื่อมต่อขาดกลางทาง · จะลองใหม่');
  } on TimeoutException {
    throw TransportError('เน็ตช้า · จะลองใหม่');
  }
}
