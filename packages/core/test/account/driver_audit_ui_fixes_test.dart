import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:design_system/design_system.dart';

class MockDriver extends Mock implements DriverRemoteDataSource {}

void main() {
  testWidgets('negative payout balance: true minus, red, explained',
      (tester) async {
    final driver = MockDriver();
    when(() => driver.balance()).thenAnswer((_) async =>
        const PayoutBalance(balance: -35.60, currency: 'INR', entries: []));
    when(() => driver.connectStatus()).thenAnswer((_) async =>
        const ConnectStatus(
            onboarded: true, payoutsEnabled: true, detailsSubmitted: true));
    await tester.pumpWidget(MaterialApp(home: DriverPayoutsPage(driver: driver)));
    await tester.pumpAndSettle();
    final t = tester.widget<Text>(find.byKey(const Key('payout-balance')));
    expect(t.data!.startsWith('−'), isTrue);
    expect(t.data!.contains('-'), isFalse);
    expect(t.style!.color, AppColors.error);
    expect(find.byKey(const Key('payout-negative-note')), findsOneWidget);
  });

  testWidgets('positive payout balance has no owe note', (tester) async {
    final driver = MockDriver();
    when(() => driver.balance()).thenAnswer((_) async =>
        const PayoutBalance(balance: 12.6, currency: 'INR', entries: []));
    when(() => driver.connectStatus()).thenAnswer((_) async =>
        const ConnectStatus(
            onboarded: true, payoutsEnabled: true, detailsSubmitted: true));
    await tester.pumpWidget(MaterialApp(home: DriverPayoutsPage(driver: driver)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('payout-negative-note')), findsNothing);
  });

  testWidgets('week bars label every day and tick zero days', (tester) async {
    final days = [
      for (var i = 0; i < 7; i++)
        EarningsDay(
          date: DateTime(2026, 9, 21 + i), // Mon..Sun
          total: i == 2 ? 0 : 100.4 * (i + 1),
          trips: i == 2 ? 0 : 1,
        ),
    ];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: SizedBox(width: 328, child: WeekBars(days: days))),
    ));
    for (var wd = 1; wd <= 7; wd++) {
      expect(find.byKey(Key('week-bar-amount-$wd')), findsOneWidget);
    }
    // Wednesday (weekday 3) is zero: visible tick, "0" amount.
    expect(find.byKey(const Key('week-bar-zero-3')), findsOneWidget);
    expect(tester.getSize(find.byKey(const Key('week-bar-zero-3'))).height,
        greaterThan(0));
    final wed = tester.widget<Text>(find.byKey(const Key('week-bar-amount-3')));
    expect(wed.data!.endsWith('0'), isTrue);
    final mon = tester.widget<Text>(find.byKey(const Key('week-bar-amount-1')));
    expect(mon.data!.endsWith('100'), isTrue); // whole units
  });
}
