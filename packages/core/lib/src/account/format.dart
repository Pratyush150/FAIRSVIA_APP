/// Lightweight formatting helpers for account screens (no intl dependency).
class Fmt {
  Fmt._();

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// e.g. "14 Jul 2026, 6:05 PM". Returns '—' for null.
  static String dateTime(DateTime? d) {
    if (d == null) return '—';
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    final min = d.minute.toString().padLeft(2, '0');
    return '${d.day} ${_months[d.month - 1]} ${d.year}, $h12:$min $ampm';
  }

  /// e.g. "14 Jul". Returns '—' for null.
  static String dateShort(DateTime? d) =>
      d == null ? '—' : '${d.day} ${_months[d.month - 1]}';

  /// Currency amount, e.g. "\$240" (USD shown as $, else "<code> 240").
  /// Negatives carry the sign before the symbol: "-\$1.30", not "\$-1.30".
  static String money(double amount, [String currency = 'USD']) {
    final abs = amount.abs();
    final n = abs.toStringAsFixed(abs.truncateToDouble() == abs ? 0 : 2);
    final sign = amount < 0 ? '-' : '';
    return currency == 'USD' ? '$sign\$$n' : '$sign$currency $n';
  }

  /// Multiplier line such as "1.2×" (one decimal, `×` not `x`).
  static String surge(double multiplier) => '${multiplier.toStringAsFixed(1)}×';

  /// Imperial distance for the US market: "350 ft" under a tenth of a mile
  /// (rounded to 10 ft), else "0.4 mi" / "12.3 mi" (one decimal).
  static String distance(int metres) {
    if (metres < 0) metres = 0;
    const metresPerMile = 1609.34;
    if (metres < metresPerMile / 10) {
      final ft = (metres * 3.28084 / 10).round() * 10;
      return '$ft ft';
    }
    return '${(metres / metresPerMile).toStringAsFixed(1)} mi';
  }

  /// Human status label from the trip status enum name.
  static String status(String raw) {
    switch (raw) {
      case 'in_progress':
        return 'In progress';
      case 'no_drivers':
        return 'No drivers';
      case 'payment_failed':
        return 'Payment failed';
      default:
        return raw.isEmpty
            ? raw
            : raw[0].toUpperCase() + raw.substring(1);
    }
  }
}
