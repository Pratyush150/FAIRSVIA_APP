import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses GET /drivers/me/fatigue', () {
    final s = FatigueStatus.fromJson({
      'onlineSeconds': 11 * 3600 + 40 * 60,
      'limitSeconds': 12 * 3600,
      'remainingSeconds': 20 * 60,
      'warnAtSeconds': 11 * 3600 + 30 * 60,
      'restBreakSeconds': 6 * 3600,
      'online': true,
      'overLimit': false,
      'resting': false,
      'restSecondsLeft': 0,
      'restUntil': null,
    });
    expect(s.nearLimit, isTrue);
    expect(s.resting, isFalse);
    expect(FatigueStatus.hm(s.onlineSeconds), '11h 40m');
    expect(FatigueStatus.hm(s.limitSeconds), '12h');
    expect(FatigueStatus.hm(25 * 60), '25m');
  });

  test('a resting driver carries the break end', () {
    final s = FatigueStatus.fromJson({
      'onlineSeconds': 12 * 3600,
      'limitSeconds': 12 * 3600,
      'warnAtSeconds': 11 * 3600 + 30 * 60,
      'overLimit': true,
      'resting': true,
      'restSecondsLeft': 4 * 3600,
      'restUntil': '2026-09-25T18:00:00.000Z',
    });
    expect(s.resting, isTrue);
    expect(s.nearLimit, isFalse);
    expect(s.restUntil, isNotNull);
  });
}
