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

  testWidgets('a cash trip says so', (tester) async {
    await show(
      tester,
      const Receipt(tripId: 't1', fare: 10, currency: 'USD', method: 'cash'),
    );

    expect(find.text('\$10'), findsNWidgets(2)); // Fare + Total
    expect(find.text('Paid in cash'), findsOneWidget);
  });
}
