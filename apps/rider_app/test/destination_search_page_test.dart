import 'package:design_system/design_system.dart';
import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/destination_search_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripRepository extends Mock implements TripRepository {}

PlacePrediction _p(String id, String name, [int? distanceM]) => PlacePrediction(
  placeId: id,
  primaryText: name,
  secondaryText: 'Miami, FL',
  description: '$name, Miami, FL',
  distanceM: distanceM,
);

void main() {
  late MockTripRepository repo;
  const me = GeoPoint(25.77, -80.19);

  setUpAll(() => registerFallbackValue(const GeoPoint(0, 0)));

  setUp(() {
    repo = MockTripRepository();
    if (sl.isRegistered<TripRepository>()) sl.unregister<TripRepository>();
    sl.registerFactory<TripRepository>(() => repo);
  });

  tearDown(() {
    if (sl.isRegistered<TripRepository>()) sl.unregister<TripRepository>();
  });

  Future<void> typeQuery(WidgetTester tester, String q) async {
    await tester.enterText(find.byType(TextField).last, q);
    // Past the 300 ms debounce, then let the (already-resolved) future land.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump();
  }

  testWidgets('passes the rider position to autocomplete and shows a distance '
      'on each row that has one', (tester) async {
    when(
      () => repo.autocomplete(
        any(),
        sessionToken: any(named: 'sessionToken'),
        near: any(named: 'near'),
      ),
    ).thenAnswer(
      (_) async => [
        _p('a', 'Panther Coffee', 107),
        _p('b', 'Bayside Marketplace', 644),
        _p('c', 'Somewhere unknown'),
      ],
    );

    await tester.pumpWidget(
      const MaterialApp(home: DestinationSearchPage(initialPickup: me)),
    );
    await tester.pump();
    await typeQuery(tester, 'pa');

    verify(
      () => repo.autocomplete(
        'pa',
        sessionToken: any(named: 'sessionToken'),
        near: me,
      ),
    ).called(1);
    expect(find.text('Panther Coffee'), findsOneWidget);
    expect(find.text('350 ft'), findsOneWidget);
    expect(find.text('0.4 mi'), findsOneWidget);
    // A row without a distance keeps the plain arrow, no label.
    expect(find.text('Somewhere unknown'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.arrowUpRight), findsOneWidget);
  });

  testWidgets('sends no position when the rider location is unknown', (
    tester,
  ) async {
    when(
      () => repo.autocomplete(
        any(),
        sessionToken: any(named: 'sessionToken'),
        near: any(named: 'near'),
      ),
    ).thenAnswer((_) async => [_p('a', 'Panther Coffee')]);

    await tester.pumpWidget(const MaterialApp(home: DestinationSearchPage()));
    await tester.pump();
    await typeQuery(tester, 'pa');

    verify(
      () => repo.autocomplete(
        'pa',
        sessionToken: any(named: 'sessionToken'),
        near: null,
      ),
    ).called(1);
    expect(find.text('Panther Coffee'), findsOneWidget);
    expect(find.byIcon(PhosphorIconsRegular.arrowUpRight), findsOneWidget);
  });
}
