import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';
import 'package:mocktail/mocktail.dart';

class _MockSafety extends Mock implements SafetyRemoteDataSource {}

void main() {
  late _MockSafety safety;

  setUp(() => safety = _MockSafety());

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: EmergencyContactsPage(safety: safety),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('adds a first contact from the empty state', (tester) async {
    when(() => safety.contacts()).thenAnswer((_) async => const []);
    when(() => safety.addContact('Mum', '+998901234567')).thenAnswer((_) async =>
        const EmergencyContact(id: 'a', name: 'Mum', phone: '+998901234567'));
    await pump(tester);

    expect(find.text('No emergency contacts yet'), findsOneWidget);
    await tester.tap(find.text('Add a contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Mum');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile number'), '+998 90 123 45 67');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save contact'));
    await tester.pumpAndSettle();

    verify(() => safety.addContact('Mum', '+998901234567')).called(1);
    expect(find.text('Mum'), findsOneWidget);
    expect(find.text('1 of 3 added'), findsOneWidget);
  });

  testWidgets('rejects a number too short to dial before calling the server', (tester) async {
    when(() => safety.contacts()).thenAnswer((_) async => const []);
    await pump(tester);
    await tester.tap(find.text('Add a contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Mum');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile number'), '12345');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save contact'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a mobile number'), findsOneWidget);
    verifyNever(() => safety.addContact(any(), any()));
  });

  testWidgets('a local number is saved with the market country code', (tester) async {
    Market.current = Market.india;
    addTearDown(() => Market.current = Market.unitedStates);
    when(() => safety.contacts()).thenAnswer((_) async => const []);
    when(() => safety.addContact(any(), any())).thenAnswer(
        (_) async => const EmergencyContact(id: 'n', name: 'Mum', phone: '+919876543210'));
    await pump(tester);
    await tester.tap(find.text('Add a contact'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Name'), 'Mum');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Mobile number'), '098765 43210');
    await tester.tap(find.widgetWithText(PrimaryButton, 'Save contact'));
    await tester.pumpAndSettle();

    // Texted during an SOS, so it must be the full international number.
    verify(() => safety.addContact('Mum', '+919876543210')).called(1);
  });

  testWidgets('at the limit it stops offering to add and says why', (tester) async {
    when(() => safety.contacts()).thenAnswer((_) async => const [
          EmergencyContact(id: 'a', name: 'Mum', phone: '+998901110001'),
          EmergencyContact(id: 'b', name: 'Dad', phone: '+998901110002'),
          EmergencyContact(id: 'c', name: 'Sis', phone: '+998901110003'),
        ]);
    await pump(tester);

    expect(find.byType(FloatingActionButton), findsNothing);
    expect(find.textContaining('maximum of 3'), findsOneWidget);
  });

  testWidgets('removing asks first, and a failed removal puts the contact back', (tester) async {
    when(() => safety.contacts()).thenAnswer((_) async => const [
          EmergencyContact(id: 'a', name: 'Mum', phone: '+998901110001'),
        ]);
    when(() => safety.removeContact('a'))
        .thenThrow(const ApiException('Server error'));
    await pump(tester);

    await tester.tap(find.byTooltip('Remove Mum'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Mum?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
    await tester.pumpAndSettle();

    expect(find.text('Mum'), findsOneWidget);
    expect(find.text('Server error'), findsOneWidget);
  });
}
