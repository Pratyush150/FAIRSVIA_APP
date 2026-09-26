import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/ride_status.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// The rider trip-sheet fixes from the 2026-09-25 product audit
/// (docs/plans/audit-2026-09-25.md, A.12, A.14, A.20, A.21).
void main() {
  setUp(() => Market.current = Market.india);
  tearDown(() => Market.current = Market.unitedStates);

  const amit = AssignedDriver(
    id: 'd1',
    name: 'Amit Kumar',
    rating: 4.8,
    vehicleMake: 'Maruti Suzuki',
    vehicleModel: 'Dzire',
    vehicleColor: 'White',
    plate: 'MH12PM2285',
    phone: '+919876500011',
    etaSec: 540,
  );

  Trip trip({TripStatus status = TripStatus.accepted}) => Trip(
    id: 't1',
    status: status,
    tier: 'comfort',
    currency: 'INR',
    fareEstimate: 120,
    paymentMode: 'cash',
    startOtp: '4821',
    pickup: const TripEndpoint(point: GeoPoint(18.52, 73.85)),
    dropoff: const TripEndpoint(
      point: GeoPoint(18.53, 73.87),
      address: 'Pune Railway Station',
    ),
  );

  const estimate = TripEstimate(
    distanceM: 6000,
    durationS: 720,
    polyline: '',
    surge: 1,
    currency: 'INR',
    pickup: GeoPoint(18.52, 73.85),
    dropoff: GeoPoint(18.53, 73.87),
    tiers: [
      FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 89,
        currency: 'INR',
        etaSeconds: 240,
      ),
      FareTier(
        tier: 'comfort',
        label: 'Comfort',
        capacity: 4,
        fare: 120,
        currency: 'INR',
        etaSeconds: 300,
      ),
    ],
  );

  Future<void> pump(
    WidgetTester tester,
    TripState state,
    Widget child, {
    double width = 411,
    double textScale = 1,
  }) async {
    final cubit = MockTripCubit();
    when(() => cubit.reset()).thenReturn(null);
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    tester.view.physicalSize = Size(width * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        builder: (context, w) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: w!,
        ),
        home: Scaffold(
          body: BlocProvider<TripCubit>.value(
            value: cubit,
            child: SingleChildScrollView(
              child: Padding(
                // The sheet's own side gutters.
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('en-route headline never orphans "min" (A.21)', () {
    test('displayTitle glues the ETA phrase; title keeps plain spaces', () {
      final s = RideStatus.of(
        TripState(phase: TripPhase.driverEnRoute, driver: amit, trip: trip()),
      );
      expect(s.title, 'Amit arriving in 9 min');
      expect(s.displayTitle, 'Amit arriving in 9 min');
      // No ETA phrase: nothing to glue.
      final arrived = RideStatus.of(
        TripState(phase: TripPhase.driverArrived, driver: amit, trip: trip()),
      );
      expect(arrived.displayTitle, arrived.title);
    });

    for (final eta in [540, 720]) {
      testWidgets('"arriving in N min" on one line at 360 dp, 1.3× ($eta s)', (
        tester,
      ) async {
        final state = TripState(
          phase: TripPhase.driverEnRoute,
          driver: amit.copyWithEta(eta),
          trip: trip(),
        );
        await pump(
          tester,
          state,
          DriverInfoSheet(state: state, arrived: false),
          width: 360,
          textScale: 1.3,
        );
        expect(tester.takeException(), isNull);
        final title = RideStatus.of(state).displayTitle;
        final para = tester.renderObject<RenderParagraph>(find.text(title));
        final text = para.text.toPlainText();
        final start = text.indexOf('arriving');
        final boxes = para.getBoxesForSelection(
          TextSelection(baseOffset: start, extentOffset: text.length),
        );
        final tops = boxes.map((b) => b.top.round()).toSet();
        expect(
          tops,
          hasLength(1),
          reason: '"$text" split the ETA phrase across lines',
        );
        // At most two lines: "Amit / arriving in 9 min".
        final all = para.getBoxesForSelection(
          TextSelection(baseOffset: 0, extentOffset: text.length),
        );
        expect(
          all.map((b) => b.top.round()).toSet().length,
          lessThanOrEqualTo(2),
        );
      });
    }

    testWidgets('Safety sits under the headline, not beside it', (
      tester,
    ) async {
      final state = TripState(
        phase: TripPhase.driverEnRoute,
        driver: amit,
        trip: trip(),
      );
      await pump(
        tester,
        state,
        DriverInfoSheet(state: state, arrived: false),
        width: 360,
      );
      final title = RideStatus.of(state).displayTitle;
      expect(
        tester.getTopLeft(find.text('Safety')).dy,
        greaterThan(tester.getBottomLeft(find.text(title)).dy),
      );
    });
  });

  group('on trip (A.21)', () {
    TripState onTrip({String? phone = '+919876500011'}) => TripState(
      phase: TripPhase.onTrip,
      trip: trip(status: TripStatus.inProgress),
      driver: AssignedDriver(
        name: 'Amit Kumar',
        rating: 4.8,
        plate: 'MH12PM2285',
        phone: phone,
      ),
      estimate: estimate,
      liveEtaSec: 720,
      liveRemainingM: 6000,
      dropoffAddr: 'Pune Railway Station',
    );

    testWidgets('Call sits next to Message and dials the driver', (
      tester,
    ) async {
      final dialled = <String>[];
      final state = onTrip();
      await pump(
        tester,
        state,
        OnTripSheet(
          state: state,
          dialer: (p) async {
            dialled.add(p);
            return true;
          },
        ),
      );
      expect(find.byTooltip('Message driver'), findsOneWidget);
      expect(find.byTooltip('Call driver'), findsOneWidget);
      expect(
        tester.getCenter(find.byTooltip('Call driver')).dy,
        tester.getCenter(find.byTooltip('Message driver')).dy,
      );
      await tester.tap(find.byTooltip('Call driver'));
      await tester.pump();
      expect(dialled, ['+919876500011']);
    });

    testWidgets('no Call without a number', (tester) async {
      final state = onTrip(phone: null);
      await pump(tester, state, OnTripSheet(state: state));
      expect(find.byTooltip('Call driver'), findsNothing);
      expect(find.byTooltip('Message driver'), findsOneWidget);
    });

    testWidgets('a failed dial names the number spaced (A.13)', (tester) async {
      final state = onTrip();
      await pump(
        tester,
        state,
        OnTripSheet(state: state, dialer: (_) async => false),
      );
      await tester.tap(find.byTooltip('Call driver'));
      await tester.pump();
      expect(
        find.text("Couldn't open the dialler for +91 98765 00011"),
        findsOneWidget,
      );
    });

    testWidgets('"12 min" is shown once', (tester) async {
      final state = onTrip();
      await pump(tester, state, OnTripSheet(state: state));
      expect(find.textContaining('12 min'), findsOneWidget);
      // The clock and the distance are still there.
      expect(
        find.textContaining(RegExp(r'^Arriving \d+:\d\d [AP]M · ')),
        findsOneWidget,
      );
    });
  });

  group('choose ride after "no drivers" (A.20)', () {
    Future<void> pumpOptions(WidgetTester tester, TripState state) async {
      final cubit = MockTripCubit();
      whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: BlocProvider<TripCubit>.value(
              value: cubit,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: RideSheetForPhase(
                  state: state,
                  onSearch: () {},
                  onPickSaved: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    TripState choosing({String? error}) => TripState(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'economy',
      dropoffAddr: 'Pune Railway Station',
      error: error,
    );

    testWidgets('the tier that found no driver shows no pickup ETA', (
      tester,
    ) async {
      await pumpOptions(tester, choosing(error: TripCubit.noDriversNearby));
      expect(find.textContaining('Pickup in 4 min'), findsNothing);
      expect(find.text('No cars found — try again'), findsOneWidget);
      // The other tier's quote is untouched.
      expect(find.textContaining('Pickup in 5 min'), findsOneWidget);
    });

    testWidgets('without the no-drivers reply the ETA is shown', (
      tester,
    ) async {
      await pumpOptions(tester, choosing());
      expect(find.textContaining('Pickup in 4 min'), findsOneWidget);
    });
  });

  group('one formatter for plates and phones (A.12, A.13)', () {
    test('share text carries the spaced plate', () {
      final text = riderTripShareText(
        TripState(
          phase: TripPhase.onTrip,
          driver: amit,
          dropoffAddr: 'Pune Railway Station',
        ),
      );
      expect(text, contains('plate MH 12 PM 2285'));
      expect(text, isNot(contains('MH12PM2285')));
    });

    testWidgets('Ride details shows the spaced plate', (tester) async {
      final state = TripState(
        phase: TripPhase.onTrip,
        driver: amit,
        trip: trip(status: TripStatus.inProgress),
      );
      await pump(tester, state, RideDetailsContent(state: state));
      expect(find.text('MH 12 PM 2285'), findsOneWidget);
      expect(find.text('MH12PM2285'), findsNothing);
    });
  });

  group('driver card art (A.14)', () {
    test('known car: the neutral sedan; unknown: the tier art', () {
      expect(driverCardArtKey(amit, 'comfort'), 'driver');
      expect(
        driverCardArtKey(
          const AssignedDriver(name: 'Amit', rating: 4.8),
          'comfort',
        ),
        'comfort',
      );
      expect(driverCardArtKey(null, null), 'comfort');
      // An auto or a bike is never drawn as a sedan.
      expect(driverCardArtKey(amit, 'auto'), 'auto');
      expect(driverCardArtKey(amit, 'bike'), 'bike');
    });

    testWidgets('the card draws the driver art for a named car', (
      tester,
    ) async {
      final state = TripState(
        phase: TripPhase.driverEnRoute,
        driver: amit,
        trip: trip(),
      );
      await pump(tester, state, DriverInfoSheet(state: state, arrived: false));
      final glyph = tester.widget<VehicleGlyph>(find.byType(VehicleGlyph));
      expect(glyph.tier, 'driver');
    });
  });
}

extension on AssignedDriver {
  AssignedDriver copyWithEta(int eta) => AssignedDriver(
    id: id,
    name: name,
    rating: rating,
    vehicleMake: vehicleMake,
    vehicleModel: vehicleModel,
    vehicleColor: vehicleColor,
    plate: plate,
    phone: phone,
    etaSec: eta,
  );
}
