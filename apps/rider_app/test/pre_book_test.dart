import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class _MockRepo extends Mock implements TripRepository {}

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
        FareTier(tier: 'economy', label: 'Economy', capacity: 4, fare: economy, currency: 'USD', etaSeconds: null),
        const FareTier(tier: 'comfort', label: 'Comfort', capacity: 4, fare: 14.5, currency: 'USD', etaSeconds: null),
      ],
    );

void main() {
  late _MockRepo repo;
  setUpAll(() => registerFallbackValue(_home));
  setUp(() => repo = _MockRepo());

  Future<void> pump(WidgetTester tester,
      {DateTime? at, GeoPoint? to, String? toAddr}) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: PreBookPage(
        repository: repo,
        pickup: _home,
        pickupAddr: 'Chorsu Bazaar',
        paymentMode: 'cash',
        initialWhen: at,
        initialDropoff: to,
        initialDropoffAddr: toAddr,
      ),
    ));
    await tester.pumpAndSettle();
  }

  PrimaryButton button(WidgetTester t) => t.widget<PrimaryButton>(find.byType(PrimaryButton));

  testWidgets('starts from where the current ride ends', (tester) async {
    await pump(tester);
    expect(find.text('Chorsu Bazaar'), findsOneWidget);
    expect(find.text('Where to?'), findsOneWidget);
    expect(button(tester).onPressed, isNull);
  });

  testWidgets('schedules the chosen ride at the chosen time and quoted fare', (tester) async {
    final at = DateTime.now().add(const Duration(days: 1));
    when(() => repo.estimate(any(), any())).thenAnswer((_) async => _estimate(9.2));
    when(() => repo.createTrip(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          tier: any(named: 'tier'),
          pickupAddr: any(named: 'pickupAddr'),
          dropoffAddr: any(named: 'dropoffAddr'),
          paymentMode: any(named: 'paymentMode'),
          scheduledAt: any(named: 'scheduledAt'),
          quotedFare: any(named: 'quotedFare'),
          quotedSurge: any(named: 'quotedSurge'),
        )).thenAnswer((_) async => Trip(
          id: 'scheduled-1',
          status: TripStatus.scheduled,
          tier: 'economy',
          pickup: const TripEndpoint(point: _home),
          dropoff: const TripEndpoint(point: _office),
          scheduledAt: at,
        ));
    await pump(tester, at: at, to: _office, toAddr: 'Tashkent City');

    expect(find.text(r'Schedule Economy · $9.20'), findsOneWidget);
    await tester.tap(find.text('Comfort'));
    await tester.pump();
    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();

    verify(() => repo.createTrip(
          pickup: _home,
          dropoff: _office,
          tier: 'comfort',
          pickupAddr: 'Chorsu Bazaar',
          dropoffAddr: 'Tashkent City',
          paymentMode: 'cash',
          scheduledAt: at,
          quotedFare: 14.5,
          quotedSurge: 1,
        )).called(1);
  });

  testWidgets('a price that moved is re-estimated and explained', (tester) async {
    final at = DateTime.now().add(const Duration(days: 1));
    var estimates = 0;
    when(() => repo.estimate(any(), any()))
        .thenAnswer((_) async => _estimate(++estimates == 1 ? 9.2 : 11.0));
    when(() => repo.createTrip(
          pickup: any(named: 'pickup'),
          dropoff: any(named: 'dropoff'),
          tier: any(named: 'tier'),
          pickupAddr: any(named: 'pickupAddr'),
          dropoffAddr: any(named: 'dropoffAddr'),
          paymentMode: any(named: 'paymentMode'),
          scheduledAt: any(named: 'scheduledAt'),
          quotedFare: any(named: 'quotedFare'),
          quotedSurge: any(named: 'quotedSurge'),
        )).thenThrow(const ApiException('moved', statusCode: 409, code: 'PRICE_CHANGED'));
    await pump(tester, at: at, to: _office, toAddr: 'Tashkent City');

    await tester.tap(find.byType(PrimaryButton));
    await tester.pumpAndSettle();
    expect(find.textContaining('Prices changed'), findsOneWidget);
    expect(find.text(r'Schedule Economy · $11'), findsOneWidget);
  });
}
