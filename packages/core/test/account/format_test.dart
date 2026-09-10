import 'package:core/src/account/format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Fmt.money', () {
    test('renders whole USD amounts with the dollar sign, no decimals', () {
      expect(Fmt.money(240), '\$240');
      expect(Fmt.money(0), '\$0');
    });

    test('keeps decimals when the amount is fractional', () {
      expect(Fmt.money(12.5), '\$12.50');
    });

    test('uses the currency code for non-USD', () {
      expect(Fmt.money(10, 'EUR'), 'EUR 10');
    });

    test('puts the sign before the symbol for negatives', () {
      expect(Fmt.money(-1.30), '-\$1.30');
      expect(Fmt.money(-2), '-\$2');
      expect(Fmt.money(-1.30, 'EUR'), '-EUR 1.30');
    });
  });

  group('Fmt.status', () {
    test('humanizes snake_case backend statuses', () {
      expect(Fmt.status('in_progress'), 'In progress');
      expect(Fmt.status('no_drivers'), 'No drivers');
      expect(Fmt.status('payment_failed'), 'Payment failed');
    });

    test('capitalizes simple statuses', () {
      expect(Fmt.status('completed'), 'Completed');
      expect(Fmt.status('cancelled'), 'Cancelled');
    });
  });

  group('Fmt.dateTime', () {
    test('formats a known instant in 12-hour time', () {
      final d = DateTime(2026, 7, 14, 18, 5);
      expect(Fmt.dateTime(d), '14 Jul 2026, 6:05 PM');
    });

    test('handles midnight and noon', () {
      expect(Fmt.dateTime(DateTime(2026, 1, 1, 0, 0)), '1 Jan 2026, 12:00 AM');
      expect(Fmt.dateTime(DateTime(2026, 1, 1, 12, 0)), '1 Jan 2026, 12:00 PM');
    });

    test('returns a dash for null', () {
      expect(Fmt.dateTime(null), '—');
    });
  });
}
