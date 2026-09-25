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

/// Accessibility of the main rider sheets (audit 4.3): the platform
/// guidelines (48 dp targets, a label on every tappable, text contrast), the
/// plate and PIN read one character at a time, the headline announced when
/// the moment changes, nothing cut off at the largest text size, and Reduce
/// Motion (4.2) honoured.
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
    pickupAddr: 'Shivajinagar, Pune',
    dropoffAddr: 'Pune Railway Station, Agarkar Nagar, Pune',
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
        etaSeconds: null,
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

  /// The sheet for [state], at a phone's size, with the given text scale and
  /// Reduce Motion setting; then lets every entrance settle.
  Future<void> pump(
    WidgetTester tester,
    TripState state, {
    Size size = const Size(411, 914),
    double textScale = 1.0,
    bool reduceMotion = false,
    bool dark = false,
  }) async {
    tester.view.physicalSize = size * 2.625;
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    // As each app's MaterialApp.builder does: the ink getters follow it.
    AppColors.syncBrightness(dark ? Brightness.dark : Brightness.light);
    addTearDown(() => AppColors.syncBrightness(Brightness.light));
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: dark ? AppTheme.dark : AppTheme.light,
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
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the finding-driver radar loops forever.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  final sheets = <String, TripState>{
    'choose ride': base.copyWith(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'economy',
    ),
    // Every optional control on: a stop to remove, a scheduled time to
    // clear, a promo to remove, a passenger to switch back from.
    'choose ride (all options)': base.copyWith(
      phase: TripPhase.choosingRide,
      estimate: estimate,
      selectedTier: 'economy',
      stops: const [
        TripStop(point: GeoPoint(18.525, 73.86), address: 'FC Road, Pune'),
      ],
      scheduledAt: DateTime.now().add(const Duration(hours: 2)),
      appliedPromo: const PromoQuote(
        code: 'WELCOME',
        kind: 'flat',
        discount: 20,
        subtotal: 102,
        net: 82,
      ),
      passenger: const TripPassenger(phone: '+919812345678', name: 'Asha'),
    ),
    'driver en route': base.copyWith(phase: TripPhase.driverEnRoute),
    'on trip': base.copyWith(phase: TripPhase.onTrip, estimate: estimate),
    'completed': base.copyWith(phase: TripPhase.completed, fareFinal: 102.0),
  };

  group('platform accessibility guidelines', () {
    for (final MapEntry(key: name, value: state) in sheets.entries) {
      for (final dark in const [false, true]) {
        testWidgets('$name sheet (${dark ? 'dark' : 'light'})', (tester) async {
          final handle = tester.ensureSemantics();
          // A tall screen, so every row of the sheet is on screen and checked
          // (the guidelines skip what is scrolled out of view).
          await pump(tester, state, size: const Size(411, 1800), dark: dark);
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(iOSTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
          if (AppGlass.enabled) {
            // Plan F fades the last 32 px of a sheet that scrolls (the "more
            // below" cue) — half-faded text there is the cue, not a contrast
            // bug. Scroll to the end so every row is measured fully drawn.
            for (final e in find.byType(Scrollable).evaluate()) {
              final pos = (e as StatefulElement).state as ScrollableState;
              pos.position.jumpTo(pos.position.maxScrollExtent);
            }
            await tester.pump();
          }
          await expectLater(tester, meetsGuideline(textContrastGuideline));
          handle.dispose();
        });
      }
    }
  });

  testWidgets('the plate and the PIN are read one character at a time', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, sheets['driver en route']!);
    expect(
      find.bySemanticsLabel(RegExp(r'^Number plate M H 1 2 A B 3 4 5 6$')),
      findsOneWidget,
    );
    expect(
      find.bySemanticsLabel(RegExp(r'^Ride PIN 4 8 2 7\. Tell Priya')),
      findsOneWidget,
    );
    // The rating says what it is, not a bare "4.9".
    expect(find.bySemanticsLabel('Rated 4.9'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('the headline is a live region that names the moment, not the '
      'ticking minute', (tester) async {
    final handle = tester.ensureSemantics();
    await pump(tester, sheets['driver en route']!);
    // The minutes are still there, as the value, for a reader who focuses it.
    expect(
      tester.getSemantics(find.bySemanticsLabel('Priya is on the way')),
      isSemantics(
        isLiveRegion: true,
        isHeader: true,
        value: 'arriving in 4 min',
      ),
    );

    // Arrived: a new label on the same live region → announced.
    await pump(tester, base.copyWith(phase: TripPhase.driverArrived));
    expect(
      tester.getSemantics(find.bySemanticsLabel('Priya has arrived')),
      isSemantics(isLiveRegion: true),
    );
    handle.dispose();
  });

  testWidgets('an unavailable ride says so in words, not only by dimming', (
    tester,
  ) async {
    await pump(tester, sheets['choose ride']!);
    expect(find.text('No cars nearby'), findsOneWidget);
  });

  testWidgets('the chosen payment chip carries a check, not only a colour', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pump(tester, sheets['choose ride']!.copyWith(paymentMode: 'cash'));
    final cash = find.ancestor(
      of: find.text('Cash'),
      matching: find.byType(InkWell),
    );
    expect(
      find.descendant(
        of: cash,
        matching: find.byIcon(PhosphorIconsFill.checkCircle),
      ),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(cash.first),
      isSemantics(isSelected: true, isButton: true),
    );
    handle.dispose();
  });

  group('Dynamic Type at 2.0 — nothing overflows', () {
    for (final MapEntry(key: name, value: state) in sheets.entries) {
      for (final size in const [Size(411, 914), Size(360, 640)]) {
        testWidgets('$name at $size', (tester) async {
          await pump(tester, state, size: size, textScale: 2.0);
          expect(tester.takeException(), isNull);
        });
      }
    }
    testWidgets('finding a driver', (tester) async {
      await pump(
        tester,
        base.copyWith(phase: TripPhase.searching),
        size: const Size(360, 640),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('Reduce Motion', () {
    testWidgets('the finding-driver radar holds still', (tester) async {
      await pump(
        tester,
        base.copyWith(phase: TripPhase.searching),
        reduceMotion: true,
      );
      final mode = tester.widget<TickerMode>(
        find
            .ancestor(
              of: find.byType(PulseRadar),
              matching: find.byType(TickerMode),
            )
            .first,
      );
      expect(mode.enabled, isFalse);
    });

    testWidgets('ride tiers appear without sliding in', (tester) async {
      final state = sheets['choose ride']!;
      final cubit = MockTripCubit();
      whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: MediaQuery(
            data: const MediaQueryData(
              size: Size(411, 914),
              disableAnimations: true,
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
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      final start = tester.getTopLeft(find.text('XL'));
      await tester.pump(const Duration(milliseconds: 600));
      // Where it starts is where it stays: no rise-in.
      expect(tester.getTopLeft(find.text('XL')), start);
    });
  });

  // Proportions (docs/plans/proportion-study-2026-09-25.md): booking opens at
  // RiderSheetHeights.chooseRide (with a pixel floor on short phones); ride
  // complete leaves a map peek above it. Heights, pinned footers and no overflow, across phone
  // sizes, text sizes and both themes.
  group('sheet heights', () {
    for (final size in const [Size(360, 640), Size(411, 914)]) {
      for (final scale in const [1.0, 1.3]) {
        for (final dark in const [false, true]) {
          final tag = '$size ×$scale ${dark ? 'dark' : 'light'}';
          testWidgets('choose ride opens at its set share ($tag)', (
            tester,
          ) async {
            await pump(
              tester,
              sheets['choose ride']!,
              size: size,
              textScale: scale,
              dark: dark,
            );
            expect(tester.takeException(), isNull);
            final rect = tester.getRect(find.byType(RideSheetForPhase));
            final share = RiderSheetHeights.current.chooseRideAt(size.height);
            expect(rect.height, closeTo(size.height * share, 1));
            expect(rect.bottom, size.height);
            // The Confirm footer is pinned inside the sheet.
            final confirm = find.textContaining('Confirm');
            expect(confirm, findsWidgets);
            expect(
              tester.getRect(confirm.first).bottom,
              lessThanOrEqualTo(size.height),
            );
          });

          testWidgets('ride complete takes its set share ($tag)', (
            tester,
          ) async {
            await pump(
              tester,
              sheets['completed']!,
              size: size,
              textScale: scale,
              dark: dark,
            );
            expect(tester.takeException(), isNull);
            final rect = tester.getRect(find.byType(RideSheetForPhase));
            final share = RiderSheetHeights.current.completed;
            expect(rect.height, closeTo(size.height * share, 1));
            expect(rect.bottom, size.height);
            // Done sits on the bottom edge, above the home-indicator inset.
            final done = tester.getRect(find.text('Done'));
            expect(done.bottom, greaterThan(size.height - 120));
            expect(done.bottom, lessThanOrEqualTo(size.height - 24));
          });
        }
      }
    }

    testWidgets('choose ride: the handle pulls the sheet up, and back', (
      tester,
    ) async {
      if (!AppGlass.enabled) return; // the handle is a control on glass only
      await pump(tester, sheets['choose ride (all options)']!);
      final sheet = find.byType(RideSheetForPhase);
      final open = 914 * RiderSheetHeights.current.chooseRideAt(914);
      expect(tester.getRect(sheet).height, closeTo(open, 1));
      await tester.tap(find.bySemanticsLabel('Show more ride options'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getRect(sheet).height, greaterThan(open + 50));
      expect(tester.takeException(), isNull);
      await tester.tap(find.bySemanticsLabel('Show less'));
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getRect(sheet).height, closeTo(open, 1));
    });

    testWidgets('ride complete: full size at once under Reduce Motion', (
      tester,
    ) async {
      await pump(tester, sheets['completed']!, reduceMotion: true);
      expect(
        tester.getRect(find.byType(RideSheetForPhase)).height,
        closeTo(914 * RiderSheetHeights.current.completed, 1),
      );
      expect(tester.takeException(), isNull);
    });
  });
}
