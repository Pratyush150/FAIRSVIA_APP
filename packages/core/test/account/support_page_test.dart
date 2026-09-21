import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSupport extends Mock implements SupportRemoteDataSource {}

void main() {
  late MockSupport support;

  setUp(() {
    support = MockSupport();
    when(() => support.listMine()).thenAnswer((_) async => []);
  });

  Future<void> fillAndSubmit(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(home: SupportPage(support: support)));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'Broken app');
    await tester.enterText(find.byType(TextField).at(1), 'It crashed');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Submit ticket'));
    await tester.pumpAndSettle();
  }

  testWidgets('a non-API failure releases the submit button and says so',
      (tester) async {
    when(() => support.create(
          subject: any(named: 'subject'),
          message: any(named: 'message'),
          category: any(named: 'category'),
          tripId: any(named: 'tripId'),
        )).thenThrow(StateError('unexpected'));

    await fillAndSubmit(tester);

    final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    expect(button.loading, isFalse);
    expect(button.onPressed, isNotNull);
    expect(
      find.text('Something went wrong. Please try again.'),
      findsOneWidget,
    );
  });

  testWidgets('an API failure surfaces its message and releases the button',
      (tester) async {
    when(() => support.create(
          subject: any(named: 'subject'),
          message: any(named: 'message'),
          category: any(named: 'category'),
          tripId: any(named: 'tripId'),
        )).thenThrow(const ApiException('Rate limited'));

    await fillAndSubmit(tester);

    final button = tester.widget<PrimaryButton>(find.byType(PrimaryButton));
    expect(button.loading, isFalse);
    expect(find.text('Rate limited'), findsOneWidget);
  });
}
