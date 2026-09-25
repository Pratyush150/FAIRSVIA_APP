import 'package:core/core.dart';
import 'package:dio/dio.dart';

/// An incentive quest as ops sees it (`/admin/quests`).
class AdminQuest {
  const AdminQuest({
    required this.id,
    required this.title,
    required this.tiers,
    required this.targetTrips,
    required this.startsAt,
    required this.endsAt,
    required this.bonusAmount,
    required this.active,
    this.currency,
    this.awards = 0,
  });

  final String id;
  final String title;

  /// Empty = every tier.
  final List<String> tiers;
  final int targetTrips;
  final DateTime startsAt;
  final DateTime endsAt;
  final double bonusAmount;
  final String? currency;
  final bool active;

  /// Drivers paid so far.
  final int awards;

  factory AdminQuest.fromJson(Map<String, dynamic> j) => AdminQuest(
        id: j['id'] as String,
        title: j['title'] as String? ?? '',
        tiers: (j['tiers'] as List<dynamic>? ?? const []).cast<String>(),
        targetTrips: (j['targetTrips'] as num?)?.toInt() ?? 0,
        startsAt: DateTime.parse(j['startsAt'] as String).toLocal(),
        endsAt: DateTime.parse(j['endsAt'] as String).toLocal(),
        bonusAmount: double.tryParse('${j['bonusAmount']}') ?? 0,
        currency: j['currency'] as String?,
        active: j['active'] as bool? ?? true,
        awards: (j['awards'] as num?)?.toInt() ?? 0,
      );
}

/// Admin REST for quests: list, create, update (incl. switching off).
class QuestsApi {
  QuestsApi(this._dio);
  final Dio _dio;

  Future<List<AdminQuest>> list() async {
    final res = await _guard(() => _dio.get<List<dynamic>>('/admin/quests'));
    return (res.data ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(AdminQuest.fromJson)
        .toList();
  }

  Future<void> create(Map<String, dynamic> body) =>
      _guard(() => _dio.post<dynamic>('/admin/quests', data: body));

  Future<void> update(String id, Map<String, dynamic> body) =>
      _guard(() => _dio.patch<dynamic>('/admin/quests/$id', data: body));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
