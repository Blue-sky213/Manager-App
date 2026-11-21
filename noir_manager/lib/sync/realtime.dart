/// สัญญาณสดจากบัญชี (รอบ 21 · แบบ Notion): เครื่องอื่นบันทึก → ได้ยินทันที → ดึงของใหม่
/// Supabase Realtime (Phoenix channel) ฟังตาราง sync_rows · RLS = ได้ยินเฉพาะของบัญชีตัวเอง
/// หลุด = ต่อใหม่เองแบบรอนานขึ้นเรื่อย ๆ (สูงสุด 1 นาที) · ระหว่างนั้นยังดึงตามรอบปกติ
library;

import 'dart:async';
import 'dart:convert';

import 'supabase_api.dart';
import 'ws.dart';

class RealtimeListener {
  RealtimeListener(this.api, {required this.device, required this.onChange});

  final SupabaseApi api;

  /// เครื่องนี้ (ไม่ต้องดึงซ้ำเมื่อได้ยินเสียงตัวเอง)
  final String device;
  final void Function() onChange;

  WsConn? _ws;
  Timer? _beat;
  Timer? _retry;
  var _ref = 0;
  var _wait = 2;
  bool _stopped = true;

  /// ต่ออยู่ไหม (ไว้โชว์สถานะ / ลดรอบดึง)
  bool get connected => _ws != null;

  Future<void> start() async {
    _stopped = false;
    await _connect();
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    _beat?.cancel();
    final w = _ws;
    _ws = null;
    await w?.close();
  }

  /// token ใหม่ (ต่ออายุแล้ว) → ส่งให้ช่องที่ฟังอยู่
  void updateToken() {
    final t = api.session?.accessToken;
    if (t == null) return;
    _send({'topic': 'realtime:sync', 'event': 'access_token', 'payload': {'access_token': t}});
  }

  void _send(Map<String, Object?> m) => _ws?.send(jsonEncode({...m, 'ref': '${++_ref}'}));

  Future<void> _connect() async {
    if (_stopped || api.session == null) return;
    final url = '${api.url.replaceFirst('http', 'ws')}/realtime/v1/websocket?apikey=${api.key}&vsn=1.0.0';
    try {
      if (api.session!.expiringSoon) await api.refresh();
      _ws = await WsConn.connect(url, onMessage: _onMessage, onClose: _onClose);
      _wait = 2;
      _send({
        'topic': 'realtime:sync',
        'event': 'phx_join',
        'join_ref': '1',
        'payload': {
          'config': {
            'broadcast': {'self': false},
            'presence': {'key': ''},
            'postgres_changes': [
              {'event': '*', 'schema': 'public', 'table': 'sync_rows'},
            ],
            'private': false,
          },
          'access_token': api.session?.accessToken,
        },
      });
      _beat?.cancel();
      _beat = Timer.periodic(const Duration(seconds: 25), (_) {
        _send({'topic': 'phoenix', 'event': 'heartbeat', 'payload': {}});
      });
    } catch (_) {
      _ws = null;
      _schedule();
    }
  }

  void _onMessage(String text) {
    try {
      final m = jsonDecode(text) as Map;
      if (m['event'] != 'postgres_changes') return;
      final rec = ((m['payload'] as Map?)?['data'] as Map?)?['record'] as Map?;
      if (rec != null && rec['device'] == device) return; // เสียงตัวเอง
      onChange();
    } catch (_) {}
  }

  void _onClose() {
    _ws = null;
    _beat?.cancel();
    _schedule();
  }

  void _schedule() {
    if (_stopped) return;
    _retry?.cancel();
    _retry = Timer(Duration(seconds: _wait), _connect);
    _wait = (_wait * 2).clamp(2, 60);
  }
}
