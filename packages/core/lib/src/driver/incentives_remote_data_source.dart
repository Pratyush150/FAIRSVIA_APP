import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// A driver's acceptance and cancellation rates over the last 7 days
/// (`GET /drivers/me/stats`). Rates are fractions 0..1, or null when there is
/// nothing to divide by yet (a new driver has no rate, not a 0% one).
class DriverStats {
  const DriverStats({
    required this.window,
    this.acceptanceRate,
    this.cancellationRate,
    this.offers = 0,
    this.accepted = 0,
    this.declined = 0,
    this.expired = 0,
    this.cancelled = 0,
  });

  final String window;
  final double? acceptanceRate;
  final double? cancellationRate;
  final int offers;
  final int accepted;
  final int declined;
  final int expired;

  /// Driver cancels of accepted trips; rider no-shows are never counted.
  final int cancelled;

  /// Below this acceptance the rate is flagged (amber).
  static const acceptanceWarnBelow = 0.70;

  /// Above this cancellation the rate is flagged (amber).
  static const cancellationWarnAbove = 0.10;

  bool get acceptanceLow =>
      acceptanceRate != null && acceptanceRate! < acceptanceWarnBelow;
  bool get cancellationHigh =>
      cancellationRate != null && cancellationRate! > cancellationWarnAbove;

  factory DriverStats.fromJson(Map<String, dynamic> j) => DriverStats(
        window: j['window'] as String? ?? '7d',
        acceptanceRate: (j['acceptanceRate'] as num?)?.toDouble(),
        cancellationRate: (j['cancellationRate'] as num?)?.toDouble(),
        offers: (j['offers'] as num?)?.toInt() ?? 0,
        accepted: (j['accepted'] as num?)?.toInt() ?? 0,
        declined: (j['declined'] as num?)?.toInt() ?? 0,
        expired: (j['expired'] as num?)?.toInt() ?? 0,
        cancelled: (j['cancelled'] as num?)?.toInt() ?? 0,
      );

  /// "92%" or "—" when there is no rate yet.
  static String percent(double? rate) =>
      rate == null ? '—' : '${(rate * 100).round()}%';
}

/// One incentive quest with this driver's progress (`GET /drivers/me/quests`).
class DriverQuest {
  const DriverQuest({
    required this.id,
    required this.title,
    required this.progress,
    required this.target,
    required this.bonus,
    required this.endsAt,
    this.startsAt,
    this.currency,
    this.completed = false,
    this.paid = false,
    this.status = 'active',
  });

  final String id;
  final String title;
  final int progress;
  final int target;
  final double bonus;
  final String? currency;
  final DateTime? startsAt;
  final DateTime endsAt;
  final bool completed;
  final bool paid;

  /// upcoming | active | ended
  final String status;

  double get fraction => target <= 0 ? 0 : (progress / target).clamp(0, 1);
  bool get isActive => status == 'active';

  factory DriverQuest.fromJson(Map<String, dynamic> j) => DriverQuest(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Quest',
        progress: (j['progress'] as num?)?.toInt() ?? 0,
        target: (j['target'] as num?)?.toInt() ?? 1,
        bonus: (j['bonus'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String?,
        startsAt: DateTime.tryParse(j['startsAt'] as String? ?? '')?.toLocal(),
        endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
        completed: j['completed'] as bool? ?? false,
        paid: j['paid'] as bool? ?? false,
        status: j['status'] as String? ?? 'active',
      );
}

/// REST for driver incentives: rates and quests.
class IncentivesRemoteDataSource {
  IncentivesRemoteDataSource(this._dio);

  final Dio _dio;

  Future<DriverStats> stats() async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>('/drivers/me/stats'),
    );
    return DriverStats.fromJson(res.data!);
  }

  Future<List<DriverQuest>> quests() async {
    final res = await _guard(
      () => _dio.get<List<dynamic>>('/drivers/me/quests'),
    );
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DriverQuest.fromJson)
        .toList();
  }

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
