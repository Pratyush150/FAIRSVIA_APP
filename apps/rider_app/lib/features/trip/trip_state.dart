part of 'trip_cubit.dart';

/// Where the rider is in the request/ride flow.
enum TripPhase {
  idle, // map + "Where to?"
  loadingEstimate, // fetching route + fares
  choosingRide, // tier selection sheet
  requesting, // creating the trip
  searching, // trip created (REQUESTED/MATCHING) — finding a driver
  driverEnRoute, // matched; driver heading to pickup
  driverArrived, // driver at pickup
  onTrip, // trip in progress
  completed, // trip finished (fare shown)
  error,
}

class TripState extends Equatable {
  const TripState({
    this.phase = TripPhase.idle,
    this.pickup,
    this.pickupAddr,
    this.dropoff,
    this.dropoffAddr,
    this.estimate,
    this.selectedTier,
    this.trip,
    this.driver,
    this.driverLocation,
    this.fareFinal,
    this.receipt,
    this.tipAmount,
    this.tipping = false,
    this.rating,
    this.appliedPromo,
    this.applyingPromo = false,
    this.promoError,
    this.paymentMode = 'card',
    this.error,
  });

  final TripPhase phase;
  final GeoPoint? pickup;
  final String? pickupAddr;
  final GeoPoint? dropoff;
  final String? dropoffAddr;
  final TripEstimate? estimate;
  final String? selectedTier;
  final Trip? trip;
  final AssignedDriver? driver;
  final GeoPoint? driverLocation;
  final double? fareFinal;
  final Receipt? receipt;
  final double? tipAmount;
  final bool tipping;
  final int? rating;

  /// A promo code the rider has applied (server-priced); null when none.
  final PromoQuote? appliedPromo;

  /// True while a promo code is being validated.
  final bool applyingPromo;

  /// The last promo rejection reason (cleared on a successful apply/remove).
  final String? promoError;

  /// Rider's chosen payment mode for the next ride: `card` or `cash`.
  final String paymentMode;
  final String? error;

  FareTier? get selectedFare {
    final tiers = estimate?.tiers;
    if (tiers == null || selectedTier == null) return null;
    for (final t in tiers) {
      if (t.tier == selectedTier) return t;
    }
    return null;
  }

  /// The selected tier's fare after the applied promo discount (if any).
  double? get discountedFare {
    final fare = selectedFare?.fare;
    if (fare == null) return null;
    final promo = appliedPromo;
    if (promo == null) return fare;
    final net = fare - promo.discount;
    return net < 0 ? 0 : net;
  }

  static const Object _s = Object();

  TripState copyWith({
    TripPhase? phase,
    Object? pickup = _s,
    Object? pickupAddr = _s,
    Object? dropoff = _s,
    Object? dropoffAddr = _s,
    Object? estimate = _s,
    Object? selectedTier = _s,
    Object? trip = _s,
    Object? driver = _s,
    Object? driverLocation = _s,
    Object? fareFinal = _s,
    Object? receipt = _s,
    Object? tipAmount = _s,
    bool? tipping,
    Object? rating = _s,
    Object? appliedPromo = _s,
    bool? applyingPromo,
    Object? promoError = _s,
    String? paymentMode,
    Object? error = _s,
  }) {
    return TripState(
      phase: phase ?? this.phase,
      pickup: pickup == _s ? this.pickup : pickup as GeoPoint?,
      pickupAddr: pickupAddr == _s ? this.pickupAddr : pickupAddr as String?,
      dropoff: dropoff == _s ? this.dropoff : dropoff as GeoPoint?,
      dropoffAddr:
          dropoffAddr == _s ? this.dropoffAddr : dropoffAddr as String?,
      estimate: estimate == _s ? this.estimate : estimate as TripEstimate?,
      selectedTier:
          selectedTier == _s ? this.selectedTier : selectedTier as String?,
      trip: trip == _s ? this.trip : trip as Trip?,
      driver: driver == _s ? this.driver : driver as AssignedDriver?,
      driverLocation: driverLocation == _s
          ? this.driverLocation
          : driverLocation as GeoPoint?,
      fareFinal: fareFinal == _s ? this.fareFinal : fareFinal as double?,
      receipt: receipt == _s ? this.receipt : receipt as Receipt?,
      tipAmount: tipAmount == _s ? this.tipAmount : tipAmount as double?,
      tipping: tipping ?? this.tipping,
      rating: rating == _s ? this.rating : rating as int?,
      appliedPromo: appliedPromo == _s
          ? this.appliedPromo
          : appliedPromo as PromoQuote?,
      applyingPromo: applyingPromo ?? this.applyingPromo,
      promoError: promoError == _s ? this.promoError : promoError as String?,
      paymentMode: paymentMode ?? this.paymentMode,
      error: error == _s ? this.error : error as String?,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        pickup,
        pickupAddr,
        dropoff,
        dropoffAddr,
        estimate,
        selectedTier,
        trip,
        driver,
        driverLocation,
        fareFinal,
        receipt,
        tipAmount,
        tipping,
        rating,
        appliedPromo,
        applyingPromo,
        promoError,
        paymentMode,
        error,
      ];
}
