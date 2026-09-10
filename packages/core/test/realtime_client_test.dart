import 'dart:convert';
import 'dart:io';

import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

/// A minimal socket.io v4 server (engine.io v4, websocket transport only) on
/// loopback, so these tests drive the REAL socket_io_client through real
/// drops and restarts instead of a fake transport.
///
/// Wire format handled:
///   engine.io OPEN  -> `0{...}`        (server -> client, on upgrade)
///   socket.io CONNECT `40{auth}`       (client -> server, with our token)
///   socket.io CONNECT ack `40{"sid"}`  (server -> client)
///   socket.io CONNECT_ERROR `44{...}`  (server -> client, rejected)
///   socket.io DISCONNECT `41`          (server -> client, "io server disconnect")
///   socket.io EVENT `42[name,data]`
class _FakeSocketIoServer {
  HttpServer? _server;
  final clients = <WebSocket>[];

  /// Every auth payload received in a CONNECT, in order (one per handshake).
  final auths = <Map<String, dynamic>>[];

  /// Reply to the next N CONNECTs with CONNECT_ERROR instead of an ack.
  int rejectNextConnects = 0;

  /// When false the server never acks CONNECT (client's connect() hangs).
  bool ackConnect = true;

  int get port => _server!.port;
  String get url => 'http://127.0.0.1:$port';

  Future<void> start({int port = 0}) async {
    HttpServer? server;
    // A restart on the same port can race the previous listener's teardown.
    for (var attempt = 0; server == null; attempt++) {
      try {
        server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
      } on SocketException {
        if (attempt >= 20) rethrow;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
    _server = server;
    server.listen(_handle);
  }

  Future<void> _handle(HttpRequest req) async {
    if (!WebSocketTransformer.isUpgradeRequest(req)) {
      req.response.statusCode = HttpStatus.notFound;
      await req.response.close();
      return;
    }
    final ws = await WebSocketTransformer.upgrade(req);
    clients.add(ws);
    ws.add(
      '0${jsonEncode({'sid': 'eio${auths.length}', 'upgrades': <String>[], 'pingInterval': 25000, 'pingTimeout': 20000, 'maxPayload': 1000000})}',
    );
    ws.listen(
      (msg) {
        if (msg is! String) return;
        if (msg.startsWith('40')) {
          final raw = msg.substring(2);
          auths.add(
            raw.isEmpty
                ? <String, dynamic>{}
                : Map<String, dynamic>.from(jsonDecode(raw) as Map),
          );
          if (rejectNextConnects > 0) {
            rejectNextConnects--;
            ws.add('44${jsonEncode({'message': 'unauthorized'})}');
          } else if (ackConnect) {
            ws.add('40${jsonEncode({'sid': 'sio${auths.length}'})}');
          }
        } else if (msg == '2') {
          ws.add('3');
        }
      },
      onDone: () => clients.remove(ws),
      onError: (_) => clients.remove(ws),
    );
  }

  void emitAll(String event, Map<String, dynamic> data) {
    for (final c in clients) {
      c.add('42${jsonEncode([event, data])}');
    }
  }

  /// Server-initiated socket.io disconnect (`io server disconnect` on the
  /// client), keeping the transport up — as a server does when it kicks a
  /// session.
  void kickAll() {
    for (final c in clients) {
      c.add('41');
    }
  }

  /// Tear the server down as a crash/restart would: every live socket is
  /// closed and the port stops listening.
  Future<void> stop() async {
    for (final c in clients.toList()) {
      await c.close();
    }
    clients.clear();
    await _server?.close(force: true);
    _server = null;
  }
}

/// Poll until [cond] holds or [timeout] elapses (real timers — the client's
/// reconnect backoff is wall-clock based).
Future<void> _waitFor(
  bool Function() cond, {
  Duration timeout = const Duration(seconds: 8),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('condition not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}

void main() {
  late _FakeSocketIoServer server;
  late SocketIoRealtimeClient client;
  late List<bool> edges;
  late int reconnects;
  late List<Map<String, dynamic>> offers;

  setUp(() async {
    server = _FakeSocketIoServer();
    await server.start();
    client = SocketIoRealtimeClient(server.url);
    edges = [];
    reconnects = 0;
    offers = [];
    client.connection.listen(edges.add);
    client.reconnects.listen((_) => reconnects++);
    // Subscribed BEFORE connect() — must survive every socket that follows.
    client.on('trip:offer').listen(offers.add);
  });

  tearDown(() async {
    client.disconnect();
    await server.stop();
  });

  test(
    'delivers events on a subscription registered before connect()',
    () async {
      await client.connect('tok-1');
      expect(client.isConnected, isTrue);
      expect(edges, [true]);
      expect(server.auths.single['token'], 'tok-1');

      server.emitAll('trip:offer', {'tripId': 't1'});
      await _waitFor(() => offers.isNotEmpty);
      expect(offers.single['tripId'], 't1');
      expect(reconnects, 0);
    },
  );

  // Live repro: the dev backend (nest --watch) restarted under two connected
  // apps and both sat on "Reconnecting…" until relaunch. This drives the real
  // client through a server that dies (sockets closed, port gone) and comes
  // back on the same port, and asserts the banner flips back, a re-sync cue
  // fires, the token is re-sent, and pre-existing handlers still receive.
  test(
    'recovers from a server restart: connected false→true, handlers live',
    () async {
      await client.connect('tok-1');
      final port = server.port;

      await server.stop();
      await _waitFor(() => edges.contains(false));
      expect(client.isConnected, isFalse);

      // Down for a bit so at least one reconnect attempt is refused first.
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      await server.start(port: port);

      await _waitFor(() => edges.last == true);
      expect(client.isConnected, isTrue);
      expect(reconnects, 1, reason: 'exactly one re-sync cue per recovery');
      expect(
        server.auths.last['token'],
        'tok-1',
        reason: 'auth must be re-sent on the reconnect handshake',
      );

      server.emitAll('trip:offer', {'tripId': 't2'});
      await _waitFor(() => offers.isNotEmpty);
      expect(offers.single['tripId'], 't2');
    },
  );

  // socket.io itself never reconnects after `io server disconnect`.
  test(
    'reconnects after a server-initiated disconnect (io server disconnect)',
    () async {
      await client.connect('tok-1');
      server.kickAll();
      await _waitFor(() => edges.contains(false));
      expect(client.isConnected, isFalse);

      await _waitFor(() => edges.last == true);
      expect(client.isConnected, isTrue);
      expect(reconnects, 1);
      expect(server.auths.length, 2);

      server.emitAll('trip:offer', {'tripId': 't3'});
      await _waitFor(() => offers.isNotEmpty);
      expect(offers.single['tripId'], 't3');
    },
  );

  // socket.io itself never retries a namespace-level CONNECT rejection.
  test(
    'retries after the server rejects the handshake (connect_error)',
    () async {
      server.rejectNextConnects = 1;
      await expectLater(client.connect('tok-1'), throwsA(anything));
      expect(edges, [false]);

      await _waitFor(() => edges.last == true);
      expect(client.isConnected, isTrue);
      expect(server.auths.length, 2);

      server.emitAll('trip:offer', {'tripId': 't4'});
      await _waitFor(() => offers.isNotEmpty);
      expect(offers.single['tripId'], 't4');
    },
  );

  // Overlapping connect(): the first caller used to hang for the full 8 s
  // timeout and then report a stale drop AFTER the replacement had connected.
  test(
    'a second connect() fails the first promptly and only B reports state',
    () async {
      server.ackConnect = false; // A can never finish its handshake
      final sw = Stopwatch()..start();
      final first = client.connect('tok-A');
      server.ackConnect = true;
      final second = client.connect('tok-B');

      await expectLater(first, throwsA(isA<StateError>()));
      expect(sw.elapsed, lessThan(const Duration(seconds: 4)));
      await second;
      expect(client.isConnected, isTrue);
      // Only B ever handshakes: A was torn down while still opening, so its
      // CONNECT (and token) must never reach the server.
      expect(server.auths.map((a) => a['token']), ['tok-B']);
      // A's teardown must not leak a `false` into the banner stream.
      expect(edges, [true]);
    },
  );

  // Identity leak: socket_io_client caches the Manager+Socket per URL and a
  // cached socket keeps the auth it was created with. `disableMultiplex()`
  // (used previously) does NOT bypass that cache in 3.1.6 — it just removes
  // the `multiplex` key — so sign-out → sign-in, or a reconnect with a rotated
  // access token, silently re-sent the FIRST token. Only `forceNew` does.
  test('connect() after disconnect() authenticates with the new token, not a '
      'cached socket\'s old one', () async {
    await client.connect('tok-A');
    client.disconnect();
    await _waitFor(() => server.clients.isEmpty);
    await client.connect('tok-B');
    expect(client.isConnected, isTrue);
    expect(server.auths.map((a) => a['token']), ['tok-A', 'tok-B']);
    expect(server.clients.length, 1, reason: 'the old socket must be gone');

    server.emitAll('trip:offer', {'tripId': 't5'});
    await _waitFor(() => offers.isNotEmpty);
    expect(offers.single['tripId'], 't5');
  });

  test('disconnect() fails an in-flight connect() with a StateError', () async {
    server.ackConnect = false;
    final pending = client.connect('tok-A');
    client.disconnect();
    await expectLater(pending, throwsA(isA<StateError>()));
    expect(client.isConnected, isFalse);
    expect(edges, isEmpty);
  });
}
