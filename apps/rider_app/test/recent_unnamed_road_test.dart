import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rider_app/features/home/home_data.dart';
import 'package:rider_app/features/home/idle_home.dart';
import 'package:shared_models/shared_models.dart';

Trip _trip(String id, String addr, GeoPoint p) => Trip(
  id: id,
  status: TripStatus.completed,
  tier: 'economy',
  pickup: const TripEndpoint(point: GeoPoint(18.5, 73.8)),
  dropoff: TripEndpoint(point: p, address: addr),
);

void main() {
  test('recents strip a stored "Unnamed Road" prefix', () {
    final r = recentDestinations([
      _trip('1', 'Unnamed Road, Dattwadi, Pune', const GeoPoint(18.50, 73.86)),
      _trip('2', 'Unnamed Road', const GeoPoint(18.60, 73.90)),
    ]);
    expect(r.single.address, 'Dattwadi, Pune');
    expect(r.single.name, 'Dattwadi');
  });

  testWidgets('RecentDestinationsCard never shows "Unnamed Road"', (
    tester,
  ) async {
    final recents = recentDestinations([
      _trip('1', 'Unnamed Road, Dattwadi, Pune', const GeoPoint(18.50, 73.86)),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: RecentDestinationsCard(items: recents, onPick: (_) {}),
        ),
      ),
    );
    expect(find.textContaining('Unnamed', findRichText: true), findsNothing);
    expect(find.text('Dattwadi'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Ride to Dattwadi, Pune'),
      findsOneWidget,
    );
  });
}
