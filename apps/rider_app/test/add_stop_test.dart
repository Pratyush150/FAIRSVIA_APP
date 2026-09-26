import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/trip/trip_cubit.dart';
import 'package:rider_app/home_page.dart';
import 'package:shared_models/shared_models.dart';

const _stop = TripStop(point: GeoPoint(25.79, -80.13), address: 'South Beach');

StopQuote _q(double fare) => StopQuote(
  fareEstimate: fare,
  previousFare: 7.33,
  distanceM: 9000,
  durationS: 900,
  currency: 'USD',
);

Trip _trip({List<TripStop> stops = const []}) => Trip(
  id: 't1',
  status: TripStatus.inProgress,
  tier: 'economy',
  pickup: const TripEndpoint(point: GeoPoint(25.77, -80.19)),
  dropoff: const TripEndpoint(point: GeoPoint(25.78, -80.18)),
  stops: stops,
);

void main() {
  Future<void> pumpSheet(
    WidgetTester tester, {
    required Future<StopQuote> Function() quote,
    required Future<void> Function(double) add,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(
          body: AddStopConfirmSheet(
            stop: _stop,
            quote: quote,
            add: add,
            driverName: 'Bekzod',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the new fare against the current one', (tester) async {
    await pumpSheet(tester, quote: () async => _q(12.4), add: (_) async {});
    expect(find.text('South Beach'), findsOneWidget);
    expect(find.text(r'$12.40'), findsOneWidget);
    expect(find.text(r'+$5.07'), findsOneWidget);
    expect(find.text(r'was $7.33'), findsOneWidget);
    expect(find.textContaining('let Bekzod know'), findsOneWidget);
  });

  testWidgets('adds at exactly the quoted fare', (tester) async {
    double? sent;
    await pumpSheet(
      tester,
      quote: () async => _q(12.4),
      add: (f) async => sent = f,
    );
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add stop'));
    await tester.pumpAndSettle();
    expect(sent, 12.4);
  });

  testWidgets('a price that moved is re-quoted and shown, not accepted', (
    tester,
  ) async {
    var quotes = 0;
    var adds = 0;
    await pumpSheet(
      tester,
      quote: () async => _q(++quotes == 1 ? 12.4 : 13.9),
      add: (_) async {
        adds++;
        throw const ApiException(
          'changed',
          statusCode: 409,
          code: 'PRICE_CHANGED',
        );
      },
    );
    await tester.tap(find.widgetWithText(PrimaryButton, 'Add stop'));
    await tester.pumpAndSettle();

    expect(adds, 1);
    expect(quotes, 2);
    expect(find.text(r'$13.90'), findsOneWidget);
    expect(find.textContaining('price changed'), findsOneWidget);
  });

  test('a stop can be added only to a live ride under the stop limit', () {
    TripState s(TripPhase p, {int stops = 0}) => TripState(
      phase: p,
      trip: _trip(stops: List.filled(stops, _stop)),
    );
    expect(TripCubit.canAddStopTo(s(TripPhase.driverEnRoute)), isTrue);
    expect(TripCubit.canAddStopTo(s(TripPhase.onTrip)), isTrue);
    expect(TripCubit.canAddStopTo(s(TripPhase.searching)), isFalse);
    expect(TripCubit.canAddStopTo(s(TripPhase.onTrip, stops: 3)), isFalse);
  });
}
