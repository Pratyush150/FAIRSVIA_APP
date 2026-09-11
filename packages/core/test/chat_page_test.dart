import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockChat extends Mock implements ChatRemoteDataSource {}

/// Just enough of the transport to drive the page: event streams and the
/// reconnect cue.
class _FakeRealtime implements RealtimeClient {
  final _events = <String, StreamController<Map<String, dynamic>>>{};
  final reconnectCtrl = StreamController<void>.broadcast();

  @override
  Stream<Map<String, dynamic>> on(String event) => _events
      .putIfAbsent(event, StreamController<Map<String, dynamic>>.broadcast)
      .stream;

  @override
  Stream<void> get reconnects => reconnectCtrl.stream;

  @override
  Stream<bool> get connection => const Stream.empty();

  @override
  bool get isConnected => true;

  @override
  Future<void> connect(String token) async {}

  @override
  Future<void> connectWith(AccessTokenProvider tokenProvider) async =>
      connect((await tokenProvider()) ?? '');

  @override
  void disconnect() {}

  @override
  void emit(String event, Map<String, dynamic> data) {}
}

ChatMessage _msg(String id, String text, int ts) =>
    ChatMessage(id: id, tripId: 'trip1', from: 'other', text: text, ts: ts);

void main() {
  late MockChat chat;
  late _FakeRealtime realtime;

  setUp(() {
    chat = MockChat();
    realtime = _FakeRealtime();
  });

  testWidgets('re-pulls history on reconnect without duplicating messages',
      (tester) async {
    var calls = 0;
    when(() => chat.history('trip1')).thenAnswer((_) async {
      calls++;
      // The second pull (after the drop) carries a message we never got live.
      return calls == 1
          ? [_msg('m1', 'hello', 1000)]
          : [_msg('m1', 'hello', 1000), _msg('m2', 'missed you', 2000)];
    });

    await tester.pumpWidget(MaterialApp(
      home: ChatPage(
        tripId: 'trip1',
        currentUserId: 'me',
        title: 'Driver',
        chat: chat,
        realtime: realtime,
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('missed you'), findsNothing);

    realtime.reconnectCtrl.add(null);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('missed you'), findsOneWidget);
  });
}
