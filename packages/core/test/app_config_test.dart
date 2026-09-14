import 'package:core/core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppConfig.assertReleaseSafe', () {
    test('debug builds accept anything (localhost is the dev default)', () {
      expect(
        () => AppConfig.assertReleaseSafe(
          'http://localhost:3000/api/v1',
          releaseMode: false,
        ),
        returnsNormally,
      );
      expect(
        () => AppConfig.assertReleaseSafe('', releaseMode: false),
        returnsNormally,
      );
    });

    test('release build rejects an unset URL', () {
      expect(
        () => AppConfig.assertReleaseSafe('', releaseMode: true),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('unset'),
          ),
        ),
      );
    });

    test('release build rejects localhost / 127.0.0.1', () {
      for (final url in [
        'http://localhost:3000/api/v1',
        'http://127.0.0.1:3000/api/v1',
        'https://localhost/api/v1',
      ]) {
        expect(
          () => AppConfig.assertReleaseSafe(url, releaseMode: true),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains(url),
            ),
          ),
          reason: url,
        );
      }
    });

    test('release build accepts a real host', () {
      for (final url in [
        'https://api.fairsvia.com/api/v1',
        'http://192.168.1.48:3000/api/v1',
        'http://10.0.2.2:3000/api/v1',
      ]) {
        expect(
          () => AppConfig.assertReleaseSafe(url, releaseMode: true),
          returnsNormally,
          reason: url,
        );
      }
    });

    test('fromEnvironment in debug mode keeps the localhost default', () {
      // No --dart-define in tests, so the default (localhost) applies and must
      // still be allowed outside release mode.
      expect(
        AppConfig.fromEnvironment(releaseMode: false).apiBaseUrl,
        contains('localhost'),
      );
      expect(
        () => AppConfig.fromEnvironment(releaseMode: true),
        throwsA(isA<StateError>()),
      );
    });
  });
}
