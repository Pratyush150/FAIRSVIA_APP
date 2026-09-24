import 'package:flutter/material.dart';

import '../network/token_storage.dart';

/// The rider's or driver's choice of Light, Dark or "same as my phone"
/// (System), like the Appearance setting in Uber. Saved on the device and
/// applied instantly: each app's MaterialApp listens to this notifier.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(this._store, [super.initial = ThemeMode.system]);

  final KeyValueStore _store;

  static const storageKey = 'ui.theme_mode';

  /// Reads the saved choice; System when nothing (or something unreadable) is
  /// stored, so a storage problem can never block the app from starting.
  static Future<ThemeController> load(KeyValueStore store) async {
    ThemeMode mode = ThemeMode.system;
    try {
      mode = switch (await store.read(storageKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
    } catch (_) {}
    return ThemeController(store, mode);
  }

  Future<void> set(ThemeMode mode) async {
    value = mode;
    try {
      await _store.write(storageKey, mode.name);
    } catch (_) {
      // Still applied for this session; only the memory of it is lost.
    }
  }

  static String label(ThemeMode mode) => switch (mode) {
    ThemeMode.light => 'Light',
    ThemeMode.dark => 'Dark',
    ThemeMode.system => 'Same as phone',
  };
}
