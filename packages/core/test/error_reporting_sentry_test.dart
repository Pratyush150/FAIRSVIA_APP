import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

class _RecordingTransport implements Transport {
  final List<SentryEnvelope> sent = [];

  @override
  Future<SentryId?> send(SentryEnvelope envelope) async {
    sent.add(envelope);
    return SentryId.newId();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingTransport transport;

  setUp(() async {
    transport = _RecordingTransport();
    await Sentry.init((o) {
      o.dsn = 'https://public@example.invalid/1';
      o.transport = transport;
    });
  });

  tearDown(() async {
    lastCaughtError.value = null;
    await Sentry.close();
  });

  test('an uncaught app error is forwarded to Sentry', () async {
    reportError(StateError('fairsvia-probe'), StackTrace.current);
    // Poll rather than wait a fixed 50 ms: under a loaded full-suite run the
    // async send can take longer, which made this test flaky.
    for (var i = 0; i < 40 && transport.sent.isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }

    expect(transport.sent, hasLength(1));
  });

  test('transient socket-close errors are not sent to Sentry', () async {
    reportError(Exception('WebSocketConnectionClosed'));
    await Future<void>.delayed(const Duration(milliseconds: 50));

    expect(transport.sent, isEmpty);
  });
}
