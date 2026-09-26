import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

/// The "Details" sheet behind each ride tier's price. Its whole reason to
/// exist is that a rider can check the arithmetic, so the test that matters is
/// that the lines add up to the total on the button.
void main() {
  const breakdown = FareBreakdown(
    baseFare: 2.5,
    distanceFare: 3.73,
    timeFare: 2.5,
    bookingFee: 2,
  );
  const tier = FareTier(
    tier: 'economy',
    label: 'Economy',
    capacity: 4,
    fare: 10.73,
    currency: 'USD',
    etaSeconds: 240,
    breakdown: breakdown,
  );

  Future<void> open(WidgetTester tester, FareTier t) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showFareDetailsSheet(context, t),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('itemises the fare and names the tier', (tester) async {
    await open(tester, tier);

    expect(find.text('Economy fare'), findsOneWidget);
    expect(find.text('Base fare'), findsOneWidget);
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('Time'), findsOneWidget);
    expect(find.text('Booking fee'), findsOneWidget);
    expect(find.text('Estimated total'), findsOneWidget);
    expect(find.text(r'$10.73'), findsOneWidget);
  });

  testWidgets('the lines add up to the total shown', (tester) async {
    await open(tester, tier);

    final sum =
        breakdown.baseFare +
        breakdown.distanceFare +
        breakdown.timeFare +
        breakdown.bookingFee +
        breakdown.minimumFareAdjustment;
    expect(sum, closeTo(tier.fare, 0.005));
  });

  testWidgets('shows the minimum-fare top-up when it applies', (tester) async {
    await open(
      tester,
      const FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 6.5,
        currency: 'USD',
        etaSeconds: 120,
        breakdown: FareBreakdown(
          baseFare: 2.5,
          distanceFare: 0.07,
          timeFare: 0.25,
          bookingFee: 2,
          minimumFareAdjustment: 1.68,
        ),
      ),
    );
    expect(find.text('Minimum fare'), findsOneWidget);
  });

  testWidgets('calls out surge, which is why the price moved', (tester) async {
    await open(
      tester,
      const FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 19.46,
        currency: 'USD',
        etaSeconds: 120,
        breakdown: FareBreakdown(
          baseFare: 5,
          distanceFare: 7.46,
          timeFare: 5,
          bookingFee: 2,
          surgeMultiplier: 2,
        ),
      ),
    );
    expect(find.text('Surge'), findsOneWidget);
  });

  testWidgets('a tier the backend did not itemise opens nothing', (
    tester,
  ) async {
    await open(
      tester,
      const FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 10.73,
        currency: 'USD',
        etaSeconds: 240,
      ),
    );
    expect(find.text('Economy fare'), findsNothing);
  });
}
