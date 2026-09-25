import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class _MockChat extends Mock implements ChatRemoteDataSource {}

class _QuietRealtime implements RealtimeClient {
  @override
  Stream<Map<String, dynamic>> on(String event) => const Stream.empty();
  @override
  Stream<void> get reconnects => const Stream.empty();
  @override
  Stream<bool> get connection => const Stream.empty();
  @override
  bool get isConnected => true;
  @override
  Future<void> connect(String token) async {}
  @override
  Future<void> connectWith(AccessTokenProvider tokenProvider) async {}
  @override
  void disconnect() {}
  @override
  void emit(String event, Map<String, dynamic> data) {}
}

/// Renders the in-trip chat (empty + with messages + quick replies open) in
/// light and dark. Runs as a smoke test everywhere; writes PNGs only when
/// CHAT_SHOTS names a directory:
///
///   CHAT_SHOTS=../../docs/brand/research/chat \
///     flutter test test/chat_screens_test.dart
void main() {
  final shots = Platform.environment['CHAT_SHOTS'];

  setUpAll(() async {
    if (shots != null) await _loadFonts();
  });

  final now = DateTime.now();
  int at(int minsAgo) =>
      now.subtract(Duration(minutes: minsAgo)).millisecondsSinceEpoch;
  ChatMessage m(String id, String from, String text, int ts) =>
      ChatMessage(id: id, tripId: 't1', from: from, text: text, ts: ts);
  final thread = [
    m('0', 'drv', 'Hi! I have accepted your ride.',
        now.subtract(const Duration(days: 1)).millisecondsSinceEpoch),
    m('1', 'drv', "Hi, I'm at the main gate", at(6)),
    m('2', 'drv', 'White Dzire, hazard lights on', at(6)),
    m('3', 'me', 'On my way', at(5)),
    m('4', 'me', 'Coming down the stairs, 2 min', at(5)),
    m('5', 'drv', 'No rush, take your time', at(4)),
    m('6', 'me', 'Thanks!', at(1)),
  ];

  Future<void> shoot(
    WidgetTester tester,
    String name, {
    required bool dark,
    required List<ChatMessage> history,
    bool openReplies = false,
  }) async {
    tester.view.physicalSize = const Size(411, 914) * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    final chat = _MockChat();
    when(() => chat.history('t1')).thenAnswer((_) async => history);
    final key = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: dark ? AppTheme.dark : AppTheme.light,
          home: ChatPage(
            tripId: 't1',
            currentUserId: 'me',
            title: 'Rahul Verma',
            subtitle: 'White Maruti Dzire · MH 12 AB 1234',
            chat: chat,
            realtime: _QuietRealtime(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (openReplies) {
      await tester.tap(find.byTooltip('Quick replies'));
      await tester.pumpAndSettle();
    }
    if (shots == null) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(shots).createSync(recursive: true);
      File('$shots/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('chat empty · $mode', (tester) async {
      await shoot(tester, 'chat-empty-$mode', dark: dark, history: const []);
      expect(find.text('Chat with Rahul Verma'), findsOneWidget);
    });
    testWidgets('chat thread · $mode', (tester) async {
      await shoot(tester, 'chat-thread-$mode', dark: dark, history: thread);
      expect(find.text('Sent'), findsOneWidget);
    });
    testWidgets('chat quick replies open · $mode', (tester) async {
      await shoot(tester, 'chat-replies-$mode',
          dark: dark, history: thread, openReplies: true);
      expect(find.text('Please wait'), findsOneWidget);
    });
  }
}

final String _flutterRoot = Platform.environment['FLUTTER_ROOT'] ??
    File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.path;

Future<void> _loadFonts() async {
  final fonts = Directory('${Directory.current.path}/../design_system/fonts')
      .resolveSymbolicLinksSync();
  Future<void> load(String family, List<String> paths) async {
    final loader = FontLoader(family);
    for (final p in paths) {
      loader.addFont(File(p).readAsBytes().then((b) => b.buffer.asByteData()));
    }
    await loader.load();
  }

  await load('MaterialIcons', [
    '$_flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
  ]);
  await load('packages/design_system/PhosphorRegular', [
    '$fonts/Phosphor-Regular.ttf',
  ]);
  await load('packages/design_system/PhosphorFill', [
    '$fonts/Phosphor-Fill.ttf',
  ]);
  await load('packages/design_system/Inter', [
    '$fonts/Inter-Regular.ttf',
    '$fonts/Inter-Medium.ttf',
    '$fonts/Inter-SemiBold.ttf',
    '$fonts/Inter-Bold.ttf',
    '$fonts/Inter-ExtraBold.ttf',
  ]);
}
