import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// A point the driver is heading to, with a short label ("Home").
class DestinationPoint {
  const DestinationPoint({
    required this.lat,
    required this.lng,
    required this.label,
  });

  final double lat;
  final double lng;
  final String label;

  static DestinationPoint? maybe(Object? j) {
    if (j is! Map<String, dynamic>) return null;
    return DestinationPoint(
      lat: (j['lat'] as num).toDouble(),
      lng: (j['lng'] as num).toDouble(),
      label: (j['label'] as String?) ?? 'Destination',
    );
  }
}

/// Destination ("go home") mode as the backend reports it
/// (`GET /drivers/me/destination-mode`).
class DestinationModeStatus {
  const DestinationModeStatus({
    required this.active,
    required this.usesToday,
    required this.usesPerDay,
    this.destination,
    this.home,
    this.expiresAt,
    this.endedReason,
  });

  final bool active;
  final DestinationPoint? destination;
  final DestinationPoint? home;
  final int usesToday;
  final int usesPerDay;
  final DateTime? expiresAt;

  /// Why the mode just switched itself off ('arrived' / 'expired'), if it did.
  final String? endedReason;

  bool get limitReached => !active && usesToday >= usesPerDay;

  factory DestinationModeStatus.fromJson(Map<String, dynamic> j) =>
      DestinationModeStatus(
        active: j['active'] == true,
        destination: DestinationPoint.maybe(j['destination']),
        home: DestinationPoint.maybe(j['home']),
        usesToday: (j['usesToday'] as num?)?.toInt() ?? 0,
        usesPerDay: (j['usesPerDay'] as num?)?.toInt() ?? 2,
        expiresAt: j['expiresAt'] == null
            ? null
            : DateTime.tryParse(j['expiresAt'] as String),
        endedReason: j['endedReason'] as String?,
      );
}

/// `/drivers/me/destination-mode` — GET / POST {lat,lng,label} / DELETE.
class DestinationModeRemoteDataSource {
  DestinationModeRemoteDataSource(this._dio);

  final Dio _dio;

  Future<DestinationModeStatus> get() => _call(
    () => _dio.get<Map<String, dynamic>>('/drivers/me/destination-mode'),
  );

  Future<DestinationModeStatus> set({
    required double lat,
    required double lng,
    required String label,
    bool saveAsHome = false,
  }) => _call(
    () => _dio.post<Map<String, dynamic>>(
      '/drivers/me/destination-mode',
      data: {
        'lat': lat,
        'lng': lng,
        'label': label,
        if (saveAsHome) 'saveAsHome': true,
      },
    ),
  );

  Future<DestinationModeStatus> clear() => _call(
    () => _dio.delete<Map<String, dynamic>>('/drivers/me/destination-mode'),
  );

  Future<DestinationModeStatus> _call(
    Future<Response<Map<String, dynamic>>> Function() fn,
  ) async {
    try {
      final res = await fn();
      return DestinationModeStatus.fromJson(res.data!);
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
