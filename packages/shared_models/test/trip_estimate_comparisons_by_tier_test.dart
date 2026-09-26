import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

Map<String, dynamic> _cmp(double ours, double uber) => {
      'quotes': [
        {'provider': 'ridevela', 'displayName': 'RideVela', 'price': ours,
          'isOurs': true, 'currency': 'INR'},
        {'provider': 'uber', 'displayName': 'Uber', 'price': uber,
          'estimated': true, 'currency': 'INR'},
      ],
      'ours': {'price': ours, 'rank': 1, 'isCheapest': true,
        'maxSavings': uber - ours},
      'cheapest': {'provider': 'ridevela', 'price': ours},
      'currency': 'INR',
    };

Map<String, dynamic> _base() => {
      'distanceM': 4200,
      'durationS': 840,
      'pickup': {'lat': 18.52, 'lng': 73.85},
      'dropoff': {'lat': 18.53, 'lng': 73.87},
      'tiers': [
        {'tier': 'economy', 'label': 'Economy', 'capacity': 4, 'fare': 161},
        {'tier': 'xl', 'label': 'XL', 'capacity': 6, 'fare': 255},
      ],
    };

void main() {
  test('parses comparisonsByTier and picks per tier', () {
    final e = TripEstimate.fromJson({
      ..._base(),
      'comparison': _cmp(161, 192),
      'comparisonsByTier': {
        'economy': _cmp(161, 192),
        'xl': _cmp(255, 310),
      },
    });
    expect(e.comparisonsByTier.keys, containsAll(['economy', 'xl']));
    expect(e.comparisonFor('economy')!.ourPrice, 161);
    expect(e.comparisonFor('xl')!.ourPrice, 255);
    expect(e.comparisonFor('xl')!.quotes[1].price, 310);
    expect(e.comparisonFor('premium'), isNull);
  });

  test('missing comparisonsByTier: empty map, economy falls back to legacy',
      () {
    final e = TripEstimate.fromJson({..._base(), 'comparison': _cmp(161, 192)});
    expect(e.comparisonsByTier, isEmpty);
    expect(e.comparisonFor('economy')!.ourPrice, 161);
    expect(e.comparisonFor('xl'), isNull, reason: 'never show economy numbers for XL');
  });

  test('malformed comparisonsByTier is tolerated', () {
    final e = TripEstimate.fromJson({
      ..._base(),
      'comparisonsByTier': {'xl': 'bad', 'premium': _cmp(400, 520)},
    });
    expect(e.comparisonFor('xl'), isNull);
    expect(e.comparisonFor('premium')!.ourPrice, 400);
    expect(TripEstimate.fromJson({..._base(), 'comparisonsByTier': null})
        .comparisonsByTier, isEmpty);
  });

  test('repriced keeps comparisonsByTier', () {
    final e = TripEstimate.fromJson({
      ..._base(),
      'comparisonsByTier': {'xl': _cmp(255, 310)},
    });
    expect(e.repriced(tier: 'economy', fare: 170).comparisonFor('xl'),
        e.comparisonFor('xl'));
  });
}
