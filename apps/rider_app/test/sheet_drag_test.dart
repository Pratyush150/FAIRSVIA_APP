import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/layout/rider_sheet_heights.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Draggable booking / ride sheets (owner, 2026-09-25): each phase opens at
/// its decided share (rest), drags / taps up to the expanded size, back down
/// to rest (on trip: on to a smaller peek), and a fling snaps to the next
/// size. Pinned footers stay on screen at every size; nothing overflows on a
/// short or a tall phone at 1.0 / 1.3 text.
void main() {
  const driver = AssignedDriver(
    name: 'Priya Sharma',
    rating: 4.9,
    vehicleMake: 'Maruti',
    vehicleModel: 'Dzire',
    vehicleColor: 'White',
    plate: 'MH12AB3456',
    phone: '+919876543210',
    etaSec: 240,
  );
  final estimate = TripEstimate(
    distanceM: 1500,
    durationS: 420,
    polyline: '',
    surge: 1,
    currency: 'INR',
    pickup: const GeoPoint(18.52, 73.85),
    dropoff: const GeoPoint(18.53, 73.87),
    tiers: const [
      FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 102,
        currency: 'INR',
        etaSeconds: 180,
      ),
      FareTier(
        tier: 'comfort',
        label: 'Comfort',
        capacity: 4,
        fare: 140,
        currency: 'INR',
        etaSeconds: 240,
      ),
      FareTier(
        tier: 'xl',
        label: 'XL',
        capacity: 6,
        fare: 190,
        currency: 'INR',
        etaSeconds: 300,
      ),
    ],
  );
  final base = TripState(
    trip: Trip(
      id: 't1',
      status: TripStatus.accepted,
      tier: 'economy',
      startOtp: '4827',
      pickup: const TripEndpoint(point: GeoPoint(18.52, 73.85)),
      dropoff: const TripEndpoint(point: GeoPoint(18.53, 73.87)),
    ),
    driver: driver,
    estimate: estimate,
    selectedTier: 'economy',
    pickupAddr: 'Shivajinagar, Pune',
    dropoffAddr: 'Pune Railway Station, Agarkar Nagar, Pune',
  );

  final phases = <String, TripState>{
    'choose ride': base.copyWith(phase: TripPhase.choosingRide),
    'finding driver': base.copyWith(phase: TripPhase.searching),
    'driver en route': base.copyWith(phase: TripPhase.driverEnRoute),
    'driver arrived': base.copyWith(phase: TripPhase.driverArrived),
    'on trip': base.copyWith(phase: TripPhase.onTrip),
    'completed': base.copyWith(phase: TripPhase.completed, fareFinal: 102.0),
  };

  /// The pinned footer each phase keeps on screen, if any.
  Finder? footerOf(TripPhase p) => switch (p) {
    TripPhase.choosingRide => find.textContaining('Confirm'),
    TripPhase.completed => find.text('Done'),
    _ => null,
  };

  Future<void> settle(WidgetTester tester) async {
    // Not pumpAndSettle: the finding-driver radar loops forever.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> pump(
    WidgetTester tester,
    TripState state, {
    Size size = const Size(411, 914),
    double textScale = 1.0,
    bool reduceMotion = false,
    VoidCallback? onSettled,
  }) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            padding: const EdgeInsets.only(top: 24, bottom: 24),
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: Scaffold(
            body: BlocProvider<TripCubit>.value(
              value: cubit,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: RideSheetForPhase(
                  state: state,
                  onSearch: () {},
                  onPickSaved: (_) {},
                  onSheetSettled: onSettled,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  double sheetHeight(WidgetTester tester) =>
      tester.getRect(find.byType(RideSheetForPhase)).height;

  double expandedPx(double screen) {
    final e = RiderSheetHeights.current.expandedPx(screen);
    final cap = screen - 24 - AppSpacing.md;
    return e < cap ? e : cap;
  }

  /// The rest size each phase must open at.
  void expectRest(TripPhase p, double h, Size size) {
    final heights = RiderSheetHeights.current;
    switch (p) {
      case TripPhase.choosingRide:
        expect(h, closeTo(size.height * heights.chooseRideAt(size.height), 1));
      case TripPhase.completed:
        expect(h, closeTo(size.height * heights.completed, 1));
      // The compact live card is Plan F's; other builds fit the content.
      case TripPhase.driverEnRoute ||
              TripPhase.driverArrived ||
              TripPhase.onTrip
          when AppGlass.enabled:
        final cap = heights.liveCompactAt(
          onTrip: p == TripPhase.onTrip,
          screenHeight: size.height,
        );
        expect(h, lessThanOrEqualTo(size.height * cap + 1));
      default:
        // Finding a driver fits its content.
        expect(h, lessThanOrEqualTo(expandedPx(size.height) + 1));
    }
  }

  void expectFooterOnScreen(WidgetTester tester, TripPhase p, Size size) {
    final footer = footerOf(p);
    if (footer == null) return;
    expect(footer, findsWidgets);
    expect(tester.getRect(footer.first).bottom, lessThanOrEqualTo(size.height));
    expect(
      tester.getRect(footer.first).top,
      greaterThan(size.height - sheetHeight(tester)),
    );
  }

  for (final MapEntry(key: name, value: state) in phases.entries) {
    group(name, () {
      for (final size in const [Size(360, 640), Size(411, 914)]) {
        for (final scale in const [1.0, 1.3]) {
          final tag = '${size.width.toInt()}×${size.height.toInt()} ×$scale';

          testWidgets('rest → drag up → expanded → drag down → rest ($tag)', (
            tester,
          ) async {
            var settled = 0;
            await pump(
              tester,
              state,
              size: size,
              textScale: scale,
              onSettled: () => settled++,
            );
            expect(tester.takeException(), isNull);
            final rest = sheetHeight(tester);
            expectRest(state.phase, rest, size);
            expect(
              tester.getRect(find.byType(RideSheetForPhase)).bottom,
              size.height,
            );
            expectFooterOnScreen(tester, state.phase, size);

            // A slow drag up on the handle, the whole way: expanded.
            final up = expandedPx(size.height) - rest;
            await tester.timedDrag(
              find.bySemanticsLabel('Expand'),
              Offset(0, -up),
              const Duration(milliseconds: 1500),
            );
            await settle(tester);
            expect(tester.takeException(), isNull);
            expect(sheetHeight(tester), closeTo(expandedPx(size.height), 1));
            expect(find.bySemanticsLabel('Collapse'), findsOneWidget);
            expectFooterOnScreen(tester, state.phase, size);
            expect(settled, greaterThanOrEqualTo(1));

            // …and slowly back down: rest again.
            await tester.timedDrag(
              find.bySemanticsLabel('Collapse'),
              Offset(0, up),
              const Duration(milliseconds: 1500),
            );
            await settle(tester);
            expect(tester.takeException(), isNull);
            expect(sheetHeight(tester), closeTo(rest, 1));
            expect(find.bySemanticsLabel('Expand'), findsOneWidget);
            expectFooterOnScreen(tester, state.phase, size);
          });
        }
      }

      testWidgets('a fling snaps to the next size', (tester) async {
        await pump(tester, state);
        final rest = sheetHeight(tester);
        // A short, fast flick up: it goes all the way.
        await tester.fling(
          find.bySemanticsLabel('Expand'),
          const Offset(0, -60),
          2000,
        );
        await settle(tester);
        expect(sheetHeight(tester), closeTo(expandedPx(914), 1));
        // A short, fast flick down: back to rest, not part-way.
        await tester.fling(
          find.bySemanticsLabel('Collapse'),
          const Offset(0, 60),
          2000,
        );
        await settle(tester);
        expect(sheetHeight(tester), closeTo(rest, 1));
        // Another one down: on trip parks at the peek; every other phase
        // stays at rest (never below it).
        await tester.fling(
          find.bySemanticsLabel('Expand'),
          const Offset(0, 60),
          2000,
        );
        await settle(tester);
        final peek = RiderSheetHeights.current.onTripPeekPx(914);
        if (state.phase == TripPhase.onTrip && peek < rest - 1) {
          expect(sheetHeight(tester), closeTo(peek, 1));
        } else {
          expect(sheetHeight(tester), closeTo(rest, 1));
        }
        expect(tester.takeException(), isNull);
      });

      testWidgets('a slow short drag springs back to rest', (tester) async {
        await pump(tester, state);
        final rest = sheetHeight(tester);
        await tester.timedDrag(
          find.bySemanticsLabel('Expand'),
          const Offset(0, -40),
          const Duration(milliseconds: 800),
        );
        await settle(tester);
        expect(sheetHeight(tester), closeTo(rest, 1));
      });

      testWidgets('the handle taps up and back; instant under Reduce Motion', (
        tester,
      ) async {
        await pump(tester, state, reduceMotion: true);
        final rest = sheetHeight(tester);
        await tester.tap(find.bySemanticsLabel('Expand'));
        await tester.pump();
        // Reduce Motion: no animation, the new size in one frame.
        expect(sheetHeight(tester), closeTo(expandedPx(914), 1));
        await tester.tap(find.bySemanticsLabel('Collapse'));
        await tester.pump();
        await tester.pump();
        expect(sheetHeight(tester), closeTo(rest, 1));
        expect(tester.takeException(), isNull);
        await settle(tester); // let the sheet content's timers run out
      });

      testWidgets('the handle is a labelled 48 dp button', (tester) async {
        final semantics = tester.ensureSemantics();
        await pump(tester, state);
        final handle = find.bySemanticsLabel('Expand');
        expect(handle, findsOneWidget);
        expect(tester.getSize(handle).height, greaterThanOrEqualTo(48));
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        semantics.dispose();
      });
    });
  }

  testWidgets('each new phase opens at its rest size again', (tester) async {
    await pump(tester, phases['driver en route']!);
    final rest = sheetHeight(tester);
    await tester.tap(find.bySemanticsLabel('Expand'));
    await settle(tester);
    expect(sheetHeight(tester), greaterThan(rest + 50));
    // The same host, a new phase.
    await pump(tester, phases['on trip']!);
    expectRest(TripPhase.onTrip, sheetHeight(tester), const Size(411, 914));
    expect(find.bySemanticsLabel('Expand'), findsOneWidget);
  });
}
