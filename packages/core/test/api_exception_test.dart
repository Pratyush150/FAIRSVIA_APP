import 'package:core/core.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

DioException _dio(int status, Object? data) {
  final options = RequestOptions(path: '/trips');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(requestOptions: options, statusCode: status, data: data),
  );
}

void main() {
  group('ApiException.fromDio', () {
    test('exposes the backend code and the decoded body', () {
      final e = ApiException.fromDio(
        _dio(409, {
          'statusCode': 409,
          'code': 'PRICE_CHANGED',
          'message': 'The price has changed. Please confirm the new fare.',
          'fare': 8.22,
          'surge': 1.2,
          'estimate': {
            'tier': 'economy',
            'fare': 8.22,
            'surge': 1.2,
            'currency': 'USD',
          },
        }),
      );
      expect(e.statusCode, 409);
      expect(e.code, 'PRICE_CHANGED');
      expect(e.message, 'The price has changed. Please confirm the new fare.');
      expect(e.body?['fare'], 8.22);
      expect(e.body?['surge'], 1.2);
      expect((e.body?['estimate'] as Map)['tier'], 'economy');
    });

    test('joins a validation message list; code/body null-safe', () {
      final e = ApiException.fromDio(
        _dio(400, {
          'statusCode': 400,
          'message': ['tier must be a string', 'pickupLat must be a number'],
        }),
      );
      expect(e.message, 'tier must be a string, pickupLat must be a number');
      expect(e.code, isNull);
      expect(e.body, isNotNull);
      // A non-string code is ignored rather than crashing.
      final odd = ApiException.fromDio(_dio(400, {'message': 'x', 'code': 7}));
      expect(odd.code, isNull);
    });

    test('a non-JSON body yields the generic message and no body', () {
      final e = ApiException.fromDio(_dio(502, '<html>Bad gateway</html>'));
      expect(e.statusCode, 502);
      expect(e.code, isNull);
      expect(e.body, isNull);
      expect(e.message, 'Something went wrong. Please try again.');
    });

    test('connectivity failures get the offline hint', () {
      final e = ApiException.fromDio(
        DioException(
          requestOptions: RequestOptions(path: '/x'),
          type: DioExceptionType.connectionError,
        ),
      );
      expect(e.message, 'Cannot reach the server. Check your connection.');
      expect(e.statusCode, isNull);
    });
  });
}
