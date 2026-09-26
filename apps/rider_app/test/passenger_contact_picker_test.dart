import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/contact_picker.dart';
import 'package:rider_app/features/trip/sheets/ride_sheets.dart';
import 'package:shared_models/shared_models.dart';

class _FakePicker implements ContactPicker {
  _FakePicker(this.result, {this.error});
  final PickedContact? result;
  final Object? error;
  int calls = 0;
  @override
  Future<PickedContact?> pick() async {
    calls++;
    if (error != null) throw error!;
    return result;
  }
}

void main() {
  late ContactPicker original;
  late Market originalMarket;
  setUp(() {
    original = ContactPicker.instance;
    originalMarket = Market.current;
    Market.current = Market.india;
  });
  tearDown(() {
    ContactPicker.instance = original;
    Market.current = originalMarket;
  });

  group('normalizeContactPhone', () {
    test('keeps a + country code, strips spaces and dashes', () {
      expect(normalizeContactPhone('+998 90-123-45-67'), '+998901234567');
    });
    test('prefixes the market dial code, dropping a trunk 0', () {
      expect(normalizeContactPhone('098765 43210'), '+919876543210');
      expect(normalizeContactPhone('(98765) 43210'), '+919876543210');
    });
    test('00 is the international prefix', () {
      expect(normalizeContactPhone('00998 90 123 45 67'), '+998901234567');
    });
    test('uses the given market', () {
      expect(
        normalizeContactPhone('90 123 45 67', Market.uzbekistan),
        '+998901234567',
      );
    });
    test('junk or empty is null', () {
      expect(normalizeContactPhone(null), isNull);
      expect(normalizeContactPhone(''), isNull);
      expect(normalizeContactPhone('12'), isNull);
    });
  });

  Future<List<TripPassenger?>> openDialog(WidgetTester tester) async {
    final results = <TripPassenger?>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async =>
                  results.add(await askHomePassenger(context)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return results;
  }

  testWidgets('picking a contact fills name + normalised phone', (
    tester,
  ) async {
    final fake = _FakePicker(
      const PickedContact(name: 'Asha Rao', phone: '098765-43210'),
    );
    ContactPicker.instance = fake;
    final results = await openDialog(tester);

    expect(find.text('Pick from contacts'), findsOneWidget);
    await tester.tap(find.byKey(const Key('pick-from-contacts')));
    await tester.pumpAndSettle();
    expect(fake.calls, 1);
    expect(find.text('Asha Rao'), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(results.single?.phone, '+919876543210');
    expect(results.single?.name, 'Asha Rao');
  });

  testWidgets('cancelling the picker leaves typed values alone', (
    tester,
  ) async {
    ContactPicker.instance = _FakePicker(null);
    await openDialog(tester);
    await tester.enterText(find.byType(TextField).first, 'Typed Name');
    await tester.tap(find.byKey(const Key('pick-from-contacts')));
    await tester.pumpAndSettle();
    expect(find.text('Typed Name'), findsOneWidget);
    expect(find.textContaining("Couldn't open"), findsNothing);
  });

  testWidgets('picker failure shows a gentle error, dialog stays usable', (
    tester,
  ) async {
    ContactPicker.instance = _FakePicker(
      null,
      error: PlatformException(code: 'intent_error'),
    );
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('pick-from-contacts')));
    await tester.pumpAndSettle();
    expect(find.textContaining("Couldn't open your contacts"), findsOneWidget);
    expect(find.text('Who is riding?'), findsOneWidget);
  });

  testWidgets('contact without a usable number says so', (tester) async {
    ContactPicker.instance = _FakePicker(
      const PickedContact(name: 'No Number', phone: '12'),
    );
    await openDialog(tester);
    await tester.tap(find.byKey(const Key('pick-from-contacts')));
    await tester.pumpAndSettle();
    expect(find.text('No Number'), findsOneWidget);
    expect(
      find.text('That contact has no usable mobile number'),
      findsOneWidget,
    );
  });
}
