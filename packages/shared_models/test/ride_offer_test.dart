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
      expect(o.approachEtaS, isNull);
      expect(o.approachSource, isNull);
      expect(o.approachEtaLabel, isNull);
      expect(o.surge, 1);
      expect(o.hasSurge, isFalse);
      expect(o.surgeLabel, isNull);
    });
  });

  group('RideOffer approach ETA, trip leg and surge', () {
    test('parses road approach figures and surge', () {
      final o = RideOffer.fromJson({
        ...base(),
        'approachDistanceM': 2300,
        'approachEtaS': 372,
        'approachSource': 'road',
        'surge': 1.3,
      });
      expect(o.approachEtaS, 372);
      expect(o.approachSource, 'road');
      expect(o.surge, 1.3);
      expect(o.hasSurge, isTrue);
      expect(o.surgeLabel, '1.3× surge');
      // Road figures are shown as-is (no "~").
      expect(o.approachEtaLabel, '6 min · 1.4 mi to pickup');
    });

    test('straight-line approach with a nominal ETA keeps the "~"', () {
      final o = RideOffer.fromJson({
        ...base(),
        'approachDistanceM': 2300,
        'approachEtaS': 372,
        'approachSource': 'straight',
      });
      expect(o.approachEtaLabel, '6 min · ~1.4 mi to pickup');
    });

    test('approachEtaLabel never reads "0 min" and handles "< 500 ft"', () {
      final o = RideOffer.fromJson({
        ...base(),
        'approachDistanceM': 90,
        'approachEtaS': 12,
        'approachSource': 'road',
      });
      expect(o.approachEtaLabel, '1 min · < 500 ft to pickup');
    });

    test('approachEtaLabel falls back to the distance-only label without an '
        'ETA', () {
      final o = RideOffer.fromJson({...base(), 'approachDistanceM': 2300});
      expect(o.approachEtaLabel, '~1.4 mi to pickup');
    });

    test('tripLabel shows miles and minutes, minutes omitted when unknown', () {
      expect(RideOffer.fromJson(base()).tripLabel, '3.1 mi · 10 min');
      expect(
        RideOffer.fromJson({...base(), 'durationS': 0}).tripLabel,
        '3.1 mi',
      );
      // 20 s rounds up to 1 min, never "0 min".
      expect(
        RideOffer.fromJson({...base(), 'distanceM': 100, 'durationS': 20})
            .tripLabel,
        '0.1 mi · 1 min',
      );
    });

    test('surge of exactly 1 (or missing) is not a surge', () {
      expect(RideOffer.fromJson({...base(), 'surge': 1}).hasSurge, isFalse);
      expect(RideOffer.fromJson({...base(), 'surge': 1.0}).surgeLabel, isNull);
      expect(RideOffer.fromJson({...base(), 'surge': 2}).surgeLabel,
          '2.0× surge');
    });
  });
}
