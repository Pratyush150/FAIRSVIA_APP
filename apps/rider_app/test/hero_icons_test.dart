import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Plan B/C 3D hero icons on the live-ride and completed sheets.
///
/// Runs in every build: in a default build it proves nothing changed (no
/// images, the Phosphor glyphs as before); run with
/// `--dart-define=THEME=daylight` (or `daynight`) it proves the 3D art is
/// used in a light theme — and still not in a dark one.
void main() {
  Future<void> pump(WidgetTester tester, TripState state, ThemeData theme) async {
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: state);
    await tester.pumpWidget(MaterialApp(
      theme: theme,
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
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Finder hero(String name) => find.byWidgetPredicate((w) =>
      w is Image &&
      w.image is AssetImage &&
      (w.image as AssetImage).assetName == 'assets/heroes/daylight/$name.png' &&
      (w.image as AssetImage).package == 'design_system');

  final onTrip = TripState(
    phase: TripPhase.onTrip,
    dropoffAddr: 'Phoenix Marketcity, Pune',
    liveRemainingM: 5000,
    trip: const Trip(
      id: 't1',
      status: TripStatus.inProgress,
      tier: 'economy',
      pickup: TripEndpoint(point: GeoPoint(18.52, 73.85)),
      dropoff: TripEndpoint(point: GeoPoint(18.53, 73.87)),
    ),
  );
  const completed = TripState(phase: TripPhase.completed, fareFinal: 75);

  final light = AppColors.planLight;

  testWidgets(
      light
          ? 'light Plan B/C: 3D art for Add a stop, Pre-book and Done'
          : 'default build: Phosphor icons, no 3D art', (tester) async {
    await pump(tester, onTrip, AppTheme.light);
    expect(hero('add_stop'), light ? findsOneWidget : findsNothing);
    expect(hero('prebook'), light ? findsOneWidget : findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.mapPinPlus),
        light ? findsNothing : findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.calendarCheck),
        light ? findsNothing : findsOneWidget);

    await pump(tester, completed, AppTheme.light);
    expect(hero('done'), light ? findsOneWidget : findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.check),
        light ? findsNothing : findsOneWidget);
  });

  testWidgets('a dark theme never gets the light-lit 3D art', (tester) async {
    await pump(tester, onTrip, AppTheme.dark);
    expect(hero('add_stop'), findsNothing);
    expect(hero('prebook'), findsNothing);
    expect(find.byIcon(PhosphorIconsRegular.mapPinPlus), findsOneWidget);
  });
}
