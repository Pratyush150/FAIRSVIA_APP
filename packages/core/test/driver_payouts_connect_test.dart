import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDriver extends Mock implements DriverRemoteDataSource {}

void main() {
  late MockDriver driver;

  setUp(() {
    driver = MockDriver();
    when(() => driver.balance()).thenAnswer(
      (_) async =>
          const PayoutBalance(balance: 0, currency: 'USD', entries: []),
    );
  });

  Widget wrap() => MaterialApp(home: DriverPayoutsPage(driver: driver));

  testWidgets('shows the setup CTA when payouts are not enabled',
      (tester) async {
    when(() => driver.connectStatus()).thenAnswer(
      (_) async => const ConnectStatus(
        onboarded: false,
        payoutsEnabled: false,
        detailsSubmitted: false,
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(find.text('Set up direct deposit'), findsOneWidget);
    expect(find.text('Set up payouts'), findsOneWidget);
  });

  testWidgets('shows the active confirmation when payouts are enabled',
      (tester) async {
    when(() => driver.connectStatus()).thenAnswer(
      (_) async => const ConnectStatus(
        onboarded: true,
        payoutsEnabled: true,
        detailsSubmitted: true,
      ),
    );

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    expect(
      find.text('Direct deposit active — withdrawals go to your bank.'),
      findsOneWidget,
    );
    expect(find.text('Set up payouts'), findsNothing);
  });
}
