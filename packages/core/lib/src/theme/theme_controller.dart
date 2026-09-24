import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../network/token_storage.dart';

/// The rider's or driver's choice of Light, Dark or "same as my phone"
/// (System), like the Appearance setting in Uber. Saved on the device and
/// applied instantly: each app's MaterialApp listens to this notifier.
///
/// [value] is the saved choice (what the Appearance sheet shows); apps render
/// [effective], which is the same except while a ride holds the theme.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController(this._store, [super.initial = ThemeMode.system])
      : effective = ValueNotifier(initial);

  final KeyValueStore _store;

  /// The mode the app actually draws in. Differs from [value] only while
  /// [holdFor] is in force.
  final ValueNotifier<ThemeMode> effective;

  bool _held = false;
  bool get isHeld => _held;

  /// The mode a fresh install starts in, before the user picks one: Plan A
  /// (midnight) is a dark app, Plan B (daylight) a light one; everything else
  /// follows the phone.
  static const ThemeMode buildDefault = AppColors.variant == 'midnight'
      ? ThemeMode.dark
      : AppColors.variant == 'daylight'
          ? ThemeMode.light
          : ThemeMode.system;

  /// Freeze the app in [brightness] — for a ride in progress, so a phone
  /// switching to night mode (or the rider flipping the setting) never
  /// repaints the map and sheets mid-trip. A change made meanwhile is saved
  /// and applied on [release].
  void holdFor(Brightness brightness) {
    _held = true;
    effective.value =
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  /// End a [holdFor]: the saved choice applies again.
  void release() {
    if (!_held) return;
    _held = false;
    effective.value = value;
  }

  @override
  set value(ThemeMode mode) {
    super.value = mode;
    if (!_held) effective.value = mode;
  }

  static const storageKey = 'ui.theme_mode';

  /// Reads the saved choice; [buildDefault] when nothing (or something
  /// unreadable) is stored, so a storage problem can never block the app
  /// from starting.
  static Future<ThemeController> load(KeyValueStore store) async {
    ThemeMode mode = buildDefault;
    try {
      mode = switch (await store.read(storageKey)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        'system' => ThemeMode.system,
        _ => buildDefault,
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
