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

  factory AppConfig.fromEnvironment() =>
      const AppConfig(apiBaseUrl: _defaultBaseUrl);
}
