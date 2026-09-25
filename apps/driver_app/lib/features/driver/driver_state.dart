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
    this.endNote,
    this.needsOnboarding = false,
    this.connected = true,
    this.approachPolyline,
    this.locationIssue,
    this.riderName,
    this.unreadMessages = 0,
    this.riderComingAt,
    this.stopsReached = 0,
    this.stopsChangedAt,
  });

  final DriverPhase phase;
  final RideOffer? offer;
  final Trip? trip;
  final bool busy;
  final String? error;

  /// Today's earnings total as last fetched (`/drivers/me/earnings?range=
  /// today` on init and after each completed trip) — not the last trip's fare.
  final double? lastEarned;
  final String? lastTripId;
  final int? riderRating;

  /// Cash the driver must collect for the just-completed trip (null for card).
  final double? cashToCollect;

  /// Non-blocking note when the trip ended away from the drop-off
  /// ("Ended 0.8 km before the drop-off · minimum fare"); null otherwise.
  final String? endNote;
  final bool needsOnboarding;

  /// Live socket connectivity. False shows a "reconnecting" banner.
  final bool connected;

  /// Encoded route from the driver's position to the pickup, sent on
  /// `trip:assigned`. Drawn while heading to pickup so the driver sees exactly
  /// where they're collecting the rider from (Uber-style approach leg).
  final String? approachPolyline;

  /// Display name of the rider on the assigned trip (from the accepted offer),
  /// used for the chat header. Null when no trip is assigned.
  final String? riderName;

  /// Rider messages received while the chat page was not open.
  final int unreadMessages;

  /// When the rider tapped "I'm on my way" for the current pickup, or null.
  final DateTime? riderComingAt;

  /// How many of the trip's stops the car has already reached (in order).
  final int stopsReached;

  /// When the rider last added a stop to this trip, or null.
  final DateTime? stopsChangedAt;

  /// The trip's stops still ahead.
  List<TripStop> get stopsAhead {
    final all = trip?.stops ?? const <TripStop>[];
    return stopsReached >= all.length ? const [] : all.sublist(stopsReached);
  }

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
    Object? endNote = _s,
    bool? needsOnboarding,
    bool? connected,
    Object? approachPolyline = _s,
    Object? riderName = _s,
    int? unreadMessages,
    Object? locationIssue = _s,
    Object? riderComingAt = _s,
    int? stopsReached,
    Object? stopsChangedAt = _s,
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
      endNote: endNote == _s ? this.endNote : endNote as String?,
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
      connected: connected ?? this.connected,
      approachPolyline: approachPolyline == _s
          ? this.approachPolyline
          : approachPolyline as String?,
      riderName: riderName == _s ? this.riderName : riderName as String?,
      unreadMessages: unreadMessages ?? this.unreadMessages,
      riderComingAt: riderComingAt == _s
          ? this.riderComingAt
          : riderComingAt as DateTime?,
      stopsReached: stopsReached ?? this.stopsReached,
      stopsChangedAt: stopsChangedAt == _s
          ? this.stopsChangedAt
          : stopsChangedAt as DateTime?,
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
        endNote,
        needsOnboarding,
        connected,
        approachPolyline,
        riderName,
        unreadMessages,
        locationIssue,
        riderComingAt,
        stopsReached,
        stopsChangedAt,
      ];
}
