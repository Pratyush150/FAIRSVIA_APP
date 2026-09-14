import 'dart:convert';

import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_models/shared_models.dart';

/// Answers /places/autocomplete with a canned list; records the query sent.
class _PlacesAdapter implements HttpClientAdapter {
  _PlacesAdapter(this.predictions);
  final List<Map<String, Object?>> predictions;
  Map<String, dynamic>? lastQuery;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    lastQuery = Map<String, dynamic>.from(options.queryParameters);
    return ResponseBody.fromString(
      jsonEncode({'predictions': predictions}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Map<String, Object?> _pred(String id, [num? distanceM]) => {
  'placeId': id,
  'primaryText': id,
  'secondaryText': '',
  'description': id,
  'distanceM': ?distanceM,
};

void main() {
  late _PlacesAdapter adapter;
  late PlacesRemoteDataSource source;

  PlacesRemoteDataSource build(List<Map<String, Object?>> preds) {
    adapter = _PlacesAdapter(preds);
    final dio = Dio(BaseOptions(baseUrl: 'http://test.local'))
      ..httpClientAdapter = adapter;
    return PlacesRemoteDataSource(dio);
  }

  test('sends the rider position as lat/lng and sorts nearest-first', () async {
    source = build([
      _pred('far', 5000),
      _pred('near', 120.4),
      _pred('mid', 900),
    ]);
    final out = await source.autocomplete(
      'cafe',
      sessionToken: 's1',
      near: const GeoPoint(25.77, -80.19),
    );
    expect(adapter.lastQuery, {
      'q': 'cafe',
      'sessionToken': 's1',
      'lat': 25.77,
      'lng': -80.19,
    });
    expect(out.map((p) => p.placeId), ['near', 'mid', 'far']);
    expect(out.first.distanceM, 120);
  });

  test('omits lat/lng without a position and keeps provider order when a '
      'distance is missing', () async {
    source = build([_pred('far', 5000), _pred('unknown'), _pred('near', 120)]);
    final out = await source.autocomplete('cafe');
    expect(adapter.lastQuery, {'q': 'cafe'});
    expect(out.map((p) => p.placeId), ['far', 'unknown', 'near']);
    expect(out[1].distanceM, isNull);
  });
}
