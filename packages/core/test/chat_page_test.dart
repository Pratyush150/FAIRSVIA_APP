import 'dart:async';

import 'package:core/core.dart';
import 'package:core/src/chat/chat_widgets.dart';
import 'package:design_system/design_system.dart';
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

/// A phone-sized window (411 x 914 dp), set up by the first pump.
Widget _phone(Widget child) => child;

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(411, 914) * 2.625;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
}

void main() {
  late MockChat chat;
  late _FakeRealtime realtime;

  setUp(() {
    chat = MockChat();
    realtime = _FakeRealtime();
  });

  testWidgets('re-pulls history on reconnect without duplicating messages', (
    tester,
  ) async {
    var calls = 0;
    when(() => chat.history('trip1')).thenAnswer((_) async {
      calls++;
      // The second pull (after the drop) carries a message we never got live.
      return calls == 1
          ? [_msg('m1', 'hello', 1000)]
          : [_msg('m1', 'hello', 1000), _msg('m2', 'missed you', 2000)];
    });

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPage(
          tripId: 'trip1',
          currentUserId: 'me',
          title: 'Driver',
          chat: chat,
          realtime: realtime,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('missed you'), findsNothing);

    realtime.reconnectCtrl.add(null);
    await tester.pumpAndSettle();

    expect(calls, 2);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('missed you'), findsOneWidget);
    // The late arrival fades in (flutter_animate starts on a zero timer).
    await tester.pumpAndSettle(AppMotion.slow);
  });

  Widget page({bool reduceMotion = false, Brightness b = Brightness.light}) =>
      _phone(
        MaterialApp(
          theme: b == Brightness.dark ? AppTheme.dark : AppTheme.light,
          home: Builder(
            builder: (context) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: ChatPage(
                tripId: 'trip1',
                currentUserId: 'me',
                title: 'Rahul',
                subtitle: 'MH 12 AB 1234',
                chat: chat,
                realtime: realtime,
              ),
            ),
          ),
        ),
      );

  testWidgets('empty chat: plain header, one muted line, rows one per line', (
    tester,
  ) async {
    when(() => chat.history('trip1')).thenAnswer((_) async => []);
    usePhone(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    // Plain app bar: name + one muted subtitle line, nothing else.
    expect(find.text('Rahul'), findsOneWidget);
    expect(find.text('MH 12 AB 1234'), findsOneWidget);
    expect(find.byType(AppAvatar), findsNothing);
    expect(find.text('Send a message to Rahul'), findsOneWidget);
    expect(find.text('Suggestions'), findsOneWidget);
    expect(find.textContaining('Messages go straight'), findsNothing);
    expect(find.text('QUICK REPLIES'), findsNothing);
    // Suggestion rows are text only: no icons inside them.
    expect(
      find.descendant(
        of: find.byType(ChatSuggestionRow),
        matching: find.byType(Icon),
      ),
      findsNothing,
    );

    // Every suggestion is its own full-width row, stacked vertically.
    final rows = find.byType(ChatSuggestionRow);
    expect(rows, findsNWidgets(kChatQuickReplies.length));
    final rects = [
      for (var i = 0; i < kChatQuickReplies.length; i++)
        tester.getRect(find.byKey(ValueKey('quick-reply-$i'))),
    ];
    final screenW =
        tester.view.physicalSize.width / tester.view.devicePixelRatio;
    for (var i = 0; i < rects.length; i++) {
      expect(rects[i].width, greaterThan(screenW * 0.8));
      expect(rects[i].height, greaterThanOrEqualTo(48));
      if (i > 0) {
        expect(rects[i].left, rects[0].left);
        expect(rects[i].top, greaterThan(rects[i - 1].bottom - 0.5));
      }
    }
    expect(find.bySemanticsLabel("Send quick reply: I'm here"), findsOneWidget);
  });

  testWidgets('tapping a suggestion sends it and shows it as a bubble', (
    tester,
  ) async {
    when(() => chat.history('trip1')).thenAnswer((_) async => []);
    when(() => chat.send('trip1', 'On my way')).thenAnswer(
      (_) async => const ChatMessage(
        id: 's1',
        tripId: 'trip1',
        from: 'me',
        text: 'On my way',
        ts: 5000,
      ),
    );
    usePhone(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    await tester.tap(find.text('On my way'));
    await tester.pumpAndSettle();

    verify(() => chat.send('trip1', 'On my way')).called(1);
    expect(find.byType(ChatBubble), findsOneWidget);
    expect(find.text('Sent'), findsOneWidget);
    // Conversation started: suggestions are only offered on an empty thread.
    expect(find.byType(ChatSuggestionRow), findsNothing);
    expect(find.text('Suggestions'), findsNothing);
  });

  testWidgets('send button is inert until there is text', (tester) async {
    when(() => chat.history('trip1')).thenAnswer((_) async => []);
    when(() => chat.send('trip1', 'hi there')).thenAnswer(
      (_) async => const ChatMessage(
        id: 's2',
        tripId: 'trip1',
        from: 'me',
        text: 'hi there',
        ts: 5000,
      ),
    );
    usePhone(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    IconButton send() => tester.widget<IconButton>(
      find
          .ancestor(
            of: find.byTooltip('Send message'),
            matching: find.byType(IconButton),
          )
          .first,
    );
    expect(send().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'hi there');
    await tester.pumpAndSettle();
    expect(send().onPressed, isNotNull);
    await tester.tap(find.byTooltip('Send message'));
    await tester.pumpAndSettle();
    verify(() => chat.send('trip1', 'hi there')).called(1);
    expect(find.text('hi there'), findsOneWidget);
  });

  testWidgets('groups by sender and separates days', (tester) async {
    final day1 = DateTime(2026, 9, 20, 10, 0).millisecondsSinceEpoch;
    final day2 = DateTime(2026, 9, 21, 9, 0).millisecondsSinceEpoch;
    when(() => chat.history('trip1')).thenAnswer(
      (_) async => [
        _msg('a', 'one', day1),
        _msg('b', 'two', day1 + 30000),
        _msg('c', 'next day', day2),
      ],
    );
    usePhone(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    ChatBubble bubble(String text) => tester.widget<ChatBubble>(
      find.ancestor(of: find.text(text), matching: find.byType(ChatBubble)),
    );
    final bubbles = [bubble('one'), bubble('two'), bubble('next day')];
    expect(bubbles.map((b) => (b.first, b.last)).toList(), [
      (true, false),
      (false, true),
      (true, true),
    ]);
    expect(find.byType(ChatDaySeparator), findsNWidgets(2));
  });

  testWidgets('bubbles are plain radius-18 rectangles; own bubble is teal', (
    tester,
  ) async {
    when(() => chat.history('trip1')).thenAnswer(
      (_) async => [
        _msg('a', 'theirs', 1000),
        const ChatMessage(
          id: 'b',
          tripId: 'trip1',
          from: 'me',
          text: 'mine',
          ts: 2000,
        ),
      ],
    );
    usePhone(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    BoxDecoration deco(String text) =>
        tester
                .widget<Container>(
                  find
                      .ancestor(
                        of: find.text(text),
                        matching: find.byType(Container),
                      )
                      .first,
                )
                .decoration!
            as BoxDecoration;
    expect(deco('theirs').borderRadius, BorderRadius.circular(18));
    expect(deco('mine').borderRadius, BorderRadius.circular(18));
    expect(deco('mine').color, AppColors.inkFor(false));
    expect(deco('theirs').color, AppColors.surfaceMutedLight);
  });

  testWidgets('a new message fades in over 150 ms, with no scale or move', (
    tester,
  ) async {
    when(
      () => chat.history('trip1'),
    ).thenAnswer((_) async => [_msg('a', 'first', 1000)]);
    usePhone(tester);
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    when(() => chat.send('trip1', 'hey')).thenAnswer(
      (_) async => const ChatMessage(
        id: 'n1',
        tripId: 'trip1',
        from: 'me',
        text: 'hey',
        ts: 3000,
      ),
    );
    await tester.enterText(find.byType(TextField), 'hey');
    await tester.pump();
    await tester.tap(find.byTooltip('Send message'));
    await tester.pump();
    await tester.pump();
    final moved = tester
        .widgetList<Transform>(
          find.ancestor(of: find.text('hey'), matching: find.byType(Transform)),
        )
        .where((t) => t.transform != Matrix4.identity());
    expect(moved, isEmpty);
    List<double> fades() => [
      for (final f in tester.widgetList<FadeTransition>(
        find.ancestor(
          of: find.text('hey'),
          matching: find.byType(FadeTransition),
        ),
      ))
        f.opacity.value,
    ];
    // flutter_animate starts on a zero timer: one frame to kick off.
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump(const Duration(milliseconds: 60));
    expect(fades().any((v) => v > 0 && v < 1), isTrue, reason: '${fades()}');
    // Done 150 ms after it started.
    await tester.pump(const Duration(milliseconds: 95));
    expect(fades().every((v) => v == 1), isTrue, reason: '${fades()}');
    await tester.pumpAndSettle();
  });

  testWidgets('Reduce Motion: the empty state still renders and sends', (
    tester,
  ) async {
    when(() => chat.history('trip1')).thenAnswer((_) async => []);
    when(() => chat.send('trip1', 'Thanks!')).thenAnswer(
      (_) async => const ChatMessage(
        id: 's3',
        tripId: 'trip1',
        from: 'me',
        text: 'Thanks!',
        ts: 5000,
      ),
    );
    usePhone(tester);
    await tester.pumpWidget(page(reduceMotion: true));
    await tester.pump();
    await tester.pump(AppMotion.fast);
    await tester.pump(AppMotion.fast);
    // No motion at all: rows are in their final place immediately.
    expect(
      find.byType(ChatSuggestionRow),
      findsNWidgets(kChatQuickReplies.length),
    );
    final moved = tester
        .widgetList<Transform>(
          find.ancestor(
            of: find.byType(ChatSuggestionRow),
            matching: find.byType(Transform),
          ),
        )
        .where((t) => t.transform != Matrix4.identity());
    expect(moved, isEmpty);
    await tester.tap(find.text('Thanks!'));
    await tester.pumpAndSettle();
    verify(() => chat.send('trip1', 'Thanks!')).called(1);
  });
}
