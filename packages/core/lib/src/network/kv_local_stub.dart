import 'token_storage.dart';

/// Non-web fallback. Never invoked at runtime (the injector only calls
/// [createLocalStore] when `kIsWeb`), but needed so the import resolves when
/// `dart:html` is unavailable (mobile/desktop).
KeyValueStore createLocalStore() =>
    throw UnsupportedError('createLocalStore is only available on web');
