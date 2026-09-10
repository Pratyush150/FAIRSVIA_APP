import 'dart:async';
import 'dart:math' as math;

import 'package:socket_io_client/socket_io_client.dart' as io;

/// Abstraction over the realtime transport so features depend on an interface
/// (and tests can inject a fake). Payloads are plain JSON maps.
abstract class RealtimeClient {
  Future<void> connect(String token);
  void disconnect();
  bool get isConnected;

  /// Stream of payloads for a given server event (e.g. `trip:accepted`).
  ///
  /// Safe to call before [connect]: subscriptions are bound to every socket
  /// that is subsequently created, so a failed or slow first connect never
  /// loses listeners.
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
///
/// Recovery model (verified against socket_io_client 3.1.6):
/// * Transport drops (server restart, network blip) are retried by socket.io's
///   Manager with the backoff configured below, and `auth` is re-sent on every
///   attempt, so no client-side work is needed beyond surfacing the edges.
/// * socket.io deliberately does NOT retry two cases, which used to leave the
///   app on "Reconnecting…" until relaunch: a server-initiated disconnect
///   (`io server disconnect` destroys the socket) and a namespace-level
///   `connect_error` (the server refused our CONNECT, e.g. an auth/presence
///   check right after it came back up). Both are retried here explicitly with
///   a capped backoff.
class SocketIoRealtimeClient implements RealtimeClient {
  SocketIoRealtimeClient(this._wsUrl);

  final String _wsUrl;
  io.Socket? _socket;
  final _controllers = <String, StreamController<Map<String, dynamic>>>{};
  final _reconnects = StreamController<void>.broadcast();
  final _connection = StreamController<bool>.broadcast();

  /// The `connect()` currently waiting for its socket to come up, if any. A
  /// newer `connect()`/`disconnect()` fails it immediately (see [disconnect])
  /// instead of leaving it to hit the 8 s timeout long after the replacement
  /// socket is already live — which used to surface as a stale `connected:
  /// false` that stuck the "Reconnecting…" banner on.
  Completer<void>? _pending;

  /// Our own retry for the cases socket.io won't retry (see class doc).
  Timer? _retry;
  int _retryAttempt = 0;

  static const _retryBase = Duration(seconds: 1);
  static const _retryMax = Duration(seconds: 8);

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
          // socket.io caches Manager+Socket per URL (multiplexing); a cached
          // socket keeps the auth it was created with, so a sign-out → sign-in
          // as a different user, or a reconnect with a rotated token, would
          // silently re-send the OLD token. Force a genuinely new connection
          // per connect() call. NB: this must be `enableForceNew()` —
          // socket_io_client 3.1.6's `disableMultiplex()` merely *removes* the
          // `multiplex` key, and `_lookup` only bypasses its cache on
          // `forceNew == true` / `multiplex == false`, so the previous
          // `disableMultiplex()` still handed back the cached socket (proven by
          // realtime_client_test's identity-leak case).
          .enableForceNew()
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

    // Overlapping connect() calls: once this socket has been replaced, none of
    // its lifecycle events may touch shared state (the `connection` stream in
    // particular), otherwise a dying socket A reports "down" after the live
    // socket B reported "up".
    bool live() => identical(_socket, socket);

    final ready = Completer<void>();
    _pending = ready;
    // `connect` fires on the first connection AND after every recovery
    // (socket.io re-sends CONNECT with our auth on each transport reopen), so
    // derive both the banner and the "re-sync now" cue from it. This also
    // covers our own explicit retries below, which socket.io's 'reconnect'
    // event would not report.
    var everConnected = false;
    socket.onConnect((_) {
      if (!live()) return;
      _retry?.cancel();
      _retryAttempt = 0;
      _emitConnection(true);
      if (everConnected && !_reconnects.isClosed) _reconnects.add(null);
      everConnected = true;
      if (!ready.isCompleted) ready.complete();
    });
    socket.onDisconnect((reason) {
      if (!live()) return;
      _emitConnection(false);
      // socket.io destroys the socket on a server-initiated disconnect and
      // never reconnects it (the server "meant it"). For us the server
      // restarting or shedding a stale session is exactly when we want to
      // come back, so reconnect explicitly.
      if (reason == 'io server disconnect') _scheduleRetry(socket);
    });
    socket.onConnectError((err) {
      if (!live()) return;
      _emitConnection(false);
      if (!ready.isCompleted) ready.completeError(err ?? 'connect_error');
      // Transport-level failures are already being retried by the Manager
      // (`reconnecting`). A namespace-level rejection leaves the engine open
      // but the socket unconnected, and socket.io never retries that.
      if (!socket.io.reconnecting) _scheduleRetry(socket);
    });
    socket.connect();
    try {
      await ready.future.timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw TimeoutException('socket connect timeout'),
      );
    } finally {
      if (identical(_pending, ready)) _pending = null;
    }
  }

  /// Re-issue CONNECT on [socket] after a backed-off delay (1 s doubling to a
  /// cap of 8 s), unless it has been replaced or has connected meanwhile.
  void _scheduleRetry(io.Socket socket) {
    _retry?.cancel();
    final factor = math.min(1 << math.min(_retryAttempt, 3), 8);
    final delay = _retryBase * factor;
    _retryAttempt++;
    _retry = Timer(delay > _retryMax ? _retryMax : delay, () {
      if (!identical(_socket, socket) || socket.connected) return;
      socket.connect();
    });
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
    _retry?.cancel();
    _retry = null;
    _retryAttempt = 0;
    // Fail any connect() still waiting on the socket we're about to tear down,
    // so its caller learns right away rather than after the full timeout.
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(
        StateError('socket replaced or closed before it connected'),
      );
    }
    // Detach BEFORE disposing: dispose() fires the socket's own `disconnect`
    // event synchronously, and the `live()` guard drops it as stale.
    final socket = _socket;
    _socket = null;
    // Disposing an already-closing socket can throw WebSocketConnectionClosed
    // from deep in the transport; that's benign here (we're tearing it down).
    try {
      socket?.dispose();
    } catch (_) {
      // ignore — the socket is going away regardless.
    }
  }
}
