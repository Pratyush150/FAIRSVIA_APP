import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// A promotional / recommendation card shown under the ride details.
class RideCard {
  const RideCard({
    required this.id,
    required this.title,
    required this.body,
    this.ctaType = 'none',
    this.ctaLabel,
    this.ctaValue,
  });

  factory RideCard.fromJson(Map<String, dynamic> j) => RideCard(
        id: j['id'] as String,
        title: j['title'] as String,
        body: j['body'] as String,
        ctaType: j['ctaType'] as String? ?? 'none',
        ctaLabel: j['ctaLabel'] as String?,
        ctaValue: j['ctaValue'] as String?,
      );

  final String id;
  final String title;
  final String body;

  /// none | promo_code | url
  final String ctaType;
  final String? ctaLabel;
  final String? ctaValue;

  bool get hasAction =>
      ctaType != 'none' && (ctaLabel?.isNotEmpty ?? false) && (ctaValue?.isNotEmpty ?? false);
}

/// Admin-managed content (`/content/*`).
class ContentRemoteDataSource {
  ContentRemoteDataSource(this._dio);
  final Dio _dio;

  Future<List<RideCard>> rideCards() async {
    try {
      final res = await _dio.get<List<dynamic>>('/content/ride-cards');
      return (res.data ?? const [])
          .cast<Map<String, dynamic>>()
          .map(RideCard.fromJson)
          .toList();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
