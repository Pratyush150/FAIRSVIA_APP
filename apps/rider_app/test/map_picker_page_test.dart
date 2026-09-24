import 'dart:convert';
import 'dart:typed_data';

import 'package:core/core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rider_app/features/trip/map_picker_page.dart';
import 'package:shared_models/shared_models.dart';

class MockTripRepository extends Mock implements TripRepository {}

/// A 1×1 transparent PNG, so the map renders without hitting the network.
final Uint8List _transparentPixel = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

class _OfflineTileProvider extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      MemoryImage(_transparentPixel);
}

void main() {
  late MockTripRepository repo;

  setUp(() {
    repo = MockTripRepository();
    if (sl.isRegistered<TripRepository>()) sl.unregister<TripRepository>();
    sl.registerFactory<TripRepository>(() => repo);
  });

  tearDown(() {
    if (sl.isRegistered<TripRepository>()) sl.unregister<TripRepository>();
  });

  testWidgets(
    'confirm returns the dropped point with its reverse-geocoded address',
    (tester) async {
      const initial = GeoPoint(18.4932, 73.7153); // Bhukum
      when(() => repo.reverseGeocode(any(), any())).thenAnswer(
        (_) async => const PlaceDetails(
          placeId: 'osm:bhukum',
          address: 'Bhukum, 415115, India',
          location: GeoPoint(18.4932, 73.7153),
        ),
      );

      PlaceDetails? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<PlaceDetails>(
                    MaterialPageRoute(
                      builder: (_) => MapPickerPage(
                        initial: initial,
                        tileProvider: _OfflineTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Set location on map'), findsOneWidget);
      expect(find.text('Bhukum, 415115, India'), findsOneWidget);

      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.address, 'Bhukum, 415115, India');
      expect(result!.location.lat, closeTo(18.4932, 0.0005));
      expect(result!.location.lng, closeTo(73.7153, 0.0005));
    },
  );

  testWidgets(
    'shows the short label as the main line and locality + city as caption',
    (tester) async {
      const full = '204, Mote Mangal Karyalay Rd, Dattwadi, Shobhapur, '
          'Dattwadi, Kasba Peth, Pune, Maharashtra 411011, India';
      when(() => repo.reverseGeocode(any(), any())).thenAnswer(
        (_) async => const PlaceDetails(
          placeId: 'ChIJ',
          address: full,
          location: GeoPoint(18.5074, 73.8553),
          label: 'Mote Mangal Karyalay Rd',
          detail: 'Dattwadi, Pune',
        ),
      );

      PlaceDetails? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  result = await Navigator.of(context).push<PlaceDetails>(
                    MaterialPageRoute(
                      builder: (_) => MapPickerPage(
                        initial: const GeoPoint(18.5074, 73.8553),
                        tileProvider: _OfflineTileProvider(),
                      ),
                    ),
                  );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Mote Mangal Karyalay Rd'), findsOneWidget);
      expect(find.text('Dattwadi, Pune'), findsOneWidget);
      expect(find.text(full), findsNothing); // raw address never shown

      await tester.tap(find.text('Confirm location'));
      await tester.pumpAndSettle();
      expect(result!.address, full); // full address still returned
      expect(result!.shortAddress, 'Mote Mangal Karyalay Rd, Dattwadi, Pune');
    },
  );
}
