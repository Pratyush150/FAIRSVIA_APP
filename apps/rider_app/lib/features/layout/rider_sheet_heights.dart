import 'package:flutter/foundation.dart';

/// How the rider's screens split between the map and the sheet, as shares of
/// the screen height — one place for every proportion, chosen in the
/// proportion study (`docs/plans/proportion-study-2026-09-25.md`).
///
/// The map's bottom fit padding follows the *measured* sheet (home_page), so
/// route framing stays in step with whatever these say.
@immutable
class RiderSheetHeights {
  const RiderSheetHeights({
    required this.homeMap,
    required this.chooseRide,
    required this.expanded,
    required this.onTripPeek,
    required this.searching,
    required this.pickupCompact,
    required this.onTripCompact,
    required this.completed,
  });

  /// Idle Home: the map header above the Home sheet.
  final double homeMap;

  /// Choosing a ride: the sheet opens at this share (floor and cap).
  final double chooseRide;

  /// Every booking / ride sheet (choose ride, finding, en route, arrived,
  /// on trip, ride complete) is draggable: it opens at its own share (its
  /// "rest" size, the fields here) and a drag up or a tap on the handle
  /// pulls it up to this share — below the status bar, a map peek above.
  final double expanded;

  /// On trip only: a drag down past the rest size parks the card at this
  /// smaller peek (the status line), floored at [onTripPeekMinPx].
  final double onTripPeek;

  /// Finding a driver: fixed sheet share, or null to fit the content.
  final double? searching;

  /// Driver on the way / arrived: the compact glass card's cap (tall enough
  /// for the car, plate, PIN and the arrived phase's actions).
  final double pickupCompact;

  /// On trip: the compact glass card's cap (status, ETA, Details).
  final double onTripCompact;

  /// Ride complete: 1.0 is a full-screen page; less leaves a map peek.
  final double completed;

  /// The shipped proportions.
  static const standard = RiderSheetHeights(
    homeMap: 0.35,
    chooseRide: 0.62,
    expanded: 0.92,
    onTripPeek: 0.22,
    searching: null,
    pickupCompact: 0.50,
    onTripCompact: 0.36,
    // 75% (owner, 2026-09-25): map above stays visible; the whole page —
    // total, rating, favourite, tips, Done — fits without scrolling.
    completed: 0.75,
  );

  /// Floors in logical pixels, so a short phone (360×640) still shows the
  /// key content above the fold: a ride tier over the Confirm footer, the
  /// driver card with the PIN, the on-trip status with Details. On a tall
  /// phone the shares above win.
  static const double chooseRideMinPx = 480;
  static const double pickupCompactMinPx = 400;
  static const double onTripCompactMinPx = 320;
  static const double onTripPeekMinPx = 160;

  /// The on-trip peek, in logical pixels, on a screen [screenHeight] tall.
  double onTripPeekPx(double screenHeight) {
    final px = onTripPeek * screenHeight;
    return px < onTripPeekMinPx ? onTripPeekMinPx : px;
  }

  /// The expanded sheet, in logical pixels, on a screen [screenHeight] tall.
  double expandedPx(double screenHeight) => expanded * screenHeight;

  static double _atLeast(double fraction, double px, double screenHeight) {
    if (screenHeight <= 0) return fraction;
    final floor = px / screenHeight;
    return (floor > fraction ? floor : fraction).clamp(0.0, 0.9);
  }

  /// The ride-options share on a screen [screenHeight] tall.
  double chooseRideAt(double screenHeight) =>
      _atLeast(chooseRide, chooseRideMinPx, screenHeight);

  /// The compact live card's share on a screen [screenHeight] tall.
  double liveCompactAt({required bool onTrip, required double screenHeight}) =>
      onTrip
      ? _atLeast(onTripCompact, onTripCompactMinPx, screenHeight)
      : _atLeast(pickupCompact, pickupCompactMinPx, screenHeight);

  /// Test hook: the proportion study renders each screen at other splits.
  @visibleForTesting
  static RiderSheetHeights? debugOverride;

  /// The proportions in use.
  static RiderSheetHeights get current => debugOverride ?? standard;

  RiderSheetHeights copyWith({
    double? homeMap,
    double? chooseRide,
    double? searching,
    double? pickupCompact,
    double? onTripCompact,
    double? completed,
  }) => RiderSheetHeights(
    homeMap: homeMap ?? this.homeMap,
    chooseRide: chooseRide ?? this.chooseRide,
    expanded: expanded,
    onTripPeek: onTripPeek,
    searching: searching ?? this.searching,
    pickupCompact: pickupCompact ?? this.pickupCompact,
    onTripCompact: onTripCompact ?? this.onTripCompact,
    completed: completed ?? this.completed,
  );
}
