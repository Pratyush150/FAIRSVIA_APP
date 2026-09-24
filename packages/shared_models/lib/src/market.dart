/// The market the apps run in: which currency money is shown in and whether
/// distances read metric or imperial. One setting for every screen, so a
/// fare never says "₹" next to "mi".
///
/// Chosen at build time with `--dart-define=MARKET=in|uz|us` (see
/// [Market.fromEnvironment]). Amounts that carry their own currency from the
/// server (a trip, an estimate) are still shown in that currency.
class Market {
  const Market._({
    required this.code,
    required this.currency,
    required this.metric,
    required this.tipPresets,
    required this.maxTip,
    required this.dialCode,
    required this.examplePhone,
    required this.cityCenter,
  });

  /// India (Pune pilot): rupees, kilometres.
  static const india = Market._(
      code: 'in', currency: 'INR', metric: true,
      tipPresets: [20, 50, 100], maxTip: 2000,
      dialCode: '+91', examplePhone: '+91 98765 43210',
      cityCenter: (18.5204, 73.8567)); // Pune (pilot city)

  /// Uzbekistan (launch market): som, kilometres.
  static const uzbekistan = Market._(
      code: 'uz', currency: 'UZS', metric: true,
      tipPresets: [5000, 10000, 20000], maxTip: 500000,
      dialCode: '+998', examplePhone: '+998 90 123 45 67',
      cityCenter: (41.3111, 69.2797)); // Tashkent

  /// United States: dollars, miles.
  static const unitedStates = Market._(
      code: 'us', currency: 'USD', metric: false,
      tipPresets: [2, 3, 5], maxTip: 500,
      dialCode: '+1', examplePhone: '+1 305 555 0137',
      cityCenter: (25.7743, -80.1937)); // Miami

  final String code;

  /// ISO 4217 code, e.g. `INR`.
  final String currency;

  /// Kilometres and metres when true; miles and feet when false.
  final bool metric;

  /// One-tap tip amounts on the rating screen, in [currency].
  final List<double> tipPresets;

  /// Largest custom tip the app accepts, in [currency].
  final double maxTip;

  /// Country calling code, e.g. `+91`.
  final String dialCode;

  /// A made-up number in the local format, for hints.
  final String examplePhone;

  /// (lat, lng) where a map opens when the phone's position isn't known yet:
  /// the market's launch city, never somewhere on another continent.
  final (double, double) cityCenter;

  // Indian state / union-territory codes, the first two letters of a plate.
  static const _inStates =
      'AN|AP|AR|AS|BR|CH|CG|DD|DL|DN|GA|GJ|HR|HP|JK|JH|KA|KL|LA|LD|MP|MH|MN|ML|MZ|NL|OD|OR|PY|PB|RJ|SK|TN|TS|TR|UP|UK|UA|WB';

  /// A plate as typed ("mh12-ab 1234") in its stored form ("MH12AB1234").
  static String normalizePlate(String typed) =>
      typed.toUpperCase().replaceAll(RegExp(r'[\s\-.]'), '');

  /// Whether [typed] can be a real plate here — the same rule the server
  /// applies, so a driver learns about a typo before sending.
  bool isValidPlate(String typed) {
    final p = normalizePlate(typed);
    if (code == 'in') {
      return RegExp('^($_inStates)\\d{1,2}[A-Z]{0,3}\\d{1,4}\$').hasMatch(p) ||
          RegExp(r'^\d{2}BH\d{4}[A-Z]{1,2}$').hasMatch(p);
    }
    return RegExp(r'^[A-Z0-9]{2,12}$').hasMatch(p);
  }

  /// A plate the way it is printed on the car, for riders to match:
  /// "MH12AB1234" → "MH 12 AB 1234". Plates that don't parse come back as-is.
  String formatPlate(String plate) {
    final p = normalizePlate(plate);
    if (code != 'in') return p;
    final m = RegExp(r'^([A-Z]{2})(\d{1,2})([A-Z]{0,3})(\d{1,4})$').firstMatch(p);
    if (m == null) return p;
    return [m[1], m[2], m[3], m[4]].where((g) => g != null && g.isNotEmpty).join(' ');
  }

  /// An example plate for hints and errors.
  String get examplePlate => code == 'in' ? 'MH 12 AB 1234' : 'ABC 1234';

  /// A typed phone number as E.164, or null when it can't be one. People type
  /// numbers the local way ("98765 43210", "098765 43210"), so a number
  /// without a leading `+` gets this market's [dialCode] (a leading trunk 0
  /// dropped); one with `+` is taken as international.
  String? toE164(String typed) {
    var digits = typed.replaceAll(RegExp(r'[\s\-()]'), '');
    if (digits.isEmpty) return null;
    if (!digits.startsWith('+')) {
      digits = digits.replaceFirst(RegExp(r'^0+'), '');
      digits = '$dialCode$digits';
    }
    return RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(digits) ? digits : null;
  }

  static Market parse(String? code) {
    switch ((code ?? '').trim().toLowerCase()) {
      case 'in':
        return india;
      case 'uz':
        return uzbekistan;
      case 'us':
        return unitedStates;
      default:
        return unitedStates;
    }
  }

  /// The build's market, from `--dart-define=MARKET=...` (US when unset).
  static Market fromEnvironment() =>
      parse(const String.fromEnvironment('MARKET'));

  /// The market every formatter reads. Set once at app start
  /// (`Market.current = Market.fromEnvironment()`); tests set it directly.
  static Market current = fromEnvironment();

  static const _metresPerMile = 1609.344;
  static const _metresPerFoot = 0.3048;

  /// A distance as people in this market say it: "850 m" / "12.3 km", or
  /// "350 ft" / "0.4 mi". [approx] prefixes "~" (straight-line estimates).
  String distance(int metres, {bool approx = false}) {
    final m = metres < 0 ? 0 : metres;
    final prefix = approx ? '~' : '';
    if (metric) {
      if (m < 1000) return '$prefix${(m / 10).round() * 10} m';
      return '$prefix${(m / 1000).toStringAsFixed(1)} km';
    }
    if (m < _metresPerMile / 10) {
      return '$prefix${(m / _metresPerFoot / 10).round() * 10} ft';
    }
    return '$prefix${(m / _metresPerMile).toStringAsFixed(1)} mi';
  }

  /// Always in the long unit, one decimal: "0.3 km" / "0.1 mi". For trip legs,
  /// where "0.3 km" next to "4.2 km" reads better than "300 m".
  String legDistance(int metres, {bool approx = false}) {
    final m = metres < 0 ? 0 : metres;
    final prefix = approx ? '~' : '';
    return metric
        ? '$prefix${(m / 1000).toStringAsFixed(1)} km'
        : '$prefix${(m / _metresPerMile).toStringAsFixed(1)} mi';
  }

  /// "< 150 m" / "< 500 ft": close enough to be "practically there".
  String? nearLabel(int metres) {
    if (metric) return metres < 150 ? '< 150 m' : null;
    return metres < 500 * _metresPerFoot ? '< 500 ft' : null;
  }

  /// Unit for a per-distance price: "km" or "mi".
  String get distanceUnit => metric ? 'km' : 'mi';
}

/// How money reads in a given currency: symbol, position, decimals.
class Money {
  Money._();

  static const _known = <String, (String, bool, int)>{
    // code: (symbol, symbol before the number, decimals)
    'USD': ('\$', true, 2),
    'INR': ('₹', true, 2),
    // Uzbek som has no coins in use: whole som, symbol after.
    'UZS': ("so'm", false, 0),
  };

  /// "₹245", "₹245.50", "\$12.30", "18 500 so'm"; an unknown code reads
  /// "EUR 12.30". [currency] defaults to the current market's.
  /// [wholeOnly] rounds to whole units (price ranges, presets).
  static String format(double amount, {String? currency, bool wholeOnly = false}) {
    final code = (currency ?? Market.current.currency).toUpperCase();
    final spec = _known[code];
    final decimals = wholeOnly ? 0 : (spec?.$3 ?? 2);
    final abs = amount.abs();
    final whole = (abs - abs.roundToDouble()).abs() < 0.005;
    var n = abs.toStringAsFixed(whole || decimals == 0 ? 0 : decimals);
    if ((spec?.$3 ?? 2) == 0) {
      n = n.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ' ');
    }
    final sign = amount < 0 ? '-' : '';
    if (spec == null) return '$sign$code $n';
    return spec.$2 ? '$sign${spec.$1}$n' : '$sign$n ${spec.$1}';
  }

  /// The bare symbol for input prefixes: "₹", "\$", "so'm".
  static String symbol([String? currency]) {
    final code = (currency ?? Market.current.currency).toUpperCase();
    return _known[code]?.$1 ?? code;
  }
}
