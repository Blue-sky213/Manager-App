import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:noir_manager/sync/google_login.dart';
import 'package:noir_manager/sync/supabase_api.dart';

String fakeJwt(Map<String, Object> payload) {
  String part(Object o) => base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${part({'alg': 'HS256'})}.${part(payload)}.sig';
}

void main() {
  test('Google: อ่าน token หลัง # → session (id + อีเมลจาก token) · error = ข้อความไทย', () {
    final api = SupabaseApi();
    CloudSession? saved;
    api.onSession = (s) => saved = s;
    final jwt = fakeJwt({'sub': 'u-123', 'email': 'paotvgame@gmail.com'});
    final s = api.adoptFragment('#access_token=$jwt&expires_at=1795160000&expires_in=3600&refresh_token=r1&token_type=bearer');
    expect(s.userId, 'u-123');
    expect(s.email, 'paotvgame@gmail.com');
    expect(s.expiresAt, 1795160000);
    expect(saved?.refreshToken, 'r1');
    expect(() => api.adoptFragment('error=access_denied&error_description=User+cancelled'),
        throwsA(isA<CloudError>().having((e) => e.message, 'msg', contains('User cancelled'))));
    expect(api.googleAuthorizeUrl('http://localhost:43823/').queryParameters,
        {'provider': 'google', 'redirect_to': 'http://localhost:43823/'});
  });

  test('Google บนคอม: เปิดเบราว์เซอร์ → หน้ากลับมาที่ localhost ส่ง token มา → ได้ค่าคืน', () async {
    expect(takeAuthFragment(), isNull);
    String? opened;
    final got = await googleSignInFlow(
      (redirect) => Uri.parse('https://example.supabase.co/auth/v1/authorize?redirect_to=$redirect'),
      (url) async {
        opened = url;
        // จำลองหน้าเล็กในเบราว์เซอร์: โหลดหน้า แล้วส่ง token กลับ
        final c = HttpClient();
        final page = await (await c.getUrl(Uri.parse('http://127.0.0.1:$googleLoopbackPort/'))).close();
        expect(await page.transform(utf8.decoder).join(), contains('location.hash'));
        await (await c.getUrl(Uri.parse('http://127.0.0.1:$googleLoopbackPort/done?access_token=a&refresh_token=b'))).close();
        c.close();
      },
    );
    expect(opened, contains('redirect_to=http://localhost:43823/'));
    expect(got, 'access_token=a&refresh_token=b');
  });
}
