import 'package:core/core.dart';
import 'package:driver_app/features/driver/call_rider_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget button) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: button))),
      );

  testWidgets('Call rider opens the dialler on tel:<rider number>', (
    tester,
  ) async {
    final launched = <Uri>[];
    await pump(
      tester,
      CallRiderButton(
        phone: '+998 90 777-88-99',
        dialer: (p) => dialPhone(p, launch: (uri) async {
          launched.add(uri);
          return true;
        }),
      ),
    );
    await tester.tap(find.byTooltip('Call rider'));
    await tester.pump();
    expect(launched.map((u) => u.toString()), ['tel:+998907778899']);
  });

  testWidgets('a dialler failure is surfaced', (tester) async {
    await pump(
      tester,
      CallRiderButton(phone: '+998907778899', dialer: (_) async => false),
    );
    await tester.tap(find.byTooltip('Call rider'));
    await tester.pump();
    expect(find.textContaining("Couldn't open the dialler"), findsOneWidget);
  });

  test('the driver trip payload carries the rider phone', () {
    final trip = Trip.fromJson(const {
      'id': 't1',
      'status': 'accepted',
      'tier': 'economy',
      'pickup': {'lat': 41.3, 'lng': 69.2},
      'dropoff': {'lat': 41.3, 'lng': 69.3},
      'rider': {'id': 'r1', 'name': 'Rustam', 'phone': '+998907778899'},
    });
    expect(trip.riderPhone, '+998907778899');
    expect(trip.riderName, 'Rustam');
    // The rider's own view has no `rider` block.
    final own = Trip.fromJson(const {
      'id': 't1',
      'status': 'accepted',
      'tier': 'economy',
      'pickup': {'lat': 41.3, 'lng': 69.2},
      'dropoff': {'lat': 41.3, 'lng': 69.3},
    });
    expect(own.riderPhone, isNull);
  });
}
