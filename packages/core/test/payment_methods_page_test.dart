import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPayments extends Mock implements PaymentsRemoteDataSource {}

void main() {
  late MockPayments payments;

  setUp(() {
    payments = MockPayments();
    when(() => payments.methods()).thenAnswer((_) async => []);
  });

  Widget wrap(Widget child) => MaterialApp(home: child);

  testWidgets('uses the injected Stripe adder and reloads on success',
      (tester) async {
    var adderCalls = 0;
    Future<StripeCardResult> adder(PaymentsRemoteDataSource _) async {
      adderCalls++;
      return StripeCardResult.added;
    }

    await tester.pumpWidget(wrap(
      PaymentMethodsPage(payments: payments, stripeCardAdder: adder),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(adderCalls, 1);
    // Initial load + reload after a successful add.
    verify(() => payments.methods()).called(greaterThanOrEqualTo(2));
  });

  testWidgets('falls back to the mock sheet when Stripe is unavailable',
      (tester) async {
    Future<StripeCardResult> adder(PaymentsRemoteDataSource _) async =>
        StripeCardResult.unavailable;

    await tester.pumpWidget(wrap(
      PaymentMethodsPage(payments: payments, stripeCardAdder: adder),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // The mock brand + last-4 sheet is shown.
    expect(find.text('Last 4 digits'), findsOneWidget);
  });

  testWidgets('does nothing further when the user cancels the sheet',
      (tester) async {
    Future<StripeCardResult> adder(PaymentsRemoteDataSource _) async =>
        StripeCardResult.cancelled;

    await tester.pumpWidget(wrap(
      PaymentMethodsPage(payments: payments, stripeCardAdder: adder),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    // No fallback sheet, only the initial load happened.
    expect(find.text('Last 4 digits'), findsNothing);
    verify(() => payments.methods()).called(1);
  });
}
