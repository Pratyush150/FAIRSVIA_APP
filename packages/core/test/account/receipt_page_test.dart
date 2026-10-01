import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockPayments extends Mock implements PaymentsRemoteDataSource {}

final _trip = Trip(
  id: 't1',
  status: TripStatus.completed,
  tier: 'economy',
  pickup: const TripEndpoint(point: GeoPoint(25.77, -80.19), address: 'A'),
  dropoff: const TripEndpoint(point: GeoPoint(25.79, -80.19), address: 'B'),
  fareFinal: 10,
  requestedAt: DateTime(2026, 9, 10, 19, 44),
);

void main() {
  late MockPayments payments;

  setUp(() => payments = MockPayments());

  Future<void> show(WidgetTester tester, Receipt r) async {
    when(() => payments.receipt('t1')).thenAnswer((_) async => r);
    await tester.pumpWidget(
      MaterialApp(home: ReceiptPage(payments: payments, trip: _trip)),
    );
    await tester.pumpAndSettle();
  }

  group('Receipt.total', () {
    test('is charged fare + tip net of refunds, floored at zero', () {
      const base = Receipt(tripId: 't1', fare: 10, currency: 'USD');
      expect(base.total, 10);
      expect(const Receipt(tripId: 't1', fare: 10, currency: 'USD', tip: 2)
          .total, 12);
      expect(
        const Receipt(
          tripId: 't1',
          fare: 10,
          currency: 'USD',
          tip: 2,
          refundedAmount: 5,
        ).total,
        7,
      );
      // The payment record's amount wins over the trip fare when present.
      expect(
        const Receipt(
          tripId: 't1',
          fare: 10,
          currency: 'USD',
          chargedAmount: 9.5,
        ).total,
        9.5,
      );
      expect(
        const Receipt(tripId: 't1', fare: 10, currency: 'USD', refundedAmount: 50)
            .total,
        0,
      );
    });

    test('parses payment.amount from the receipt payload', () {
      final r = Receipt.fromJson({
        'tripId': 't1',
        'fare': 10,
        'currency': 'USD',
        'payment': {'amount': 9.5, 'tip': 1, 'method': 'cash'},
      });
      expect(r.chargedAmount, 9.5);
      expect(r.isCash, isTrue);
      expect(r.total, 10.5);
    });
  });

  testWidgets('a refund is netted out of the total', (tester) async {
    await show(
      tester,
      const Receipt(
        tripId: 't1',
        fare: 10,
        currency: 'USD',
        tip: 2,
        refundedAmount: 5,
        status: 'refunded',
      ),
    );

    expect(find.text('- \$5'), findsOneWidget);
    // The total heads the page and closes the fare card.
    expect(find.text('\$7'), findsNWidgets(2));
    expect(find.text('\$12'), findsNothing);
    expect(find.text('Paid in cash'), findsNothing);
  });

  group('breakdown', () {
    const breakdown = FareBreakdown(
      baseFare: 2.5,
      distanceFare: 3.12,
      timeFare: 1.2,
      bookingFee: 1.75,
      surgeMultiplier: 1.2,
      promoDiscount: 1,
      tip: 2,
    );

    test('Receipt.fromJson parses breakdown and tolerates null', () {
      final r = Receipt.fromJson({
        'tripId': 't1',
        'fare': 7.57,
        'currency': 'USD',
        'breakdown': {
          'baseFare': 2.5,
          'distanceFare': 3.12,
          'timeFare': 1.2,
          'bookingFee': 1.75,
          'surgeMultiplier': 1.2,
          'promoDiscount': 1,
          'tip': 2,
        },
      });
      expect(r.breakdown, breakdown);
      final legacy = Receipt.fromJson(
          {'tripId': 't1', 'fare': 7.57, 'currency': 'USD', 'breakdown': null});
      expect(legacy.breakdown, isNull);
    });

    testWidgets('itemised lines show above the fare when present',
        (tester) async {
      await show(
        tester,
        const Receipt(
          tripId: 't1',
          fare: 7.57,
          currency: 'USD',
          tip: 2,
          breakdown: breakdown,
        ),
      );

      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text('\$2.50'), findsOneWidget);
      expect(find.text('Distance'), findsOneWidget);
      expect(find.text('\$3.12'), findsOneWidget);
      expect(find.text('Time'), findsOneWidget);
      expect(find.text('\$1.20'), findsOneWidget);
      expect(find.text('Booking fee'), findsOneWidget);
      expect(find.text('\$1.75'), findsOneWidget);
      expect(find.text('Surge'), findsOneWidget);
      expect(find.text('1.2×'), findsOneWidget);
      expect(find.text('Promo'), findsOneWidget);
      expect(find.text('−\$1'), findsOneWidget);
      // The receipt's own Tip line renders once (showTip: false on the rows).
      expect(find.text('Tip'), findsOneWidget);
      expect(find.text('\$2'), findsOneWidget);
      // Headline fare and total are still the authoritative numbers.
      expect(find.text('Fare'), findsOneWidget);
      expect(find.text('\$7.57'), findsOneWidget);
      expect(find.text('\$9.57'), findsNWidgets(2)); // summary + Total
    });

    testWidgets('surge and promo lines are hidden at 1x / no discount',
        (tester) async {
      await show(
        tester,
        const Receipt(
          tripId: 't1',
          fare: 8.57,
          currency: 'USD',
          breakdown: FareBreakdown(
            baseFare: 2.5,
            distanceFare: 3.12,
            timeFare: 1.2,
            bookingFee: 1.75,
          ),
        ),
      );
      expect(find.text('Base fare'), findsOneWidget);
      expect(find.text('Surge'), findsNothing);
      expect(find.text('Promo'), findsNothing);
      expect(find.text('Tip'), findsNothing);
    });

    testWidgets('a null breakdown keeps the plain fare/total receipt',
        (tester) async {
      await show(
        tester,
        const Receipt(tripId: 't1', fare: 10, currency: 'USD'),
      );
      expect(find.text('Base fare'), findsNothing);
      expect(find.text('Booking fee'), findsNothing);
      // Summary total + Fare + Total.
      expect(find.text('\$10'), findsNWidgets(3));
    });
  });

  testWidgets('a metered auto fare shows distance only, no ₹0 lines',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FareBreakdownRows(
          currency: 'INR',
          breakdown: FareBreakdown(
            baseFare: 0,
            distanceFare: 100,
            timeFare: 0,
            bookingFee: 0,
            surgeMultiplier: 1,
          ),
        ),
      ),
    ));
    expect(find.text('Distance'), findsOneWidget);
    expect(find.text('₹100'), findsOneWidget);
    expect(find.text('Base fare'), findsNothing);
    expect(find.text('Time'), findsNothing);
    expect(find.text('Booking fee'), findsNothing);
  });

  testWidgets('an early end at the minimum fare says "minimum", not "metered"',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FareBreakdownRows(
          currency: 'INR',
          breakdown: FareBreakdown(
            baseFare: 45,
            distanceFare: 0,
            timeFare: 1,
            bookingFee: 4,
            minimumFareAdjustment: 25,
            fareBasis: 'minimum',
            endedEarly: true,
            endReason: 'Rider changed plans',
          ),
        ),
      ),
    ));
    expect(find.text('Minimum fare'), findsOneWidget);
    expect(
        find.text('Trip ended before the drop-off (Rider changed plans). '
            'Minimum fare applied.'),
        findsOneWidget);
    expect(find.textContaining('Metered'), findsNothing);
  });

  testWidgets('a quote-bounded fare is an adjustment, never "Minimum fare"',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: FareBreakdownRows(
          currency: 'INR',
          breakdown: FareBreakdown(
            baseFare: 20,
            distanceFare: 10,
            timeFare: 10,
            bookingFee: 5,
            fareAdjustment: 26,
            fareBasis: 'estimate',
          ),
        ),
      ),
    ));
    expect(find.text('Minimum fare'), findsNothing);
    expect(find.text('Up-front price adjustment'), findsOneWidget);
    expect(find.text('Based on your up-front price.'), findsOneWidget);
  });

  testWidgets('a cash trip says so', (tester) async {
    await show(
      tester,
      const Receipt(tripId: 't1', fare: 10, currency: 'USD', method: 'cash'),
    );

    // Summary total + Fare + Total.
    expect(find.text('\$10'), findsNWidgets(3));
    expect(find.text('Paid in cash'), findsOneWidget);
  });

  group('Your trip layout', () {
    final full = Trip(
      id: 't1',
      status: TripStatus.completed,
      tier: 'comfort',
      pickup: const TripEndpoint(
          point: GeoPoint(25.77, -80.19),
          address: 'Terminal 2 Departures, International Airport Road'),
      dropoff: const TripEndpoint(
          point: GeoPoint(25.79, -80.13),
          address: 'Harbour View Residences, Tower B, Marina Walk, Block 7'),
      fareFinal: 24.5,
      completedAt: DateTime(2026, 9, 10, 19, 44),
      distanceM: 8400,
      durationS: 1260,
      driverName: 'Aziz Karimov',
      driverVehicleLabel: 'Silver Chevrolet Cobalt',
      driverPlate: '01A123BC',
      myRating: 4,
      hasMyRatingField: true,
    );
    const receipt = Receipt(
      tripId: 't1',
      fare: 24.5,
      currency: 'USD',
      tip: 2,
      method: 'card',
      cardLabel: 'Visa •4242',
      status: 'succeeded',
      breakdown: FareBreakdown(
        baseFare: 3,
        distanceFare: 14,
        timeFare: 5.75,
        bookingFee: 1.75,
      ),
    );

    Future<void> pump(WidgetTester tester,
        {double scale = 1, VoidCallback? onGetHelp}) async {
      tester.view.physicalSize = const Size(360, 800) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      when(() => payments.receipt('t1')).thenAnswer((_) async => receipt);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: ReceiptPage(
            payments: payments, trip: full, onGetHelp: onGetHelp),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('titles the page, maps the route and lays out every block',
        (tester) async {
      var helped = 0;
      await pump(tester, onGetHelp: () => helped++);
      expect(find.text('Your trip'), findsOneWidget);
      expect(find.byType(RouteSnapshot), findsOneWidget);
      expect(find.byType(RouteTimeline), findsOneWidget);
      expect(find.text('Pickup'), findsOneWidget);
      expect(find.text('Drop-off'), findsOneWidget);
      expect(find.text('Comfort · Completed'), findsOneWidget);
      expect(find.text('Aziz Karimov'), findsOneWidget);
      expect(find.text('Silver Chevrolet Cobalt'), findsOneWidget);
      // 4 lit stars. Counted by colour: in THEME=clay3d the filled and the
      // empty star share one 3D glyph, so the unlit fifth matches the icon too.
      final stars = tester.widgetList<Icon>(find.byIcon(PhosphorIconsFill.star));
      expect(stars.where((i) => i.color == stars.first.color), hasLength(4));
      expect(find.text('\$26.50'), findsOneWidget); // the summary total
      await tester.scrollUntilVisible(find.text('Paid with Visa •4242'), 200);
      expect(find.text('Fare breakdown'), findsOneWidget);
      expect(find.text('\$26.50'), findsNWidgets(2)); // summary + Total

      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Share receipt'), findsOneWidget);
      await tester.tap(find.text('Get help with this trip'));
      expect(helped, 1);
    });

    testWidgets('no help action without a support route', (tester) async {
      await pump(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(find.text('Share receipt'), findsOneWidget);
      expect(find.text('Get help with this trip'), findsNothing);
    });

    for (final scale in [1.0, 1.5, 2.0]) {
      testWidgets('no overflow at 360dp and ${scale}x text', (tester) async {
        await pump(tester, scale: scale, onGetHelp: () {});
        expect(tester.takeException(), isNull);
        // Walk the whole page so every block lays out.
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byType(ListView), const Offset(0, -500));
          await tester.pumpAndSettle();
        }
        expect(find.textContaining('Trip ID'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });
}
