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

  /// Live connection state: `true` on (re)connect, `false` on drop. Drives the
  /// "reconnecting" banner so the user knows when live updates are paused.
  Stream<bool> get connection;

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
  final _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => _socket?.connected ?? false;

  @override
  Stream<void> get reconnects => _reconnects.stream;

  @override
  Stream<bool> get connection => _connection.stream;

  void _emitConnection(bool up) {
    if (!_connection.isClosed) _connection.add(up);
  }

  @override
  Future<void> connect(String token) async {
    disconnect();
    final socket = io.io(
      _wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          // Explicit reconnection policy: keep retrying with a capped backoff
          // rather than relying on library defaults, so a flaky link recovers.
          .enableReconnection()
          .setReconnectionAttempts(1 << 30)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(8000)
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
      _emitConnection(true);
    });
    // Surface every up/down edge for the connection banner.
    socket.onDisconnect((_) => _emitConnection(false));
    socket.onConnectError((_) => _emitConnection(false));

    final ready = Completer<void>();
    socket.onConnect((_) {
      _emitConnection(true);
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
    // Disposing an already-closing socket can throw WebSocketConnectionClosed
    // from deep in the transport; that's benign here (we're tearing it down).
    try {
      _socket?.dispose();
    } catch (_) {
      // ignore — the socket is going away regardless.
    }
    _socket = null;
  }
}
