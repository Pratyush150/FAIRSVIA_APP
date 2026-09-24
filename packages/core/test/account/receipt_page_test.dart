import 'package:core/core.dart';
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
    expect(find.text('\$7'), findsOneWidget);
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
      expect(find.text('\$9.57'), findsOneWidget);
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
      expect(find.text('\$10'), findsNWidgets(2)); // Fare + Total
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

  testWidgets('a cash trip says so', (tester) async {
    await show(
      tester,
      const Receipt(tripId: 't1', fare: 10, currency: 'USD', method: 'cash'),
    );

    expect(find.text('\$10'), findsNWidgets(2)); // Fare + Total
    expect(find.text('Paid in cash'), findsOneWidget);
  });
}
