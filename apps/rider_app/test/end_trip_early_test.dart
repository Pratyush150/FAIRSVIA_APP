import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripCubit extends MockCubit<TripState> implements TripCubit {}

/// Owner request: the rider can end an in-progress ride early from the •••
/// menu. Confirm → POST /trips/:id/end-early (TripCubit.endTripEarly).
void main() {
  TripState state({TripPhase phase = TripPhase.onTrip, double? minFare = 75}) =>
      TripState(
        phase: phase,
        trip: Trip(
          id: 't1',
          status: phase == TripPhase.onTrip
              ? TripStatus.inProgress
              : TripStatus.accepted,
          tier: 'economy',
          currency: 'INR',
          fareEstimate: 289,
          paymentMode: 'cash',
          minFare: minFare,
          pickup: const TripEndpoint(point: GeoPoint(18.52, 73.85)),
          dropoff: const TripEndpoint(
              point: GeoPoint(18.53, 73.87), address: 'Pune Railway Station'),
        ),
        driver: const AssignedDriver(
            name: 'Amit Kumar', rating: 4.8, plate: 'MH12PM2285'),
        dropoffAddr: 'Pune Railway Station',
      );

  Future<MockTripCubit> pump(WidgetTester tester, TripState s) async {
    final cubit = MockTripCubit();
    whenListen(cubit, const Stream<TripState>.empty(), initialState: s);
    when(() => cubit.endTripEarly(reason: any(named: 'reason')))
        .thenAnswer((_) async => true);
    tester.view.physicalSize = const Size(411 * 3, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: BlocProvider<TripCubit>.value(
          value: cubit,
          child: SingleChildScrollView(child: OnTripSheet(state: s)),
        ),
      ),
    ));
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return cubit;
  }

  Future<void> openMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('on trip, ••• offers "End trip here" (not "Cancel ride")',
      (tester) async {
    await pump(tester, state());
    await openMenu(tester);
    expect(find.text('End trip here'), findsOneWidget);
    expect(find.text('Cancel ride'), findsNothing);
  });

  testWidgets('confirm states the minimum fare, then ends the trip',
      (tester) async {
    final cubit = await pump(tester, state());
    await openMenu(tester);
    await tester.tap(find.text('End trip here'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('End your trip here?'), findsOneWidget);
    expect(
        find.text("You'll pay for the distance travelled (min fare ₹75)."),
        findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('end-early-confirm')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    verify(() => cubit.endTripEarly(reason: 'Rider ended the trip')).called(1);
  });

  testWidgets('"Keep riding" ends nothing', (tester) async {
    final cubit = await pump(tester, state());
    await openMenu(tester);
    await tester.tap(find.text('End trip here'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const ValueKey('end-early-keep-riding')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    verifyNever(() => cubit.endTripEarly(reason: any(named: 'reason')));
  });

  testWidgets('older backend without a minimum fare: generic wording',
      (tester) async {
    await pump(tester, state(minFare: null));
    await openMenu(tester);
    await tester.tap(find.text('End trip here'));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(
        find.text(
            "You'll pay for the distance travelled (at least the minimum fare)."),
        findsOneWidget);
  });
}
