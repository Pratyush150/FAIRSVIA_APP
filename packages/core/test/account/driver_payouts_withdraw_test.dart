import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockDriver extends Mock implements DriverRemoteDataSource {}

void main() {
  late MockDriver driver;

  const balance = PayoutBalance(balance: 12.60, currency: 'USD', entries: []);

  setUp(() {
    driver = MockDriver();
    when(() => driver.balance()).thenAnswer((_) async => balance);
    when(() => driver.connectStatus()).thenAnswer(
      (_) async => const ConnectStatus(
        onboarded: true,
        payoutsEnabled: true,
        detailsSubmitted: true,
      ),
    );
  });

  Widget wrap() => MaterialApp(home: DriverPayoutsPage(driver: driver));

  Future<void> openDialog(WidgetTester tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PrimaryButton, 'Withdraw to bank'));
    await tester.pumpAndSettle();
  }

  group('validateWithdrawal', () {
    test('accepts 0 < amount <= max (at cent precision)', () {
      expect(DriverPayoutsPage.validateWithdrawal('12.60', 12.6), isNull);
      expect(DriverPayoutsPage.validateWithdrawal('0.01', 12.6), isNull);
      expect(DriverPayoutsPage.validateWithdrawal(' 5 ', 12.6), isNull);
    });

    test('rejects unparsable, zero, negative and over-balance amounts', () {
      expect(DriverPayoutsPage.validateWithdrawal('abc', 12.6), isNotNull);
      expect(DriverPayoutsPage.validateWithdrawal('', 12.6), isNotNull);
      expect(DriverPayoutsPage.validateWithdrawal('0', 12.6), isNotNull);
      expect(DriverPayoutsPage.validateWithdrawal('-1', 12.6), isNotNull);
      expect(
        DriverPayoutsPage.validateWithdrawal('13', 12.6),
        'You can withdraw up to \$12.60.',
      );
    });
  });

  testWidgets('pre-fills the full balance with cents, not rounded up',
      (tester) async {
    await openDialog(tester);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.controller!.text, '12.60');
  });

  testWidgets('shows an inline error instead of posting an invalid amount',
      (tester) async {
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), '13');
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(find.text('You can withdraw up to \$12.60.'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid amount.'), findsOneWidget);

    // Still on the dialog, nothing was sent.
    expect(find.text('Withdraw to bank'), findsNWidgets(2));
    verifyNever(() => driver.withdraw(any()));
  });

  testWidgets('posts a valid amount and confirms with two decimals',
      (tester) async {
    when(() => driver.withdraw(any())).thenAnswer((_) async => balance);
    await openDialog(tester);

    await tester.enterText(find.byType(TextField), '12.60');
    await tester.tap(find.text('Withdraw'));
    await tester.pumpAndSettle();

    verify(() => driver.withdraw(12.6)).called(1);
    expect(find.text('Withdrew \$12.60'), findsOneWidget);
  });
}
