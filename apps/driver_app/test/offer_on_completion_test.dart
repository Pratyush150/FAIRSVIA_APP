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

/// Back-to-back rides: an offer that arrives while the driver is still on the
/// "Trip complete / Rate your rider" sheet is drawn OVER that sheet.
void main() {
  final offer = RideOffer.fromJson({
    'tripId': 'trip-2',
    'pickup': {'lat': 12.96, 'lng': 77.63, 'address': '12 Main St'},
    'dropoff': {'lat': 12.97, 'lng': 77.59, 'address': 'Airport T1'},
    'fare': 24.5,
    'tier': 'economy',
    'distanceM': 6865,
    'durationS': 824,
    'expiresInSec': 15,
    'rider': {'name': 'Ava Rider', 'rating': 4.9},
  });

  late MockDriverCubit cubit;

  Future<void> pump(WidgetTester tester, DriverState state) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.6;
    addTearDown(tester.view.reset);
    cubit = MockDriverCubit();
    whenListen(cubit, const Stream<DriverState>.empty(), initialState: state);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: BlocProvider<DriverCubit>.value(
            value: cubit,
            child: DriverSheetLayer(state: state),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('offer card is shown above the trip-complete sheet',
      (tester) async {
    await pump(
      tester,
      DriverState(
        phase: DriverPhase.offered,
        offer: offer,
        lastTripId: 'trip-1',
      ),
    );

    // The completion sheet is still there underneath...
    expect(find.text('Trip complete'), findsOneWidget);
    expect(find.text('Rate your rider'), findsOneWidget);
    // ...and the offer card is on top of it, actionable.
    expect(find.text('Accept'), findsOneWidget);
    expect(find.text('Decline'), findsOneWidget);
    final sheet = find.text('Trip complete');
    final card = find.byType(OfferOverlay);
    final stack = tester.widget<Stack>(find
        .ancestor(of: card, matching: find.byType(Stack))
        .first);
    // Overlay is painted last (on top) in the layer's stack.
    expect(stack.children.last, isA<OfferOverlay>());
    expect(sheet, findsOneWidget);

    await tester.tap(find.text('Accept'));
    await tester.pump();
    verify(() => cubit.acceptOffer()).called(1);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a plain online offer still shows the online sheet',
      (tester) async {
    await pump(tester, DriverState(phase: DriverPhase.offered, offer: offer));
    expect(find.text('Trip complete'), findsNothing);
    expect(find.text("You're online"), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('driver car art follows the vehicle tier', () {
    expect(driverCarAssetFor('xl'),
        'packages/design_system/assets/vehicles/top/xl.png');
    expect(driverCarAssetFor('bike'),
        'packages/design_system/assets/vehicles/top/bike.png');
    expect(driverCarAssetFor(null), endsWith('/top/driver.png'));
    expect(driverCarAssetFor('spaceship'), endsWith('/top/driver.png'));
  });
}
