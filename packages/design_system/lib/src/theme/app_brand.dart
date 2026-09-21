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
  static const Duration splashFadeIn = Duration(milliseconds: 500);

  /// …then settles with a subtle scale/opacity lift.
  static const Duration splashSettle = Duration(milliseconds: 500);

  /// …then hands over to the app. Total 1400ms, per the brand-signature spec:
  /// long enough to register, short enough that it never reads as a loader.
  static const Duration splashHandover = Duration(milliseconds: 400);

  /// How long the splash owns the screen end to end.
  static Duration get splashTotal =>
      splashFadeIn + splashSettle + splashHandover;
}
