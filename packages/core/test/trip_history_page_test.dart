import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_models/shared_models.dart';

class MockTrips extends Mock implements TripRemoteDataSource {}

class MockPayments extends Mock implements PaymentsRemoteDataSource {}

Trip _trip({
  required String id,
  required TripStatus status,
  double? fareEstimate,
  double? fareFinal,
  String? driverName,
}) =>
    Trip(
      id: id,
      status: status,
      tier: 'economy',
      pickup: const TripEndpoint(point: GeoPoint(25.77, -80.19), address: 'A'),
      dropoff: const TripEndpoint(point: GeoPoint(25.79, -80.19), address: 'B'),
      fareEstimate: fareEstimate,
      fareFinal: fareFinal,
      requestedAt: DateTime(2026, 9, 10, 19, 44),
      driverName: driverName,
    );

void main() {
  testWidgets('cancelled trips do not show the (uncharged) estimate',
      (tester) async {
    final trips = MockTrips();
    when(() => trips.history()).thenAnswer((_) async => [
          _trip(
            id: 'done',
            status: TripStatus.completed,
            fareEstimate: 8.73,
            fareFinal: 6.50,
          ),
          _trip(id: 'gone', status: TripStatus.cancelled, fareEstimate: 7.61),
          _trip(
            id: 'fee',
            status: TripStatus.cancelled,
            fareEstimate: 7.61,
            fareFinal: 2.00,
          ),
        ]);

    await tester.pumpWidget(MaterialApp(
      home: TripHistoryPage(trips: trips, payments: MockPayments()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('\$6.50'), findsOneWidget);
    expect(find.text('\$7.61'), findsNothing);
    expect(find.text('\$2'), findsOneWidget);
  });

  testWidgets('rider rows show who drove, when the history says',
      (tester) async {
    final trips = MockTrips();
    when(() => trips.history()).thenAnswer((_) async => [
          _trip(
            id: 'done',
            status: TripStatus.completed,
            fareFinal: 6.50,
            driverName: 'Aziz Karimov',
          ),
          _trip(id: 'gone', status: TripStatus.cancelled),
        ]);

    await tester.pumpWidget(MaterialApp(
      home: TripHistoryPage(trips: trips, payments: MockPayments()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('with Aziz Karimov'), findsOneWidget);
    expect(find.textContaining('with '), findsOneWidget);
  });
}
