import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class _MockRepo extends Mock implements TripRepository {}

class _MockPayments extends Mock implements PaymentsRemoteDataSource {}

const _home = GeoPoint(41.33, 69.28);
const _office = GeoPoint(41.31, 69.24);

TripEstimate _estimate(double economy) => TripEstimate(
  distanceM: 6000,
  durationS: 900,
  polyline: '',
  surge: 1,
  currency: 'USD',
  pickup: _home,
  dropoff: _office,
  tiers: [
    FareTier(
      tier: 'economy',
      label: 'Economy',
      capacity: 4,
      fare: economy,
      currency: 'USD',
      etaSeconds: null,
    ),
    const FareTier(
      tier: 'comfort',
      label: 'Comfort',
      capacity: 4,
      fare: 14.5,
      currency: 'USD',
      etaSeconds: null,
    ),
  ],
);

void main() {
  late _MockRepo repo;
  setUpAll(() => registerFallbackValue(_home));
  setUp(() => repo = _MockRepo());

  Future<void> pump(
    WidgetTester tester, {
    DateTime? at,
    GeoPoint? to,
    String? toAddr,
    String mode = 'cash',
    PaymentsRemoteDataSource? payments,
  }) async {
    // A phone-tall screen, so the tiers, notices and the pay chips all fit.
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: PreBookPage(
          repository: repo,
          pickup: _home,
          pickupAddr: 'Chorsu Bazaar',
          paymentMode: mode,
          payments: payments,
          initialWhen: at,
          initialDropoff: to,
          initialDropoffAddr: toAddr,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PrimaryButton button(WidgetTester t) =>
      t.widget<PrimaryButton>(find.byType(PrimaryButton));

  testWidgets('starts from where the current ride ends', (tester) async {
    await pump(tester);
    expect(find.text('Chorsu Bazaar'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(button(tester).onPressed, isNull);
  });

  testWidgets('schedules the chosen ride at the chosen time and quoted fare', (
    tester,
  ) async {
    final at = DateTime.now().add(const Duration(days: 1));
    when(
      () => repo.estimate(any(), any()),
    ).thenAnswer((_) async => _estimate(9.2));
    when(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        paymentMode: any(named: 'paymentMode'),
        scheduledAt: any(named: 'scheduledAt'),
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
      ),
    ).thenAnswer(
      (_) async => Trip(
        id: 'scheduled-1',
        status: TripStatus.scheduled,
        tier: 'economy',
        pickup: const TripEndpoint(point: _home),
        dropoff: const TripEndpoint(point: _office),
        scheduledAt: at,
      ),
    );
    await pump(tester, at: at, to: _office, toAddr: 'Tashkent City');

    expect(find.text(r'Schedule Economy · $9.20'), findsOneWidget);
    await tester.tap(find.text('Comfort'));
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();

    verify(
      () => repo.createTrip(
        pickup: _home,
        dropoff: _office,
        tier: 'comfort',
        pickupAddr: 'Chorsu Bazaar',
        dropoffAddr: 'Tashkent City',
        paymentMode: 'cash',
        scheduledAt: at,
        quotedFare: 14.5,
        quotedSurge: 1,
      ),
    ).called(1);
  });

  testWidgets('a price that moved is re-estimated and explained', (
    tester,
  ) async {
    final at = DateTime.now().add(const Duration(days: 1));
    var estimates = 0;
    when(
      () => repo.estimate(any(), any()),
    ).thenAnswer((_) async => _estimate(++estimates == 1 ? 9.2 : 11.0));
    when(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        paymentMode: any(named: 'paymentMode'),
        scheduledAt: any(named: 'scheduledAt'),
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
      ),
    ).thenThrow(
      const ApiException('moved', statusCode: 409, code: 'PRICE_CHANGED'),
    );
    await pump(tester, at: at, to: _office, toAddr: 'Tashkent City');

    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prices changed'), findsOneWidget);
    expect(find.text(r'Schedule Economy · $11'), findsOneWidget);
  });

  void stubCreate(DateTime at) {
    when(
      () => repo.estimate(any(), any()),
    ).thenAnswer((_) async => _estimate(9.2));
    when(
      () => repo.createTrip(
        pickup: any(named: 'pickup'),
        dropoff: any(named: 'dropoff'),
        tier: any(named: 'tier'),
        pickupAddr: any(named: 'pickupAddr'),
        dropoffAddr: any(named: 'dropoffAddr'),
        paymentMode: any(named: 'paymentMode'),
        paymentMethodId: any(named: 'paymentMethodId'),
        scheduledAt: any(named: 'scheduledAt'),
        quotedFare: any(named: 'quotedFare'),
        quotedSurge: any(named: 'quotedSurge'),
      ),
    ).thenAnswer(
      (_) async => Trip(
        id: 'scheduled-1',
        status: TripStatus.scheduled,
        tier: 'economy',
        pickup: const TripEndpoint(point: _home),
        dropoff: const TripEndpoint(point: _office),
        scheduledAt: at,
      ),
    );
  }

  List<dynamic> sent() => verify(
    () => repo.createTrip(
      pickup: any(named: 'pickup'),
      dropoff: any(named: 'dropoff'),
      tier: any(named: 'tier'),
      pickupAddr: any(named: 'pickupAddr'),
      dropoffAddr: any(named: 'dropoffAddr'),
      paymentMode: captureAny(named: 'paymentMode'),
      paymentMethodId: captureAny(named: 'paymentMethodId'),
      scheduledAt: any(named: 'scheduledAt'),
      quotedFare: any(named: 'quotedFare'),
      quotedSurge: any(named: 'quotedSurge'),
    ),
  ).captured;

  bool chipSelected(WidgetTester tester, String key) => tester
      .widgetList<Semantics>(
        find.descendant(
          of: find.byKey(Key(key)),
          matching: find.byType(Semantics),
        ),
      )
      .any((s) => s.properties.selected == true);

  testWidgets('the rider picks Cash or Card, and the booking uses the pick', (
    tester,
  ) async {
    final at = DateTime.now().add(const Duration(days: 1));
    stubCreate(at);
    final payments = _MockPayments();
    when(() => payments.methods()).thenAnswer(
      (_) async => [
        {'id': 'pm_1', 'brand': 'visa', 'last4': '4242', 'isDefault': true},
      ],
    );
    await pump(
      tester,
      at: at,
      to: _office,
      toAddr: 'Tashkent City',
      payments: payments,
    );

    expect(find.textContaining('4242'), findsOneWidget);
    expect(chipSelected(tester, 'prebook-pay-cash'), isTrue);

    // Opened on Cash; switch to the card and book.
    await tester.ensureVisible(find.byKey(const Key('prebook-pay-card')));
    await tester.tap(find.byKey(const Key('prebook-pay-card')));
    await tester.pump();
    expect(chipSelected(tester, 'prebook-pay-card'), isTrue);
    expect(chipSelected(tester, 'prebook-pay-cash'), isFalse);
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(sent(), ['card', 'pm_1']);
  });

  testWidgets('with no card on file it starts on Cash and books cash', (
    tester,
  ) async {
    final at = DateTime.now().add(const Duration(days: 1));
    stubCreate(at);
    final payments = _MockPayments();
    when(() => payments.methods()).thenAnswer((_) async => []);
    await pump(
      tester,
      at: at,
      to: _office,
      toAddr: 'Tashkent City',
      mode: 'card',
      payments: payments,
    );

    expect(find.text('Add card'), findsOneWidget);
    expect(chipSelected(tester, 'prebook-pay-cash'), isTrue);
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(sent(), ['cash', null]);
  });

  testWidgets(
    'the time picker is a 12-hour clock with AM/PM on a 24-hour phone',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
          home: PreBookPage(
            repository: repo,
            pickup: _home,
            pickupAddr: 'Chorsu Bazaar',
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a date and time'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OK')); // the date
      await tester.pumpAndSettle();
      expect(find.text('Pickup time'), findsOneWidget);
      expect(find.text('AM'), findsOneWidget);
      expect(find.text('PM'), findsOneWidget);
      // The dial runs 1–12 only — no 13–23 / 00 ring. The header's minutes
      // can legitimately read "00" (the suggested time is rounded, so on
      // some clocks it lands on the hour); a 24-hour inner ring would add a
      // second "00" and the 13–23 labels.
      expect(find.text('13'), findsNothing);
      expect(find.text('00').evaluate().length, lessThanOrEqualTo(1));
    },
  );
}
