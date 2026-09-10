import 'dart:async';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockTrips extends Mock implements TripRemoteDataSource {}

Trip _scheduled(String id) => Trip(
      id: id,
      status: TripStatus.requested,
      tier: 'economy',
      pickup: const TripEndpoint(point: GeoPoint(25.77, -80.19), address: 'A'),
      dropoff: const TripEndpoint(point: GeoPoint(25.79, -80.19), address: 'B'),
      scheduledAt: DateTime(2026, 9, 12, 8, 30),
    );

void main() {
  late MockTrips trips;

  setUp(() {
    trips = MockTrips();
    when(() => trips.scheduled()).thenAnswer((_) async => [_scheduled('t1')]);
  });

  Widget wrap() => MaterialApp(home: ScheduledRidesPage(trips: trips));

  testWidgets('asks for confirmation and does nothing on "Keep ride"',
      (tester) async {
    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this scheduled ride?'), findsOneWidget);
    await tester.tap(find.text('Keep ride'));
    await tester.pumpAndSettle();

    expect(find.text('Cancel this scheduled ride?'), findsNothing);
    verifyNever(() => trips.cancel(any(), reason: any(named: 'reason')));
  });

  testWidgets('confirming cancels exactly once, even with a second tap',
      (tester) async {
    final inFlight = Completer<double>();
    when(() => trips.cancel(any(), reason: any(named: 'reason')))
        .thenAnswer((_) => inFlight.future);

    await tester.pumpWidget(wrap());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel ride'));
    await tester.pumpAndSettle();

    // The POST is pending: the row's Cancel is disabled, a second tap is a no-op.
    final button = tester.widget<TextButton>(
      find.ancestor(of: find.text('Cancel'), matching: find.byType(TextButton)),
    );
    expect(button.onPressed, isNull);
    await tester.tap(find.text('Cancel'), warnIfMissed: false);
    await tester.pump();
    expect(find.text('Cancel this scheduled ride?'), findsNothing);

    // Let the cancel finish; the list reloads.
    when(() => trips.scheduled()).thenAnswer((_) async => []);
    inFlight.complete(0);
    await tester.pumpAndSettle();

    verify(() => trips.cancel('t1', reason: any(named: 'reason'))).called(1);
    expect(find.text('Scheduled ride cancelled'), findsOneWidget);
    expect(find.text('No scheduled rides'), findsOneWidget);
  });
}
