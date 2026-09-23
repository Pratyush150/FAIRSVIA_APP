import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockSafety extends Mock implements SafetyRemoteDataSource {}

const _c1 = EmergencyContact(id: 'a', name: 'Mum', phone: '+998901110001');
const _c2 = EmergencyContact(id: 'b', name: 'Dad', phone: '+998901110002');

SosResult _result({int notified = 0, int total = 0, bool repeat = false}) =>
    SosResult(
      incidentId: 'inc',
      contactsNotified: notified,
      contactsTotal: total,
      repeat: repeat,
      emergencyNumbers: const [],
    );

void main() {
  late _MockSafety safety;
  late List<Uri> dialled;

  setUp(() {
    safety = _MockSafety();
    dialled = [];
    when(() => safety.emergencyNumbers())
        .thenAnswer((_) async => EmergencyNumber.fallback);
    when(() => safety.contacts()).thenAnswer((_) async => const []);
  });

  Future<void> pump(WidgetTester tester, {SafetyLocator? locate}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SafetySheet(
          tripId: 't1',
          safety: safety,
          shareText: 'share',
          locate: locate,
          launch: (uri) async {
            dialled.add(uri);
            return true;
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> sendSos(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(PrimaryButton, 'Send SOS alert'));
    await tester.pumpAndSettle();
  }

  testWidgets('offers the local numbers from the server and dials them', (tester) async {
    when(() => safety.emergencyNumbers()).thenAnswer((_) async => const [
          EmergencyNumber('Police', '102'),
          EmergencyNumber('Ambulance', '103'),
        ]);
    await pump(tester);

    expect(find.text('911'), findsNothing);
    await tester.tap(find.text('103'));
    await tester.pump();
    expect(dialled.single.toString(), 'tel:103');
  });

  testWidgets('call buttons work even if the server cannot be reached', (tester) async {
    when(() => safety.emergencyNumbers())
        .thenThrow(const ApiException('offline'));
    await pump(tester);
    expect(find.text('102'), findsOneWidget);
  });

  testWidgets('with no contacts it says nobody will be texted — before and after', (tester) async {
    when(() => safety.raiseSos(any(), lat: any(named: 'lat'), lng: any(named: 'lng')))
        .thenAnswer((_) async => _result());
    await pump(tester);

    expect(find.textContaining('nobody you know will be texted'), findsOneWidget);
    await sendSos(tester);

    expect(find.textContaining('SOS sent to'), findsOneWidget);
    expect(find.textContaining('No emergency contacts were texted'), findsOneWidget);
    expect(find.textContaining('Stay on the line'), findsNothing);
  });

  testWidgets('names the contacts it will text, and sends the location', (tester) async {
    when(() => safety.contacts()).thenAnswer((_) async => const [_c1, _c2]);
    when(() => safety.raiseSos(any(), lat: any(named: 'lat'), lng: any(named: 'lng')))
        .thenAnswer((_) async => _result(notified: 2, total: 2));
    await pump(tester, locate: () async => (lat: 41.3, lng: 69.24));

    expect(find.textContaining('Texts Mum and Dad'), findsOneWidget);
    await sendSos(tester);

    verify(() => safety.raiseSos('t1', lat: 41.3, lng: 69.24)).called(1);
    expect(find.text('Texted your 2 emergency contacts.'), findsOneWidget);
  });

  testWidgets('says plainly when some contacts could not be texted', (tester) async {
    when(() => safety.contacts()).thenAnswer((_) async => const [_c1, _c2]);
    when(() => safety.raiseSos(any(), lat: any(named: 'lat'), lng: any(named: 'lng')))
        .thenAnswer((_) async => _result(notified: 1, total: 2));
    await pump(tester);
    await sendSos(tester);

    expect(find.textContaining("Texted 1 of 2 contacts — 1 couldn't be reached"),
        findsOneWidget);
  });

  testWidgets('a location that never comes does not stop the alert', (tester) async {
    when(() => safety.raiseSos(any(), lat: any(named: 'lat'), lng: any(named: 'lng')))
        .thenAnswer((_) async => _result());
    await pump(tester, locate: () async => throw Exception('no gps'));
    await sendSos(tester);

    verify(() => safety.raiseSos('t1')).called(1);
    expect(find.textContaining('SOS sent to'), findsOneWidget);
  });

  testWidgets('when the alert fails it says so and points to the call buttons', (tester) async {
    when(() => safety.raiseSos(any(), lat: any(named: 'lat'), lng: any(named: 'lng')))
        .thenThrow(const ApiException('No connection'));
    await pump(tester);
    await sendSos(tester);

    expect(find.textContaining("the alert wasn't sent"), findsOneWidget);
    expect(find.textContaining('SOS sent'), findsNothing);
    // Still possible to try again.
    expect(find.widgetWithText(PrimaryButton, 'Send SOS alert'), findsOneWidget);
  });
}
