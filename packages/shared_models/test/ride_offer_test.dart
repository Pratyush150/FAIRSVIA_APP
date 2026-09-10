import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  Map<String, dynamic> base() => {
        'tripId': 't1',
        'pickup': {'lat': 1.0, 'lng': 2.0, 'address': 'A'},
        'dropoff': {'lat': 3.0, 'lng': 4.0, 'address': 'B'},
        'fare': 12.5,
        'tier': 'economy',
        'distanceM': 5000,
        'durationS': 600,
        'expiresInSec': 10,
      };

  group('RideOffer rider + approach', () {
    test('parses rider identity and approach distance', () {
      final o = RideOffer.fromJson({
        ...base(),
        'rider': {'name': 'Priya', 'rating': 4.7},
        'approachDistanceM': 2300,
      });
      expect(o.riderName, 'Priya');
      expect(o.riderRating, 4.7);
      expect(o.approachDistanceM, 2300);
      // 2300 m = 1.43 mi — imperial, to match the "X.X mi trip" line on the
      // same offer card.
      expect(o.approachLabel, '~1.4 mi to pickup');
    });

    test('approachLabel uses miles with one decimal for short approaches', () {
      final o = RideOffer.fromJson({...base(), 'approachDistanceM': 450});
      expect(o.approachLabel, '~0.3 mi to pickup');
    });

    test('approachLabel reads "< 500 ft" when practically at the pickup', () {
      // 500 ft = 152.4 m
      expect(
        RideOffer.fromJson({...base(), 'approachDistanceM': 100}).approachLabel,
        '< 500 ft to pickup',
      );
      expect(
        RideOffer.fromJson({...base(), 'approachDistanceM': 152}).approachLabel,
        '< 500 ft to pickup',
      );
      expect(
        RideOffer.fromJson({...base(), 'approachDistanceM': 153}).approachLabel,
        '~0.1 mi to pickup',
      );
    });

    test('back-compatible: old payload without rider/approach still parses', () {
      final o = RideOffer.fromJson(base());
      expect(o.tripId, 't1');
      expect(o.riderName, isNull);
      expect(o.riderRating, isNull);
      expect(o.approachDistanceM, isNull);
      expect(o.approachLabel, isNull);
    });
  });
}
