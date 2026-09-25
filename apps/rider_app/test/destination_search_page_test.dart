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
    // The distance sits directly under the row's leading pin (left side),
    // horizontally centred on it.
    final row = find
        .ancestor(
            of: find.text('Panther Coffee'), matching: find.byType(InkWell))
        .first;
    final badge = find.descendant(of: row, matching: find.byType(AppIconBadge));
    final label = find.text('350 ft');
    final badgeRect = tester.getRect(badge);
    final labelRect = tester.getRect(label);
    expect(labelRect.top, greaterThanOrEqualTo(badgeRect.bottom));
    expect(labelRect.center.dx, closeTo(badgeRect.center.dx, 1));
    expect(labelRect.right,
        lessThan(tester.getRect(find.text('Panther Coffee')).left));
    // A row without a distance is just the pin — no label, nothing guessed.
    expect(find.text('Somewhere unknown'), findsOneWidget);
    expect(find.byKey(const ValueKey('search-row-distance')), findsNWidgets(2));
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
    // Location unknown → no distance label under the pin.
    expect(find.byKey(const ValueKey('search-row-distance')), findsNothing);
  });

  testWidgets('a long distance shrinks to the pin width instead of '
      'overflowing', (tester) async {
    when(
      () => repo.autocomplete(
        any(),
        sessionToken: any(named: 'sessionToken'),
        near: any(named: 'near'),
      ),
    ).thenAnswer((_) async => [_p('a', 'Far away', 1234567)]);

    await tester.pumpWidget(
      const MaterialApp(home: DestinationSearchPage(initialPickup: me)),
    );
    await tester.pump();
    await typeQuery(tester, 'fa');

    final label = find.byKey(const ValueKey('search-row-distance'));
    expect(label, findsOneWidget);
    expect(tester.takeException(), isNull);
    final badge = tester.getRect(find.byType(AppIconBadge).last);
    // FittedBox scales the text down to the badge's width.
    final fitted = tester.getRect(
        find.ancestor(of: label, matching: find.byType(FittedBox)));
    expect(fitted.width, lessThanOrEqualTo(badge.width + 0.01));
  });
}
