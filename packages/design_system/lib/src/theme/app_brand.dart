/// Product identity in one place. Every user-visible occurrence of the product
/// name (splash, app titles, share text, notification copy) reads it from here,
/// so a rename is a single edit rather than a grep across three apps.
abstract final class AppBrand {
  /// The product name as it is written to riders and drivers.
  static const String name = 'RideVela';

  /// Per-app window/task titles.
  static const String riderTitle = '$name Rider';
  static const String driverTitle = '$name Driver';
  static const String adminTitle = '$name Admin';

  // --- Splash timing (see BrandSplash) ---------------------------------------
  /// The wordmark fades in over this window.
  static const Duration splashFadeIn = Duration(milliseconds: 450);

  /// …then the launch motion: a car glides along a road line under the
  /// wordmark, drawing the brand-coloured route behind it (the Uber-style
  /// 1–2 s loading beat the owner asked for).
  static const Duration splashSettle = Duration(milliseconds: 1050);

  /// …then the splash fades out over the app. Total 1800ms — inside the 2 s
  /// hard cap; the app is never held longer than this.
  static const Duration splashHandover = Duration(milliseconds: 300);

  /// How long the splash owns the screen end to end.
  static Duration get splashTotal =>
      splashFadeIn + splashSettle + splashHandover;
}
