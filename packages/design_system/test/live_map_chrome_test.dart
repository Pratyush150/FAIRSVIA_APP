import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The controls that sit over the live map: the Recenter pill that appears
/// when the camera stops following, and the connection banner that has to say
/// when live updates came back, not just when they stopped.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('RecenterPill', () {
    testWidgets('is invisible and untappable while the camera follows',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(RecenterPill(visible: false, onPressed: () => taps++)),
      );
      await tester.pumpAndSettle();

      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity,
          0);
      // Hidden means hidden: a stray tap in that corner must not fire it.
      await tester.tap(find.byType(RecenterPill), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(taps, 0);
    });

    testWidgets('appears and recenters once the rider has panned away',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        wrap(RecenterPill(visible: true, onPressed: () => taps++)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Recenter'), findsOneWidget);
      await tester.tap(find.text('Recenter'));
      await tester.pumpAndSettle();
      expect(taps, 1);
    });
  });

  group('ConnectionBanner', () {
    // The disconnected bar carries an indeterminate spinner, which never
    // stops scheduling frames — so these pump fixed durations rather than
    // pumpAndSettle, which would spin forever waiting for it.
    const settle = Duration(milliseconds: 400);

    testWidgets('says nothing at all while the socket has never dropped',
        (tester) async {
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: true)));
      await tester.pump(settle);
      expect(find.textContaining('Reconnecting'), findsNothing);
      expect(find.textContaining('Connected'), findsNothing);
    });

    testWidgets('confirms the recovery, then gets out of the way',
        (tester) async {
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: true)));
      await tester.pump(settle);

      // Drop.
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: false)));
      await tester.pump(settle);
      expect(find.textContaining('Reconnecting'), findsOneWidget);

      // Recovery: the rider is told, rather than the bar just vanishing —
      // otherwise a resumed live map looks exactly like a frozen one.
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: true)));
      await tester.pump(settle);
      expect(find.textContaining('Connected'), findsOneWidget);
      expect(find.textContaining('Reconnecting'), findsNothing);

      // ...and then it collapses on its own.
      await tester.pump(ConnectionBanner.reconnectedHold);
      await tester.pump(settle);
      expect(find.textContaining('Connected'), findsNothing);
    });

    testWidgets('a second drop inside the hold window wins', (tester) async {
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: true)));
      await tester.pump(settle);
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: false)));
      await tester.pump(settle);
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: true)));
      await tester.pump(settle);
      // Flaps down again before the green bar's timer fires.
      await tester.pumpWidget(wrap(const ConnectionBanner(connected: false)));
      await tester.pump(settle);

      // That stale timer must not clear the amber bar when it lands.
      await tester.pump(ConnectionBanner.reconnectedHold);
      await tester.pump(settle);
      expect(find.textContaining('Reconnecting'), findsOneWidget);
    });
  });
}
