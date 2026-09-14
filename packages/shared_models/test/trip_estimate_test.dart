import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  const estimate = TripEstimate(
    distanceM: 6865,
    durationS: 824,
    polyline: 'abcd',
    surge: 1,
    currency: 'USD',
    pickup: GeoPoint(1, 2),
    dropoff: GeoPoint(3, 4),
    tiers: [
      FareTier(
        tier: 'economy',
        label: 'Economy',
        capacity: 4,
        fare: 6.85,
        currency: 'USD',
        etaSeconds: 300,
      ),
      FareTier(
        tier: 'xl',
        label: 'XL',
        capacity: 6,
        fare: 11.2,
        currency: 'USD',
        etaSeconds: 420,
      ),
    ],
  );

  group('TripEstimate.repriced', () {
    test('replaces only the named tier fare and updates the surge', () {
      final r = estimate.repriced(tier: 'economy', fare: 8.22, surge: 1.2);
      expect(r.surge, 1.2);
      expect(r.tiers[0].fare, 8.22);
      expect(r.tiers[0].label, 'Economy');
      expect(r.tiers[0].etaSeconds, 300);
      expect(r.tiers[1], estimate.tiers[1]);
      expect(r.polyline, 'abcd');
      expect(r.pickup, const GeoPoint(1, 2));
      // The original is untouched.
      expect(estimate.tiers[0].fare, 6.85);
    });

    test('keeps the surge when none is given', () {
      final r = estimate.repriced(tier: 'xl', fare: 12);
      expect(r.surge, 1);
      expect(r.tiers[1].fare, 12);
    });

    test('an unknown tier changes no fares', () {
      final r = estimate.repriced(tier: 'nope', fare: 99, surge: 2);
      expect(r.tiers, estimate.tiers);
      expect(r.surge, 2);
    });
  });
}
