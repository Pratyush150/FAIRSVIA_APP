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
    this.needsOnboarding = false,
  });

  final DriverPhase phase;
  final RideOffer? offer;
  final Trip? trip;
  final bool busy;
  final String? error;
  final double? lastEarned;
  final String? lastTripId;
  final int? riderRating;
  final bool needsOnboarding;

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
    bool? needsOnboarding,
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
      needsOnboarding: needsOnboarding ?? this.needsOnboarding,
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
        needsOnboarding,
      ];
}
