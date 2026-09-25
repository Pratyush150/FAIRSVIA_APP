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

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// Clock time only, e.g. "6:42 PM". Returns '—' for null.
  static String time(DateTime? d) {
    if (d == null) return '—';
    final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final ampm = d.hour < 12 ? 'AM' : 'PM';
    return '$h12:${d.minute.toString().padLeft(2, '0')} $ampm';
  }

  /// A day heading for a list grouped by date: "Today", "Yesterday",
  /// "Mon, 22 Sep", and "Mon, 22 Sep 2025" outside [now]'s year.
  static String dayLabel(DateTime d, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(d.year, d.month, d.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    final base =
        '${_weekdays[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';
    return d.year == n.year ? base : '$base ${d.year}';
  }

  /// A ride's length: "14 min", "1 h 5 min".
  static String duration(int seconds) {
    final mins = (seconds / 60).round();
    if (mins < 60) return '${mins < 1 ? 1 : mins} min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '$h h' : '$h h $m min';
  }

  /// e.g. "14 Jul". Returns '—' for null.
  static String dateShort(DateTime? d) =>
      d == null ? '—' : '${d.day} ${_months[d.month - 1]}';

  /// Currency amount as the market writes it: "₹240", "\$12.30",
  /// "18 500 so'm". [currency] defaults to the build's market (see [Market]).
  /// Negatives carry the sign before the symbol: "-₹4", not "₹-4".
  static String money(double amount, [String? currency]) =>
      Money.format(amount, currency: currency);

  /// A stored E.164 number spaced the way it is read aloud:
  /// "+919876543210" → "+91 98765 43210", "+998901234567" →
  /// "+998 90 123 45 67", "+13055550137" → "+1 305 555 0137". Numbers from
  /// other countries, or that don't have the expected length, come back as
  /// stored rather than grouped wrongly.
  static String phone(String? e164) {
    final raw = (e164 ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    String group(String digits, List<int> sizes) {
      final out = <String>[];
      var i = 0;
      for (final n in sizes) {
        out.add(digits.substring(i, i + n));
        i += n;
      }
      return out.join(' ');
    }

    final india = RegExp(r'^\+91(\d{10})$').firstMatch(raw);
    if (india != null) return '+91 ${group(india[1]!, [5, 5])}';
    final uz = RegExp(r'^\+998(\d{9})$').firstMatch(raw);
    if (uz != null) return '+998 ${group(uz[1]!, [2, 3, 2, 2])}';
    final us = RegExp(r'^\+1(\d{10})$').firstMatch(raw);
    if (us != null) return '+1 ${group(us[1]!, [3, 3, 4])}';
    return e164 ?? '';
  }

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
