import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  group('AssignedDriver ETA', () {
    test('parses etaSec/etaDistanceM from the accepted event', () {
      final d = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'id': 'd1', 'name': 'Sam', 'rating': 4.8},
        'vehicle': {'make': 'Toyota', 'model': 'Camry', 'plate': 'ABC123'},
        'etaSec': 240,
        'etaDistanceM': 1800,
      });
      expect(d.etaSec, 240);
      expect(d.etaDistanceM, 1800);
      expect(d.etaLabel, 'Arriving in 4 min');
    });

    test('etaLabel rounds up (a partial minute reads as 1 min)', () {
      final d = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'name': 'Sam', 'rating': 5},
        'etaSec': 10,
      });
      expect(d.etaLabel, 'Arriving in 1 min');
    });

    test('etaLabel is null when ETA is absent or non-positive', () {
      final noEta = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'name': 'Sam', 'rating': 5},
      });
      expect(noEta.etaSec, isNull);
      expect(noEta.etaLabel, isNull);

      final zero = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'name': 'Sam', 'rating': 5},
        'etaSec': 0,
      });
      expect(zero.etaLabel, isNull);
    });

    test('parses the driver phone when the payload carries one', () {
      final d = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'name': 'Sam', 'rating': 5, 'phone': '+13055550123'},
      });
      expect(d.phone, '+13055550123');
    });

    test('phone is null when absent or blank (the Call button hides)', () {
      final absent = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'name': 'Sam', 'rating': 5},
      });
      expect(absent.phone, isNull);
      final blank = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'name': 'Sam', 'rating': 5, 'phone': '  '},
      });
      expect(blank.phone, isNull);
    });

    test('reads the last known position from a restored trip snapshot', () {
      final d = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'id': 'd1', 'name': 'Sam', 'rating': 4.9},
        'vehicle': {'make': 'Honda', 'model': 'Civic'},
        'driverLocation': {'lat': 12.34, 'lng': 56.78, 'heading': 90},
      });
      expect(d.lastLocation?.lat, 12.34);
      expect(d.lastLocation?.lng, 56.78);
    });

    test('a missing or malformed position is simply absent, never a crash', () {
      // The accept event carries no position at all.
      expect(
        AssignedDriver.fromAcceptedEvent(const {
          'driver': {'name': 'Sam', 'rating': 5},
        }).lastLocation,
        isNull,
      );
      // Server had no fresh fix for this driver.
      expect(
        AssignedDriver.fromAcceptedEvent(const {
          'driver': {'name': 'Sam', 'rating': 5},
          'driverLocation': null,
        }).lastLocation,
        isNull,
      );
      // Half a coordinate is not a position.
      expect(
        AssignedDriver.fromAcceptedEvent(const {
          'driver': {'name': 'Sam', 'rating': 5},
          'driverLocation': {'lat': 12.34},
        }).lastLocation,
        isNull,
      );
    });

    test('back-compatible: old payloads without ETA still parse', () {
      final d = AssignedDriver.fromAcceptedEvent(const {
        'driver': {'id': 'd1', 'name': 'Sam', 'rating': 4.9},
        'vehicle': {'make': 'Honda', 'model': 'Civic'},
      });
      expect(d.name, 'Sam');
      expect(d.etaSec, isNull);
      expect(d.etaLabel, isNull);
    });
  });
}
