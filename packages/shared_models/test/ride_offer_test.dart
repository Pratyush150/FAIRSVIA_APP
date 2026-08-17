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
      expect(o.approachLabel, '~2.3 km to pickup');
    });

    test('approachLabel uses metres under 1 km', () {
      final o = RideOffer.fromJson({...base(), 'approachDistanceM': 450});
      expect(o.approachLabel, '~450 m to pickup');
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
