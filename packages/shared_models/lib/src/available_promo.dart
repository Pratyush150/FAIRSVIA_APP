import 'package:equatable/equatable.dart';

import 'market.dart';

/// A promo the rider can use, as the Offers page lists it
/// (`GET /promos/available`). The server has already dropped expired,
/// exhausted and used-up codes; [usesLeftForMe] is always ≥ 1.
class AvailablePromo extends Equatable {
  const AvailablePromo({
    required this.code,
    required this.title,
    this.description,
    required this.kind,
    required this.value,
    this.maxDiscount,
    this.minFare = 0,
    this.expiresAt,
    this.usesLeftForMe = 1,
  });

  final String code;
  final String title;
  final String? description;

  /// `flat` or `percent`.
  final String kind;

  /// Percent (0–100) for `percent`, an amount for `flat`.
  final double value;

  /// Cap on a percent discount, in the market currency.
  final double? maxDiscount;

  /// The fare must be at least this for the code to apply.
  final double minFare;
  final DateTime? expiresAt;
  final int usesLeftForMe;

  bool get isPercent => kind == 'percent';

  factory AvailablePromo.fromJson(Map<String, dynamic> json) => AvailablePromo(
        code: json['code'] as String,
        title: (json['title'] as String?) ?? json['code'] as String,
        description: json['description'] as String?,
        kind: json['kind'] as String? ?? 'flat',
        value: (json['value'] as num).toDouble(),
        maxDiscount: (json['maxDiscount'] as num?)?.toDouble(),
        minFare: (json['minFare'] as num?)?.toDouble() ?? 0,
        expiresAt: json['expiresAt'] == null
            ? null
            : DateTime.parse(json['expiresAt'] as String).toLocal(),
        usesLeftForMe: (json['usesLeftForMe'] as num?)?.toInt() ?? 1,
      );

  /// "50% off, up to ₹100" / "₹100 off".
  String get headline {
    if (isPercent) {
      final pct = '${_trim(value)}% off';
      final cap = maxDiscount;
      return cap == null
          ? pct
          : '$pct, up to ${Money.format(cap, wholeOnly: true)}';
    }
    return '${Money.format(value, wholeOnly: true)} off';
  }

  /// Short conditions line: "On fares over ₹400 · 2 uses left".
  String get conditions {
    final parts = <String>[
      if (minFare > 0) 'On fares over ${Money.format(minFare, wholeOnly: true)}',
      usesLeftForMe == 1 ? '1 use left' : '$usesLeftForMe uses left',
    ];
    return parts.join(' · ');
  }

  static String _trim(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

  @override
  List<Object?> get props => [
        code,
        title,
        description,
        kind,
        value,
        maxDiscount,
        minFare,
        expiresAt,
        usesLeftForMe,
      ];
}
