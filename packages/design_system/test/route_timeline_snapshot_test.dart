import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('RouteTimeline shows every stop, wrapping at 2x text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800) * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2)),
        child: Scaffold(
          body: SingleChildScrollView(
            child: RouteTimeline(stops: const [
              RouteTimelineStop(
                  label: 'Pickup',
                  address: 'A very long pickup address, Block 12, Street 4'),
              RouteTimelineStop(label: 'Stop', address: 'Market'),
              RouteTimelineStop(label: 'Drop-off', address: 'Airport'),
            ]),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('Pickup'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('Airport'), findsOneWidget);
  });

  test('RouteSnapshotPainter fits the route inside the padding', () {
    const size = Size(320, 180);
    const pad = EdgeInsets.fromLTRB(40, 32, 40, 72);
    final pts = RouteSnapshotPainter.project(
      const [LatLng(41.30, 69.24), LatLng(41.33, 69.30)],
      size,
      pad,
    );
    expect(pts.length, greaterThan(2)); // two ends become an arc
    for (final p in [pts.first, pts.last]) {
      expect(p.dx, inInclusiveRange(pad.left - 0.01, size.width - pad.right + 0.01));
      expect(p.dy, inInclusiveRange(pad.top - 0.01, size.height - pad.bottom + 0.01));
    }
  });

  testWidgets('RouteSnapshot renders in light and dark', (tester) async {
    for (final dark in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        theme: dark ? ThemeData.dark() : ThemeData.light(),
        home: const Scaffold(
          body: RouteSnapshot(
            path: [LatLng(41.30, 69.24), LatLng(41.31, 69.26), LatLng(41.33, 69.30)],
            semanticLabel: 'Route map',
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(RouteSnapshot), findsOneWidget);
    }
  });
}
