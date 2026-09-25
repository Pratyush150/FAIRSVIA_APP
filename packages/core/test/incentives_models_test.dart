import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('DriverStats parses rates and flags thresholds', () {
    final s = DriverStats.fromJson({
      'window': '7d',
      'acceptanceRate': 0.65,
      'cancellationRate': 0.1,
      'offers': 20,
      'accepted': 13,
      'declined': 5,
      'expired': 2,
      'cancelled': 1,
    });
    expect(s.acceptanceLow, isTrue); // < 70%
    expect(s.cancellationHigh, isFalse); // exactly 10% is not over
    expect(DriverStats.percent(s.acceptanceRate), '65%');
  });

  test('DriverStats: null rates stay null ("—")', () {
    final s = DriverStats.fromJson({'window': '7d', 'offers': 0});
    expect(s.acceptanceRate, isNull);
    expect(s.acceptanceLow, isFalse);
    expect(DriverStats.percent(s.cancellationRate), '—');
  });

  test('DriverQuest parses and clamps its fraction', () {
    final q = DriverQuest.fromJson({
      'id': 'q',
      'title': 'Morning rush',
      'progress': 6,
      'target': 10,
      'bonus': 150,
      'currency': 'INR',
      'startsAt': '2026-09-25T01:30:00.000Z',
      'endsAt': '2026-09-25T05:30:00.000Z',
      'completed': false,
      'paid': false,
      'status': 'active',
    });
    expect(q.fraction, closeTo(0.6, 1e-9));
    expect(q.isActive, isTrue);
    expect(q.endsAt.isUtc, isFalse);
  });
}
