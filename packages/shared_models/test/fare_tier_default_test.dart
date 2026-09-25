import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  FareTier tier(String t, int? eta, {int capacity = 4}) => FareTier.fromJson(
      {'tier': t, 'label': t, 'fare': 100, 'capacity': capacity, 'currency': 'INR', 'etaSeconds': eta});

  test('pre-selects the first ride type a car can actually do', () {
    final tiers = [tier('economy', null), tier('comfort', 240), tier('xl', 300)];
    expect(tiers.first.available, isFalse);
    expect(FareTier.defaultTier(tiers), 'comfort');
  });

  // Every ride type can be booked (the search keeps looking for a while), so
  // with no car nearby the first roomy ride is still pre-selected.
  test('pre-selects the first roomy ride when no car of any type is nearby', () {
    expect(FareTier.defaultTier([tier('economy', null), tier('xl', null)]), 'economy');
    expect(
      FareTier.defaultTier([tier('bike', null, capacity: 1), tier('economy', null)]),
      'economy',
    );
    expect(FareTier.defaultTier([]), isNull);
  });

  test('skips the one-seat bike when a roomier ride is available', () {
    final tiers = [
      tier('bike', 120, capacity: 1),
      tier('auto', 180, capacity: 3),
      tier('economy', 240),
    ];
    expect(FareTier.defaultTier(tiers), 'auto');
  });

  test('pre-selects the bike when it is the only ride nearby', () {
    final tiers = [
      tier('bike', 120, capacity: 1),
      tier('auto', null, capacity: 3),
      tier('economy', null),
    ];
    expect(FareTier.defaultTier(tiers), 'bike');
  });
}
