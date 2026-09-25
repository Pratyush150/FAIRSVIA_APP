import 'package:design_system/design_system.dart';
import 'package:driver_app/features/driver/no_show_timer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final arrived = DateTime(2026, 9, 25, 10);
  late DateTime now;

  Future<void> pump(
    WidgetTester tester, {
    required Future<void> Function() onNoShow,
    Brightness brightness = Brightness.light,
  }) async {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: NoShowTimer(
            arrivedAt: arrived,
            waitSec: 300,
            fee: 50,
            onNoShow: onNoShow,
            now: () => now,
          ),
        ),
      ),
    ));
  }

  test('secondsLeft counts down and never goes negative', () {
    expect(NoShowTimer.secondsLeft(arrived, 300, arrived), 300);
    expect(
        NoShowTimer.secondsLeft(
            arrived, 300, arrived.add(const Duration(seconds: 55))),
        245);
    expect(
        NoShowTimer.secondsLeft(
            arrived, 300, arrived.add(const Duration(minutes: 9))),
        0);
    expect(NoShowTimer.clock(245), '4:05');
  });

  testWidgets('counts down, then offers the no-show cancel with the fee',
      (tester) async {
    now = arrived.add(const Duration(seconds: 10));
    var called = 0;
    await pump(tester, onNoShow: () async => called++);

    expect(find.text('Waiting for rider'), findsOneWidget);
    expect(find.text('4:50'), findsOneWidget);
    expect(find.text("Rider didn't show"), findsNothing);

    now = arrived.add(const Duration(seconds: 70));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('3:50'), findsOneWidget);

    // Wait over.
    now = arrived.add(const Duration(minutes: 5, seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Waiting for rider'), findsNothing);
    expect(find.textContaining('no-show fee'), findsOneWidget);
    expect(tester.takeException(), isNull); // no overflow at 360 dp

    // Asks first; "Keep waiting" does nothing.
    await tester.tap(find.text("Rider didn't show"));
    await tester.pumpAndSettle();
    expect(find.text("Rider didn't show?"), findsOneWidget);
    await tester.tap(find.text('Keep waiting'));
    await tester.pumpAndSettle();
    expect(called, 0);

    await tester.tap(find.text("Rider didn't show"));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel trip'));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('the waiting state reads as one sentence to a screen reader '
      '(dark theme)', (tester) async {
    final handle = tester.ensureSemantics();
    now = arrived.add(const Duration(seconds: 30));
    await pump(tester, onNoShow: () async {}, brightness: Brightness.dark);
    expect(
      find.bySemanticsLabel(RegExp(r'Waiting for the rider\. No-show option in 5 minutes')),
      findsOneWidget,
    );
    handle.dispose();
  });
}
