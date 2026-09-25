import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/home/home_cards.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripRepository extends Mock implements TripRepository {}

class MockPayments extends Mock implements PaymentsRemoteDataSource {}

class MockRatings extends Mock implements RatingsRemoteDataSource {}

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

class _NoRealtime implements RealtimeClient {
  @override
  Future<void> connect(String token) async {}
  @override
  Future<void> connectWith(AccessTokenProvider tokenProvider) async {}
  @override
  void disconnect() {}
  @override
  bool get isConnected => false;
  @override
  Stream<Map<String, dynamic>> on(String event) => const Stream.empty();
  @override
  Stream<void> get reconnects => const Stream.empty();
  @override
  Stream<bool> get connection => const Stream.empty();
  @override
  void emit(String event, Map<String, dynamic> data) {}
}

const welcome = AvailablePromo(
  code: 'WELCOME50',
  title: 'Welcome offer',
  description: 'Half price on a ride — one use per rider.',
  kind: 'percent',
  value: 50,
  maxDiscount: 100,
);
final airport = AvailablePromo(
  code: 'AIRPORT100',
  title: 'Airport run',
  kind: 'flat',
  value: 100,
  minFare: 400,
  usesLeftForMe: 2,
  expiresAt: DateTime(2030, 10, 3),
);

const pickup = GeoPoint(18.52, 73.85);
const dropoff = GeoPoint(18.53, 73.87);
const estimate = TripEstimate(
  distanceM: 6000,
  durationS: 720,
  polyline: '',
  surge: 1,
  currency: 'INR',
  pickup: pickup,
  dropoff: dropoff,
  tiers: [
    FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 88,
        currency: 'INR',
        etaSeconds: 240),
    FareTier(
        tier: 'comfort',
        label: 'Comfort',
        capacity: 4,
        fare: 300,
        currency: 'INR',
        etaSeconds: 300),
  ],
);

void main() {
  setUp(() => Market.current = Market.india);
  tearDown(() => Market.current = Market.unitedStates);

  group('AvailablePromo copy', () {
    test('percent with a cap, flat with a minimum', () {
      expect(welcome.headline, '50% off, up to ₹100');
      expect(welcome.conditions, '1 use left');
      expect(airport.headline, '₹100 off');
      expect(airport.conditions, 'On fares over ₹400 · 2 uses left');
    });

    test('parses the API shape', () {
      final p = AvailablePromo.fromJson({
        'code': 'WEEKEND20',
        'title': 'Weekend saver',
        'description': null,
        'kind': 'percent',
        'value': 20,
        'maxDiscount': 60,
        'minFare': 0,
        'expiresAt': '2030-01-01T00:00:00.000Z',
        'usesLeftForMe': 4,
      });
      expect(p.headline, '20% off, up to ₹60');
      expect(p.usesLeftForMe, 4);
      expect(p.expiresAt!.toUtc(), DateTime.utc(2030));
    });
  });

  group('OffersPage', () {
    Future<void> pump(
      WidgetTester tester, {
      required Future<List<AvailablePromo>> Function() load,
      String? selected,
      void Function(AvailablePromo)? onApply,
      VoidCallback? onRemove,
    }) async {
      tester.view.physicalSize = const Size(411 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.light,
        home: OffersPage(
          load: load,
          selectedCode: selected,
          onApply: onApply ?? (_) {},
          onRemove: onRemove ?? () {},
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('lists the real offers with terms, code and Apply',
        (tester) async {
      AvailablePromo? applied;
      await pump(
        tester,
        load: () async => [welcome, airport],
        onApply: (o) => applied = o,
      );
      expect(find.text('Welcome offer'), findsOneWidget);
      expect(find.text('50% off, up to ₹100'), findsOneWidget);
      expect(find.text('WELCOME50'), findsOneWidget);
      expect(find.text('Airport run'), findsOneWidget);
      expect(find.text('On fares over ₹400 · 2 uses left · Ends 3 Oct 2030'),
          findsOneWidget);
      // The hero's full label, the ticket's short pill (same spoken label).
      expect(find.text('Apply to next ride'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);
      await tester.tap(find.text('Apply to next ride'));
      expect(applied, welcome);
    });

    testWidgets('the picked offer shows as applied, with Remove',
        (tester) async {
      var removed = false;
      await pump(
        tester,
        load: () async => [welcome, airport],
        selected: 'WELCOME50',
        onRemove: () => removed = true,
      );
      expect(find.text('Applied — will be used on your next ride'),
          findsOneWidget);
      expect(find.text('Apply'), findsOneWidget); // the other
      await tester.tap(find.text('Remove'));
      expect(removed, isTrue);
    });

    testWidgets('Copy puts the code on the clipboard', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(tester, load: () async => [welcome]);
      await tester.tap(find.byIcon(PhosphorIconsRegular.copy));
      await tester.pump();
      expect(copied, 'WELCOME50');
      expect(find.text('Code WELCOME50 copied'), findsOneWidget);
    });

    testWidgets('empty state when there are no offers', (tester) async {
      await pump(tester, load: () async => const []);
      expect(find.text('No offers right now'), findsOneWidget);
    });

    testWidgets('error state retries', (tester) async {
      var calls = 0;
      await pump(tester, load: () async {
        calls++;
        if (calls == 1) throw ApiException('offline');
        return [welcome];
      });
      expect(find.text("Couldn't load offers"), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Welcome offer'), findsOneWidget);
    });
  });

  test('expiry label: today, this year, another year', () {
    final now = DateTime(2026, 9, 25, 10);
    expect(offerExpiryLabel(DateTime(2026, 9, 25, 23), now: now), 'Ends today');
    expect(offerExpiryLabel(DateTime(2026, 10, 3), now: now), 'Ends 3 Oct');
    expect(offerExpiryLabel(DateTime(2027, 1, 2), now: now), 'Ends 2 Jan 2027');
  });

  test('Home banners from offers: title headline, photo, tap picks it', () {
    AvailablePromo? picked;
    final banners = promosFromOffers([welcome], onPick: (o) => picked = o);
    expect(banners.single.headline, 'Welcome offer');
    expect(banners.single.subline, '50% off, up to ₹100 · code WELCOME50');
    expect(banners.single.image, isNotNull);
    banners.single.onTap!();
    expect(picked, welcome);
  });

  group('TripCubit offer → next ride', () {
    late MockTripRepository repo;
    final realtime = _NoRealtime();

    setUpAll(() => registerFallbackValue(const GeoPoint(0, 0)));
    setUp(() {
      repo = MockTripRepository();
      when(() => repo.estimate(any(), any())).thenAnswer((_) async => estimate);
      when(() => repo.quotePromo('WELCOME50', 88)).thenAnswer((_) async =>
          const PromoQuote(
              code: 'WELCOME50',
              kind: 'percent',
              discount: 44,
              subtotal: 88,
              net: 44));
      when(() => repo.quotePromo('WELCOME50', 300)).thenAnswer((_) async =>
          const PromoQuote(
              code: 'WELCOME50',
              kind: 'percent',
              discount: 100,
              subtotal: 300,
              net: 200));
    });

    TripCubit build() => TripCubit(repo, realtime, MockPayments(), MockRatings());

    test('picked offer is applied, priced, on the next ride sheet', () async {
      final c = build();
      await c.selectOffer(welcome);
      expect(c.state.offerPromo, welcome);
      c.reset(); // between rides
      expect(c.state.offerPromo, welcome);
      await c.chooseDestination(pickup: pickup, dropoff: dropoff);
      expect(c.state.phase, TripPhase.choosingRide);
      expect(c.state.appliedPromo?.code, 'WELCOME50');
      expect(c.state.discountedFare, 44);
      // A different tier re-prices the discount (capped at 100).
      await c.selectTier('comfort');
      expect(c.state.appliedPromo?.discount, 100);
      expect(c.state.discountedFare, 200);
      await c.close();
    });

    test('removing the applied offer code drops the offer', () async {
      final c = build();
      await c.selectOffer(welcome);
      await c.chooseDestination(pickup: pickup, dropoff: dropoff);
      c.removePromo();
      expect(c.state.appliedPromo, isNull);
      expect(c.state.offerPromo, isNull);
      await c.close();
    });

    test('a rejected offer keeps the reason for the rider', () async {
      when(() => repo.quotePromo('WELCOME50', 88))
          .thenThrow(ApiException('You have already used this promo code.'));
      final c = build();
      await c.selectOffer(welcome);
      await c.chooseDestination(pickup: pickup, dropoff: dropoff);
      expect(c.state.appliedPromo, isNull);
      expect(c.state.promoError, 'You have already used this promo code.');
      await c.close();
    });

    test('booking with the offer spends it', () async {
      when(() => repo.createTrip(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            tier: any(named: 'tier'),
            pickupAddr: any(named: 'pickupAddr'),
            dropoffAddr: any(named: 'dropoffAddr'),
            pickupNote: any(named: 'pickupNote'),
            passenger: any(named: 'passenger'),
            promoCode: any(named: 'promoCode'),
            paymentMode: any(named: 'paymentMode'),
            paymentMethodId: any(named: 'paymentMethodId'),
            scheduledAt: any(named: 'scheduledAt'),
            stops: any(named: 'stops'),
            quotedFare: any(named: 'quotedFare'),
            quotedSurge: any(named: 'quotedSurge'),
          )).thenAnswer((_) async => const Trip(
            id: 't1',
            status: TripStatus.requested,
            tier: 'economy',
            pickup: TripEndpoint(point: pickup),
            dropoff: TripEndpoint(point: dropoff),
          ));
      final c = build();
      await c.selectOffer(welcome);
      await c.chooseDestination(pickup: pickup, dropoff: dropoff);
      await c.confirmRide();
      verify(() => repo.createTrip(
            pickup: any(named: 'pickup'),
            dropoff: any(named: 'dropoff'),
            tier: any(named: 'tier'),
            pickupAddr: any(named: 'pickupAddr'),
            dropoffAddr: any(named: 'dropoffAddr'),
            pickupNote: any(named: 'pickupNote'),
            passenger: any(named: 'passenger'),
            promoCode: 'WELCOME50',
            paymentMode: any(named: 'paymentMode'),
            paymentMethodId: any(named: 'paymentMethodId'),
            scheduledAt: any(named: 'scheduledAt'),
            stops: any(named: 'stops'),
            quotedFare: any(named: 'quotedFare'),
            quotedSurge: any(named: 'quotedSurge'),
          )).called(1);
      expect(c.state.offerPromo, isNull);
      await c.close();
    });
  });

  testWidgets('choose-ride sheet shows the offer applied and the net fare',
      (tester) async {
    const state = TripState(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'economy',
      dropoffAddr: 'Somewhere',
      offerPromo: welcome,
      appliedPromo: PromoQuote(
          code: 'WELCOME50', kind: 'percent', discount: 44, subtotal: 88, net: 44),
    );
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    tester.view.physicalSize = const Size(411 * 3, 2800);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: BlocProvider<TripCubit>.value(
          value: cubit,
          child: Align(
            alignment: Alignment.bottomCenter,
            child: RideSheetForPhase(
                state: state, onSearch: () {}, onPickSaved: (_) {}),
          ),
        ),
      ),
    ));
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.textContaining('WELCOME50 applied', skipOffstage: false),
        findsOneWidget);
    expect(find.textContaining('₹44', skipOffstage: false), findsWidgets);
  });
}
