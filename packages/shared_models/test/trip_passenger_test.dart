import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

/// Who is travelling when somebody else booked the ride.
void main() {
  group('fromJson', () {
    test('reads a name and phone', () {
      final p = TripPassenger.fromJson(const {
        'name': 'Priya',
        'phone': '+15550001111',
      });
      expect(p?.name, 'Priya');
      expect(p?.phone, '+15550001111');
    });

    test('a phone with no name is valid — the driver can still call', () {
      final p = TripPassenger.fromJson(const {'phone': '+15550001111'});
      expect(p, isNotNull);
      expect(p!.name, isNull);
      expect(p.displayName, 'Your passenger');
    });

    test('is null on an ordinary ride, or when the phone is missing', () {
      // The backend sends null for a ride the booker is taking themselves.
      expect(TripPassenger.fromJson(null), isNull);
      // A name with no number cannot be acted on, so it is not a passenger.
      expect(TripPassenger.fromJson(const {'name': 'Priya'}), isNull);
      expect(TripPassenger.fromJson(const {'phone': '  '}), isNull);
      expect(TripPassenger.fromJson('nonsense'), isNull);
    });

    test('blank names collapse to the generic label', () {
      final p = TripPassenger.fromJson(const {
        'name': '   ',
        'phone': '+15550001111',
      });
      expect(p?.name, isNull);
      expect(p?.displayName, 'Your passenger');
    });
  });

  group('on a Trip', () {
    Map<String, dynamic> tripJson(Object? passenger) => {
          'id': 't1',
          'status': 'accepted',
          'tier': 'economy',
          'pickup': {'lat': 1.0, 'lng': 2.0},
          'dropoff': {'lat': 3.0, 'lng': 4.0},
          'passenger': ?passenger,
        };

    test('parses onto the trip', () {
      final t = Trip.fromJson(
        tripJson(const {'name': 'Priya', 'phone': '+15550001111'}),
      );
      expect(t.passenger?.displayName, 'Priya');
    });

    test('an ordinary trip has none', () {
      expect(Trip.fromJson(tripJson(null)).passenger, isNull);
    });

    test('counts towards equality, so the UI rebuilds when it changes', () {
      final a = Trip.fromJson(tripJson(const {'phone': '+15550001111'}));
      final b = Trip.fromJson(tripJson(const {'phone': '+15550002222'}));
      expect(a, isNot(equals(b)));
    });
  });
}
