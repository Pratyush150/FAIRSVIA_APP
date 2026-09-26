// "Book for someone else" with a wrong number used to dead-end: the server's
// 400 landed on an error card with only "Try again", and Android back closed
// the app. These cover the fixes: the dialog refuses a bad number, a booking
// error keeps the ride options, the error card has Back, and system back
// steps back one level (never out of a live ride).
import 'package:bloc_test/bloc_test.dart';
import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

import 'trip_cubit_test.dart'
    show FakeRealtimeClient, MockPayments, MockRatings, MockTripRepository;

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

const pickup = GeoPoint(18.52, 73.85);
const dropoff = GeoPoint(18.55, 73.90);
const estimate = TripEstimate(
  distanceM: 5000,
  durationS: 900,
  polyline: 'abcd',
  surge: 1,
  currency: 'INR',
  pickup: pickup,
  dropoff: dropoff,
  tiers: [
    FareTier(
      tier: 'economy',
      label: 'Economy',
      capacity: 4,
      fare: 142.98,
      currency: 'INR',
      etaSeconds: 300,
    ),
  ],
);
const choosing = TripState(
  phase: TripPhase.choosingRide,
  pickup: pickup,
  dropoff: dropoff,
  estimate: estimate,
  selectedTier: 'economy',
  passenger: TripPassenger(phone: '+911234567890', name: 'Asha'),
);

void _stubCreateTrip(MockTripRepository repo, Object error) => when(
  () => repo.createTrip(
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
  ),
).thenThrow(error);

Widget _sheet(TripCubit cubit, TripState s) => MaterialApp(
  theme: AppTheme.light,
  home: Scaffold(
    body: BlocProvider<TripCubit>.value(
      value: cubit,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: RideSheetForPhase(
          state: s,
          onSearch: () {},
          onPickSaved: (_) {},
        ),
      ),
    ),
  ),
);

void main() {
  late MockTripRepository repo;
  late Market originalMarket;
  setUpAll(() => registerFallbackValue(const GeoPoint(0, 0)));
  setUp(() {
    repo = MockTripRepository();
    originalMarket = Market.current;
    Market.current = Market.india;
  });
  tearDown(() => Market.current = originalMarket);

  TripCubit realCubit() =>
      TripCubit(repo, FakeRealtimeClient(), MockPayments(), MockRatings());

  group('validPassengerPhone (India)', () {
    test('accepts a 10-digit mobile starting 6-9', () {
      expect(validPassengerPhone('98765 43210'), '+919876543210');
      expect(validPassengerPhone('+91 62345 67890'), '+916234567890');
    });
    test('rejects a landline-looking, short or long number', () {
      expect(validPassengerPhone('12345 67890'), isNull);
      expect(validPassengerPhone('98765 4321'), isNull);
      expect(validPassengerPhone('98765 432100'), isNull);
      expect(validPassengerPhone(''), isNull);
    });
  });

  group('passenger dialog', () {
    Future<List<TripPassenger?>> open(WidgetTester tester) async {
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

    FilledButton done(WidgetTester tester) =>
        tester.widget<FilledButton>(find.byKey(const Key('passenger-done')));

    testWidgets('Done stays disabled and says why for a bad number', (
      tester,
    ) async {
      final results = await open(tester);
      expect(done(tester).onPressed, isNull);
      await tester.enterText(
        find.byKey(const Key('passenger-phone')),
        '12345 67890',
      );
      await tester.pump();
      expect(done(tester).onPressed, isNull);
      expect(find.text(invalidPassengerPhoneMessage), findsOneWidget);
      await tester.tap(find.byKey(const Key('passenger-done')));
      await tester.pumpAndSettle();
      expect(results, isEmpty, reason: 'dialog must not return');
    });

    testWidgets('a valid number enables Done and returns E.164', (
      tester,
    ) async {
      final results = await open(tester);
      await tester.enterText(
        find.byKey(const Key('passenger-phone')),
        '98765 43210',
      );
      await tester.pump();
      expect(find.text(invalidPassengerPhoneMessage), findsNothing);
      await tester.tap(find.byKey(const Key('passenger-done')));
      await tester.pumpAndSettle();
      expect(results.single?.phone, '+919876543210');
    });
  });

  group('booking error keeps the ride options', () {
    blocTest<TripCubit, TripState>(
      'server 400 on passengerPhone -> choosingRide, estimate kept, plain text',
      setUp: () => _stubCreateTrip(
        repo,
        const ApiException(
          'passengerPhone must be a valid phone number',
          statusCode: 400,
        ),
      ),
      build: realCubit,
      seed: () => choosing,
      act: (c) => c.confirmRide(),
      expect: () => [
        isA<TripState>().having((s) => s.phase, 'phase', TripPhase.requesting),
        isA<TripState>()
            .having((s) => s.phase, 'phase', TripPhase.choosingRide)
            .having((s) => s.estimate, 'estimate', estimate)
            .having((s) => s.selectedTier, 'tier', 'economy')
            .having((s) => s.passenger?.name, 'passenger', 'Asha')
            .having((s) => s.error, 'error', TripCubit.passengerPhoneInvalid),
      ],
    );

    testWidgets('the sheet shows the error and Edit passenger opens the '
        'dialog prefilled', (tester) async {
      final cubit = MockTripCubit();
      final s = choosing.copyWith(error: TripCubit.passengerPhoneInvalid);
      whenListen(cubit, const Stream<TripState>.empty(), initialState: s);
      await tester.pumpWidget(_sheet(cubit, s));
      await tester.pumpAndSettle();
      expect(find.text(TripCubit.passengerPhoneInvalid), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('edit-passenger')));
      await tester.tap(find.byKey(const Key('edit-passenger')));
      await tester.pumpAndSettle();
      expect(find.text('Who is riding?'), findsOneWidget);
      expect(find.text('Asha'), findsOneWidget);
      // The bad number is prefilled and Done is held until it is fixed.
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('passenger-done')))
            .onPressed,
        isNull,
      );
    });
  });

  group('error card Back', () {
    testWidgets('Back calls backFromError', (tester) async {
      final cubit = MockTripCubit();
      const s = TripState(phase: TripPhase.error, error: 'Boom');
      whenListen(cubit, const Stream<TripState>.empty(), initialState: s);
      await tester.pumpWidget(_sheet(cubit, s));
      await tester.pumpAndSettle();
      expect(find.text('Try again'), findsOneWidget);
      await tester.tap(find.byKey(const Key('error-back')));
      verify(cubit.backFromError).called(1);
    });

    blocTest<TripCubit, TripState>(
      'backFromError with an estimate -> choosingRide',
      build: realCubit,
      seed: () => choosing.copyWith(phase: TripPhase.error, error: 'x'),
      act: (c) => c.backFromError(),
      expect: () => [
        isA<TripState>()
            .having((s) => s.phase, 'phase', TripPhase.choosingRide)
            .having((s) => s.error, 'error', isNull)
            .having((s) => s.estimate, 'estimate', estimate),
      ],
    );

    blocTest<TripCubit, TripState>(
      'backFromError without an estimate -> idle',
      build: realCubit,
      seed: () => const TripState(phase: TripPhase.error, error: 'x'),
      act: (c) => c.backFromError(),
      expect: () => [
        isA<TripState>().having((s) => s.phase, 'phase', TripPhase.idle),
      ],
    );
  });

  group('system back', () {
    // The same PopScope wiring the rider home uses (home_page.dart), driven
    // by a real cubit and a real system back (handlePopRoute).
    Future<(TripCubit, List<String>)> pump(
      WidgetTester tester,
      TripState seed,
    ) async {
      final cubit = realCubit();
      // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
      cubit.emit(seed);
      final popped = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [_PopObserver(popped)],
          home: const Text('below'),
        ),
      );
      final nav = tester.state<NavigatorState>(find.byType(Navigator));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => BlocProvider<TripCubit>.value(
            value: cubit,
            child: BlocBuilder<TripCubit, TripState>(
              builder: (context, state) =>
                  RiderHomeBackScope(state: state, child: const Text('home')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return (cubit, popped);
    }

    Future<void> back(WidgetTester tester) async {
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }

    testWidgets('choosingRide -> idle', (tester) async {
      final (cubit, popped) = await pump(tester, choosing);
      await back(tester);
      expect(cubit.state.phase, TripPhase.idle);
      expect(popped, isEmpty);
    });

    testWidgets('error -> choosingRide', (tester) async {
      final (cubit, popped) = await pump(
        tester,
        choosing.copyWith(phase: TripPhase.error, error: 'x'),
      );
      await back(tester);
      expect(cubit.state.phase, TripPhase.choosingRide);
      expect(popped, isEmpty);
    });

    testWidgets('onTrip stays put (never cancels, never exits)', (
      tester,
    ) async {
      final (cubit, popped) = await pump(
        tester,
        choosing.copyWith(phase: TripPhase.onTrip),
      );
      await back(tester);
      expect(cubit.state.phase, TripPhase.onTrip);
      expect(popped, isEmpty);
      expect(find.text('home'), findsOneWidget);
    });

    testWidgets('idle pops', (tester) async {
      final (_, popped) = await pump(tester, const TripState());
      await back(tester);
      expect(popped, isNotEmpty);
      expect(find.text('below'), findsOneWidget);
    });
  });
}

class _PopObserver extends NavigatorObserver {
  _PopObserver(this.popped);
  final List<String> popped;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      popped.add('pop');
}
