part of 'driver_cubit.dart';

enum DriverPhase {
  offline,
  online, // available, waiting for offers
  offered, // an offer is on screen
  enRoute, // accepted, driving to pickup
  arrived, // at pickup, awaiting start OTP
  onTrip, // driving to dropoff
  completed, // trip done — rate the rider, then back online
}

class DriverState extends Equatable {
  const DriverState({
    this.phase = DriverPhase.offline,
    this.offer,
    this.trip,
    this.busy = false,
    this.error,
    this.lastEarned,
    this.lastTripId,
    this.riderRating,
    this.cashToCollect,
    this.needsOnboarding = false,
    this.connected = true,
    this.approachPolyline,
    this.locationIssue,
  });

  final DriverPhase phase;
  final RideOffer? offer;
  final Trip? trip;
  final bool busy;
  final String? error;
  final double? lastEarned;
  final String? lastTripId;
  final int? riderRating;

  /// Cash the driver must collect for the just-completed trip (null for card).
  final double? cashToCollect;
  final bool needsOnboarding;

  /// Live socket connectivity. False shows a "reconnecting" banner.
  final bool connected;

  /// Encoded route from the driver's position to the pickup, sent on
  /// `trip:assigned`. Drawn while heading to pickup so the driver sees exactly
  /// where they're collecting the rider from (Uber-style approach leg).
  final String? approachPolyline;

  /// Why the last "go online" was refused for lack of location access (null
  /// when it wasn't). Lets the UI offer the right fix — open app settings for a
  /// permanent denial, the location-services page when GPS is switched off.
  final LocationAccess? locationIssue;

  bool get isOnline => phase != DriverPhase.offline;

  static const Object _s = Object();

  DriverState copyWith({
    DriverPhase? phase,
    Object? offer = _s,
    Object? trip = _s,
    bool? busy,
    Object? error = _s,
    Object? lastEarned = _s,
    Object? lastTripId = _s,
    Object? riderRating = _s,
    Object? cashToCollect = _s,
    bool? needsOnboarding,
    bool? connected,
    Object? approachPolyline = _s,
    Object? locationIssue = _s,
  }) {
    return DriverState(
      phase: phase ?? this.phase,
      offer: offer == _s ? this.offer : offer as RideOffer?,
      trip: trip == _s ? this.trip : trip as Trip?,
      busy: busy ?? this.busy,
      error: error == _s ? this.error : error as String?,
      lastEarned: lastEarned == _s ? this.lastEarned : lastEarned as double?,
      lastTripId: lastTripId == _s ? this.lastTripId : lastTripId as String?,
      riderRating: riderRating == _s ? this.riderRating : riderRating as int?,
      cashToCollect:
          cashToCollect == _s ? this.cashToCollect : cashToCollect as double?,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      connected: connected ?? this.connected,
      approachPolyline: approachPolyline == _s
          ? this.approachPolyline
          : approachPolyline as String?,
      locationIssue: locationIssue == _s
          ? this.locationIssue
          : locationIssue as LocationAccess?,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        offer,
        trip,
        busy,
        error,
        lastEarned,
        lastTripId,
        riderRating,
        cashToCollect,
        needsOnboarding,
        connected,
        approachPolyline,
        locationIssue,
      ];
}
