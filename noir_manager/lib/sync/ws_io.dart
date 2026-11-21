library;

import 'dart:async';
import 'dart:io';

class WsConn {
  WsConn._(this._ws);
  final WebSocket _ws;

  static Future<WsConn> connect(String url, {required void Function(String) onMessage, required void Function() onClose}) async {
    final ws = await WebSocket.connect(url).timeout(const Duration(seconds: 15));
    ws.listen((m) => onMessage('$m'), onDone: onClose, onError: (_) => onClose(), cancelOnError: true);
    return WsConn._(ws);
  }

  void send(String text) => _ws.add(text);
  Future<void> close() => _ws.close();
}
