import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Abstraction over the realtime transport so features depend on an interface
/// (and tests can inject a fake). Payloads are plain JSON maps.
abstract class RealtimeClient {
  Future<void> connect(String token);
  void disconnect();
  bool get isConnected;

  /// Stream of payloads for a given server event (e.g. `trip:accepted`).
  Stream<Map<String, dynamic>> on(String event);

  /// Fires whenever the socket reconnects after a drop — the cue to re-sync
  /// any active trip state that may have advanced while disconnected.
  Stream<void> get reconnects;

  /// Send a client event (e.g. `driver:location`).
  void emit(String event, Map<String, dynamic> data);
}

/// socket.io implementation. Per-event broadcast controllers are lazily
/// created and re-bound whenever a new socket connects.
class SocketIoRealtimeClient implements RealtimeClient {
  SocketIoRealtimeClient(this._wsUrl);

  final String _wsUrl;
  io.Socket? _socket;
  final _controllers = <String, StreamController<Map<String, dynamic>>>{};
  final _reconnects = StreamController<void>.broadcast();

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  Stream<void> get reconnects => _reconnects.stream;

  @override
  Future<void> connect(String token) async {
    disconnect();
    final socket = io.io(
      _wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    _socket = socket;
    for (final event in _controllers.keys) {
      _bind(event);
    }

    // Notify subscribers when the socket comes back after a drop so they can
    // re-request server-authoritative state (`trip:sync`).
    socket.onReconnect((_) {
      if (!_reconnects.isClosed) _reconnects.add(null);
    });

    final ready = Completer<void>();
    socket.onConnect((_) {
      if (!ready.isCompleted) ready.complete();
    });
    socket.onConnectError((err) {
      if (!ready.isCompleted) ready.completeError(err ?? 'connect_error');
    });
    socket.connect();
    return ready.future.timeout(
      const Duration(seconds: 8),
      onTimeout: () => throw TimeoutException('socket connect timeout'),
    );
  }

  @override
  Stream<Map<String, dynamic>> on(String event) {
    final controller = _controllers.putIfAbsent(
      event,
      () => StreamController<Map<String, dynamic>>.broadcast(),
    );
    if (_socket != null) _bind(event);
    return controller.stream;
  }

  void _bind(String event) {
    final socket = _socket;
    if (socket == null) return;
    socket.off(event);
    socket.on(event, (data) {
      final controller = _controllers[event];
      if (controller == null) return;
      controller.add(
        data is Map ? Map<String, dynamic>.from(data) : {'data': data},
      );
    });
  }

  @override
  void emit(String event, Map<String, dynamic> data) {
    _socket?.emit(event, data);
  }

  @override
  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
