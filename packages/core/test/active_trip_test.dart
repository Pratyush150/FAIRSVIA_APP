import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  const base = {
    'id': 't1',
    'status': 'accepted',
    'tier': 'economy',
    'pickup': {'lat': 25.77, 'lng': -80.19, 'address': '12 Pickup St'},
    'dropoff': {'lat': 25.78, 'lng': -80.18},
  };

  group('ActiveTrip.fromJson', () {
    test('parses driver, vehicle, ETA and approach polyline when present', () {
      final a = ActiveTrip.fromJson({
        ...base,
        'driver': {'id': 'd1', 'name': 'Ava', 'rating': 4.9, 'phone': '+1305'},
        'vehicle': {'make': 'Toyota', 'model': 'Prius', 'plate': 'ABC123'},
        'etaSec': 240,
        'etaDistanceM': 1800,
        'driverPolyline': '_ki|C~ulhNbB?bB?',
      });
      expect(a.trip.id, 't1');
      expect(a.trip.status, TripStatus.accepted);
      expect(a.driver?.name, 'Ava');
      expect(a.driver?.plate, 'ABC123');
      expect(a.driver?.phone, '+1305');
      expect(a.driver?.etaSec, 240);
      expect(a.driverPolyline, '_ki|C~ulhNbB?bB?');
    });

    test('keeps working when the server omits the driver keys', () {
      final a = ActiveTrip.fromJson(base);
      expect(a.trip.id, 't1');
      expect(a.driver, isNull);
      expect(a.driverPolyline, isNull);
    });

    test('an empty driverPolyline reads as absent', () {
      final a = ActiveTrip.fromJson({...base, 'driverPolyline': ''});
      expect(a.driverPolyline, isNull);
    });
  });

  group('dialPhone', () {
    test('builds a tel: URI from a display-formatted number', () {
      expect(phoneCallUri('+1 (305) 555-0123').toString(), 'tel:+13055550123');
      expect(phoneCallUri('305 555 0123').toString(), 'tel:3055550123');
    });

    test('launches the tel: URI and reports the launcher result', () async {
      Uri? launched;
      final ok = await dialPhone(
        '+1 305-555-0123',
        launch: (u) async {
          launched = u;
          return true;
        },
      );
      expect(ok, isTrue);
      expect(launched.toString(), 'tel:+13055550123');
    });

    test('an unusable number never reaches the launcher', () async {
      var calls = 0;
      final ok = await dialPhone(
        'n/a',
        launch: (_) async {
          calls++;
          return true;
        },
      );
      expect(ok, isFalse);
      expect(calls, 0);
    });

    test('a throwing launcher reads as false, not a crash', () async {
      final ok = await dialPhone('+1305', launch: (_) async => throw 'boom');
      expect(ok, isFalse);
    });
  });
}
