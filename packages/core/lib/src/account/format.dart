import 'package:shared_models/shared_models.dart';

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

  /// Currency amount as the market writes it: "₹240", "\$12.30",
  /// "18 500 so'm". [currency] defaults to the build's market (see [Market]).
  /// Negatives carry the sign before the symbol: "-₹4", not "₹-4".
  static String money(double amount, [String? currency]) =>
      Money.format(amount, currency: currency);

  /// Multiplier line such as "1.2×" (one decimal, `×` not `x`).
  static String surge(double multiplier) => '${multiplier.toStringAsFixed(1)}×';

  /// Distance in the market's units: "850 m" / "12.3 km", or "350 ft" /
  /// "0.4 mi" in the US.
  static String distance(int metres) => Market.current.distance(metres);

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
