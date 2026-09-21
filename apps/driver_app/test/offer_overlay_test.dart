import 'package:bloc_test/bloc_test.dart';
import 'package:design_system/design_system.dart';
import 'package:driver_app/features/driver/driver_cubit.dart';
import 'package:driver_app/home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockDriverCubit extends MockCubit<DriverState> implements DriverCubit {}

void main() {
  Map<String, dynamic> offerJson() => {
    'tripId': 'trip-1',
    'pickup': {'lat': 12.96, 'lng': 77.63, 'address': '12 Main St'},
    'dropoff': {'lat': 12.97, 'lng': 77.59, 'address': 'Airport T1'},
    'fare': 24.5,
    'tier': 'economy',
    'distanceM': 6865,
    'durationS': 824,
    'expiresInSec': 15,
    'rider': {'name': 'Ava Rider', 'rating': 4.9},
  };

  late MockDriverCubit cubit;

  Future<void> pump(WidgetTester tester, RideOffer offer) async {
    cubit = MockDriverCubit();
    whenListen(
      cubit,
      const Stream<DriverState>.empty(),
      initialState: DriverState(phase: DriverPhase.offered, offer: offer),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BlocProvider<DriverCubit>.value(
            value: cubit,
            child: Stack(children: [OfferOverlay(offer: offer)]),
          ),
        ),
      ),
    );
    // Plain pumps: the card runs a 1 s countdown timer that never "settles".
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  // The countdown is a periodic Timer; tearing the widget down cancels it so
  // flutter_test doesn't flag it as pending.
  Future<void> teardown(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  testWidgets('shows road ETA + distance to pickup, dropoff, trip leg and a '
      'surge badge', (tester) async {
    final offer = RideOffer.fromJson({
      ...offerJson(),
      'surge': 1.3,
      'approachDistanceM': 2300,
      'approachEtaS': 372,
      'approachSource': 'road',
    });
    await pump(tester, offer);

    expect(find.text('\$24.50'), findsOneWidget);
    expect(find.text('1.3× surge'), findsOneWidget);
    expect(find.text('6 min · 1.4 mi to pickup'), findsOneWidget);
    expect(find.text('Est. fare · 4.3 mi · 14 min trip'), findsOneWidget);
    expect(find.text('12 Main St'), findsOneWidget);
    expect(find.text('→ Airport T1'), findsOneWidget);
    expect(find.text('Ava Rider'), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('no surge badge at 1.0× and straight-line fallback without an '
      'ETA', (tester) async {
    final offer = RideOffer.fromJson({
      ...offerJson(),
      'surge': 1,
      'approachDistanceM': 2300,
    });
    await pump(tester, offer);

    expect(find.textContaining('surge'), findsNothing);
    expect(find.text('~1.4 mi to pickup'), findsOneWidget);
    expect(find.text('Est. fare · 4.3 mi · 14 min trip'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('old payload: no approach line, distance-only trip leg, '
      'placeholder dropoff', (tester) async {
    final offer = RideOffer.fromJson({
      ...offerJson(),
      'durationS': 0,
      'dropoff': {'lat': 12.97, 'lng': 77.59},
    });
    await pump(tester, offer);

    expect(find.textContaining('to pickup'), findsNothing);
    expect(find.text('Est. fare · 4.3 mi trip'), findsOneWidget);
    expect(find.text('→ Dropoff location'), findsOneWidget);

    await teardown(tester);
  });

  testWidgets('Accept and Decline reach the cubit', (tester) async {
    await pump(tester, RideOffer.fromJson(offerJson()));

    await tester.tap(find.text('Decline'));
    verify(() => cubit.declineOffer()).called(1);

    await tester.tap(find.text('Accept'));
    await tester.pump();
    verify(() => cubit.acceptOffer()).called(1);

    await teardown(tester);
  });
}
