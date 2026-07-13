// This file is only ever compiled into the web build (selected via the
// conditional import in injector.dart), so using dart:html here is correct.
// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'token_storage.dart';

/// Web token storage backed directly by `window.localStorage`. Avoids both
/// `flutter_secure_storage` (its `crypto.subtle` throws on insecure HTTP
/// origins) and `shared_preferences` (its method channel throws
/// `MissingPluginException` on web here). `localStorage` is a plain synchronous
/// JS API — no plugin channel, works on plain-HTTP/IP origins.
class LocalStorageStore implements KeyValueStore {
  @override
  Future<void> write(String key, String value) async =>
      html.window.localStorage[key] = value;

  @override
  Future<String?> read(String key) async => html.window.localStorage[key];

  @override
  Future<void> delete(String key) async =>
      html.window.localStorage.remove(key);
}

KeyValueStore createLocalStore() => LocalStorageStore();
