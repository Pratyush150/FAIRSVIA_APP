import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  FareTier tier(String t, int? eta) => FareTier.fromJson(
      {'tier': t, 'label': t, 'fare': 100, 'capacity': 4, 'currency': 'INR', 'etaSeconds': eta});

  test('pre-selects the first ride type a car can actually do', () {
    final tiers = [tier('economy', null), tier('comfort', 240), tier('xl', 300)];
    expect(tiers.first.available, isFalse);
    expect(FareTier.defaultTier(tiers), 'comfort');
  });

  test('pre-selects nothing when no car of any type is nearby', () {
    expect(FareTier.defaultTier([tier('economy', null), tier('xl', null)]), isNull);
  });
}
