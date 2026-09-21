import 'package:flutter/foundation.dart';

/// Runtime configuration. The API base URL can be overridden at build time:
///   flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
///
/// Defaults:
///  - Android emulator reaches the host machine at 10.0.2.2
///  - Web/desktop/iOS-simulator reach it at localhost
class AppConfig {
  const AppConfig({required this.apiBaseUrl});

  final String apiBaseUrl;

  /// WebSocket origin — the API base URL with the `/api/v1` suffix stripped
  /// (Socket.IO shares the backend's HTTP port).
  String get wsUrl {
    final withoutApi = apiBaseUrl.replaceFirst(RegExp(r'/api/v\d+/?$'), '');
    return withoutApi.isEmpty ? apiBaseUrl : withoutApi;
  }

  static const String _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:3000/api/v1',
  );

  /// Builds the config from `--dart-define`s. In a release build this throws
  /// (see [assertReleaseSafe]) when `API_BASE_URL` was not supplied or points
  /// at the developer's own machine, so a device build can't ship silently
  /// talking to `localhost` and failing every request.
  factory AppConfig.fromEnvironment({bool releaseMode = kReleaseMode}) {
    assertReleaseSafe(_defaultBaseUrl, releaseMode: releaseMode);
    return const AppConfig(apiBaseUrl: _defaultBaseUrl);
  }

  /// Release-build guard for [url]. No-op unless [releaseMode]. Throws a
  /// [StateError] naming the fix when the URL is empty or loops back to the
  /// build machine (`localhost` / `127.0.0.1`), which is never reachable from a
  /// real device.
  static void assertReleaseSafe(String url, {required bool releaseMode}) {
    if (!releaseMode) return;
    final trimmed = url.trim();
    final loopback = RegExp(r'(^|//|@)(localhost|127\.0\.0\.1)(:|/|$)');
    if (trimmed.isEmpty || loopback.hasMatch(trimmed)) {
      throw StateError(
        'API_BASE_URL is ${trimmed.isEmpty ? 'unset' : '"$trimmed"'} in a '
        'release build. Pass a reachable backend, e.g. '
        '--dart-define=API_BASE_URL=https://api.example.com/api/v1',
      );
    }
  }
}
