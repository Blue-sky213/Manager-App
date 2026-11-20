/// คุยกับ Supabase ตรง ๆ ผ่าน HTTP (รอบ 16) · ไม่เพิ่ม package
/// - เข้าระบบ: /auth/v1 (อีเมล + รหัสผ่าน · Google ทำต่อรอบหน้า)
/// - ข้อมูล: /rest/v1/sync_rows (RLS: เห็นเฉพาะของบัญชีตัวเอง)
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'merge.dart';
import 'sync_remote.dart';

/// โปรเจกต์ Supabase ของนัวร์ (publishable key ฝังในแอปได้ · ความปลอดภัยมาจาก RLS)
const cloudUrl = 'https://wqrutkywwkjsrjlhbuyu.supabase.co';
const cloudKey = 'sb_publishable_TfAn5d4m70-2bnQWarVWZg_7W5Nk8vK';

class CloudSession {
  const CloudSession({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
    required this.email,
  });

  final String accessToken;
  final String refreshToken;

  /// วินาที (epoch)
  final int expiresAt;
  final String userId;
  final String email;

  factory CloudSession.fromAuth(Map<String, dynamic> j) {
    final user = (j['user'] as Map).cast<String, dynamic>();
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return CloudSession(
      accessToken: j['access_token'] as String,
      refreshToken: j['refresh_token'] as String,
      expiresAt: (j['expires_at'] as num?)?.toInt() ?? now + ((j['expires_in'] as num?)?.toInt() ?? 3600),
      userId: user['id'] as String,
      email: (user['email'] as String?) ?? '',
    );
  }

  factory CloudSession.fromJson(Map<String, dynamic> j) => CloudSession(
        accessToken: j['a'] as String,
        refreshToken: j['r'] as String,
        expiresAt: (j['e'] as num).toInt(),
        userId: j['u'] as String,
        email: j['m'] as String,
      );

  Map<String, Object> toJson() => {'a': accessToken, 'r': refreshToken, 'e': expiresAt, 'u': userId, 'm': email};

  bool get expiringSoon => DateTime.now().millisecondsSinceEpoch ~/ 1000 > expiresAt - 60;
}

/// ข้อผิดพลาดที่อ่านเข้าใจ (ภาษาไทย)
class CloudError implements Exception {
  CloudError(this.message, {this.status});
  final String message;
  final int? status;

  bool get offline => status == null;
  @override
  String toString() => message;
}

String _thaiAuthError(int status, String body) {
  final b = body.toLowerCase();
  if (b.contains('invalid login credentials')) return 'อีเมลหรือรหัสผ่านไม่ถูก';
  if (b.contains('email not confirmed')) return 'ยังไม่ได้ยืนยันอีเมล · เปิดลิงก์ในอีเมลก่อน';
  if (b.contains('already registered') || b.contains('already exists')) return 'อีเมลนี้สมัครแล้ว · กด "เข้าสู่ระบบ" แทน';
  if (b.contains('password') && (b.contains('6') || b.contains('weak') || b.contains('short'))) {
    return 'รหัสผ่านสั้นไป (อย่างน้อย 6 ตัว)';
  }
  if (b.contains('rate limit') || status == 429) return 'ลองบ่อยไป · รอสักครู่แล้วลองใหม่';
  if (b.contains('invalid') && b.contains('email')) return 'รูปแบบอีเมลไม่ถูก';
  return 'ผิดพลาด ($status)';
}

class SupabaseApi {
  SupabaseApi({this.url = cloudUrl, this.key = cloudKey, HttpClient? client}) : _http = client ?? HttpClient();

  final String url;
  final String key;
  final HttpClient _http;

  CloudSession? session;

  /// เรียกหลังได้ session ใหม่ (เก็บลงเครื่อง)
  void Function(CloudSession?)? onSession;

  Future<(int, String)> _send(String method, String path, {Object? body, Map<String, String> headers = const {}, bool auth = false}) async {
    try {
      final req = await _http.openUrl(method, Uri.parse('$url$path')).timeout(const Duration(seconds: 20));
      req.headers.set('apikey', key);
      req.headers.set('Authorization', 'Bearer ${auth ? session!.accessToken : key}');
      req.headers.contentType = ContentType.json;
      headers.forEach(req.headers.set);
      if (body != null) req.add(utf8.encode(jsonEncode(body)));
      final res = await req.close().timeout(const Duration(seconds: 30));
      final text = await res.transform(utf8.decoder).join();
      return (res.statusCode, text);
    } on SocketException {
      throw CloudError('ไม่มีเน็ต · ข้อมูลยังอยู่ในเครื่อง จะซิงก์เมื่อออนไลน์');
    } on HandshakeException {
      throw CloudError('เชื่อมต่อไม่ปลอดภัย (เช็กวันเวลาเครื่อง)');
    } on HttpException {
      throw CloudError('เชื่อมต่อขาดกลางทาง · จะลองใหม่');
    } on TimeoutException {
      throw CloudError('เน็ตช้า · จะลองใหม่');
    }
  }

  Future<CloudSession> _auth(String path, Map<String, Object> body) async {
    final (code, text) = await _send('POST', path, body: body);
    if (code >= 300) throw CloudError(_thaiAuthError(code, text), status: code);
    final s = CloudSession.fromAuth((jsonDecode(text) as Map).cast<String, dynamic>());
    session = s;
    onSession?.call(s);
    return s;
  }

  Future<CloudSession> signIn(String email, String password) =>
      _auth('/auth/v1/token?grant_type=password', {'email': email.trim(), 'password': password});

  /// สมัคร · null = ต้องยืนยันอีเมลก่อน (Supabase ส่งลิงก์ไปที่อีเมล)
  Future<CloudSession?> signUp(String email, String password) async {
    final (code, text) = await _send('POST', '/auth/v1/signup', body: {'email': email.trim(), 'password': password});
    if (code >= 300) throw CloudError(_thaiAuthError(code, text), status: code);
    final j = (jsonDecode(text) as Map).cast<String, dynamic>();
    if (j['access_token'] == null) return null;
    final s = CloudSession.fromAuth(j);
    session = s;
    onSession?.call(s);
    return s;
  }

  Future<void> refresh() async {
    final s = session;
    if (s == null) throw CloudError('ยังไม่เข้าระบบ', status: 401);
    try {
      await _auth('/auth/v1/token?grant_type=refresh_token', {'refresh_token': s.refreshToken});
    } on CloudError catch (e) {
      if (e.status != null && e.status! >= 400 && e.status! < 500) {
        session = null;
        onSession?.call(null);
        throw CloudError('หมดเวลาเข้าระบบ · เข้าระบบใหม่อีกครั้ง', status: 401);
      }
      rethrow;
    }
  }

  Future<void> signOut() async {
    final s = session;
    session = null;
    onSession?.call(null);
    if (s == null) return;
    try {
      await _send('POST', '/auth/v1/logout', headers: {'Authorization': 'Bearer ${s.accessToken}'});
    } catch (_) {
      // ออกจากเครื่องนี้แล้ว · เซิร์ฟเวอร์ไม่ตอบก็ไม่เป็นไร
    }
  }

  /// เรียก REST แบบเข้าระบบแล้ว · token ใกล้หมด/หมด → ต่ออายุแล้วลองใหม่ 1 ครั้ง
  Future<String> rest(String method, String path, {Object? body, Map<String, String> headers = const {}}) async {
    if (session == null) throw CloudError('ยังไม่เข้าระบบ', status: 401);
    if (session!.expiringSoon) await refresh();
    var (code, text) = await _send(method, path, body: body, headers: headers, auth: true);
    if (code == 401) {
      await refresh();
      (code, text) = await _send(method, path, body: body, headers: headers, auth: true);
    }
    if (code >= 300) {
      if (text.contains('sync_rows') && (code == 404 || text.contains('does not exist'))) {
        throw CloudError('ยังไม่ได้สร้างตารางบน Supabase (รัน SQL ใน docs/supabase/001_sync.sql)', status: code);
      }
      throw CloudError('ซิงก์ไม่สำเร็จ ($code)', status: code);
    }
    return text;
  }
}

/// ที่เก็บกลางบน Supabase
class SupabaseRemote implements SyncRemote {
  SupabaseRemote(this.api, {this.device = ''});
  final SupabaseApi api;
  final String device;

  static const _page = 1000;

  @override
  Future<List<RemoteRow>> pull(int afterRev) async {
    final out = <RemoteRow>[];
    var after = afterRev;
    while (true) {
      final text = await api.rest(
        'GET',
        '/rest/v1/sync_rows?select=tbl,row_id,vals,stamps,deleted_at,rev&rev=gt.$after&order=rev.asc&limit=$_page',
      );
      final list = jsonDecode(text) as List;
      for (final j in list.cast<Map>()) {
        final rev = (j['rev'] as num).toInt();
        out.add(RemoteRow(
          SyncRow(
            table: j['tbl'] as String,
            id: j['row_id'] as String,
            values: (j['vals'] as Map).cast<String, Object?>(),
            stamps: (j['stamps'] as Map).map((k, v) => MapEntry(k as String, (v as num).toInt())),
            deletedAt: (j['deleted_at'] as num?)?.toInt(),
          ),
          rev,
        ));
        if (rev > after) after = rev;
      }
      if (list.length < _page) break;
    }
    return out;
  }

  @override
  Future<void> push(List<SyncRow> rows) async {
    final uid = api.session?.userId;
    for (var i = 0; i < rows.length; i += 500) {
      final chunk = rows.sublist(i, i + 500 > rows.length ? rows.length : i + 500);
      await api.rest(
        'POST',
        '/rest/v1/sync_rows?on_conflict=user_id,tbl,row_id',
        headers: {'Prefer': 'resolution=merge-duplicates,return=minimal'},
        body: [
          for (final r in chunk)
            {
              'user_id': uid,
              'tbl': r.table,
              'row_id': r.id,
              'vals': r.values,
              'stamps': r.stamps,
              'deleted_at': r.deletedAt,
              'device': device,
            },
        ],
      );
    }
  }
}
