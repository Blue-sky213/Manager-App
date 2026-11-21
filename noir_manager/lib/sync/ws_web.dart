library;

import 'dart:async';
import 'dart:js_interop';

@JS('WebSocket')
extension type _WebSocket._(JSObject _) implements JSObject {
  external factory _WebSocket(JSString url);
  external int get readyState;
  external void send(JSString data);
  external void close();
  external set onopen(JSFunction? f);
  external set onmessage(JSFunction? f);
  external set onclose(JSFunction? f);
  external set onerror(JSFunction? f);
}

extension type _MessageEvent._(JSObject _) implements JSObject {
  external JSAny? get data;
}

class WsConn {
  WsConn._(this._ws);
  final _WebSocket _ws;

  static Future<WsConn> connect(String url, {required void Function(String) onMessage, required void Function() onClose}) {
    final done = Completer<WsConn>();
    final ws = _WebSocket(url.toJS);
    final conn = WsConn._(ws);
    var closed = false;
    void fail() {
      if (closed) return;
      closed = true;
      if (!done.isCompleted) {
        done.completeError(StateError('websocket'));
      } else {
        onClose();
      }
    }

    ws.onopen = ((JSAny? _) {
      if (!done.isCompleted) done.complete(conn);
    }).toJS;
    ws.onmessage = ((_MessageEvent e) {
      final d = e.data;
      final v = d?.dartify();
      if (v is String) onMessage(v);
    }).toJS;
    ws.onclose = ((JSAny? _) => fail()).toJS;
    ws.onerror = ((JSAny? _) => fail()).toJS;
    return done.future.timeout(const Duration(seconds: 15));
  }

  void send(String text) {
    if (_ws.readyState == 1) _ws.send(text.toJS);
  }

  Future<void> close() async => _ws.close();
}
