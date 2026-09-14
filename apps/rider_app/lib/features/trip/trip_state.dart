part of 'trip_cubit.dart';

/// Where the rider is in the request/ride flow.
enum TripPhase {
  idle, // map + "Where to?"
  loadingEstimate, // fetching route + fares
  choosingRide, // tier selection sheet
  requesting, // creating the trip
  scheduled, // a future ride was booked (not dispatched yet)
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
    this.liveEtaSec,
    this.liveRemainingM,
    this.driverRoutePolyline,
    this.fareFinal,
    this.receipt,
    this.tipAmount,
    this.tipping = false,
    this.rating,
    this.appliedPromo,
    this.applyingPromo = false,
    this.promoError,
    this.paymentMode = 'card',
    this.paymentMethods = const [],
    this.selectedMethodId,
    this.scheduledAt,
    this.stops = const [],
    this.connected = true,
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

  /// Live ETA (s) / distance left (m) along the current leg, recomputed from
  /// every driver ping — approach leg while matched, trip leg once started.
  final int? liveEtaSec;
  final int? liveRemainingM;

  /// Encoded polyline of the driver's route TO the pickup, shown on the map
  /// while the driver is en route/arriving (the "approach" leg). Null falls back
  /// to the trip route.
  final String? driverRoutePolyline;
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

  /// Saved payment methods (raw maps: id, brand, last4) for the checkout picker.
  final List<Map<String, dynamic>> paymentMethods;

  /// The specific saved card chosen at checkout (null = default/cash).
  final String? selectedMethodId;

  /// A future time to schedule the ride for; null means ride now.
  final DateTime? scheduledAt;

  /// Ordered intermediate stops for a multi-stop ride.
  final List<TripStop> stops;

  /// Live socket connectivity. False shows a "reconnecting" banner and means
  /// live trip updates are paused until the socket recovers.
  final bool connected;
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
    Object? liveEtaSec = _s,
    Object? liveRemainingM = _s,
    Object? driverRoutePolyline = _s,
    Object? fareFinal = _s,
    Object? receipt = _s,
    Object? tipAmount = _s,
    bool? tipping,
    Object? rating = _s,
    Object? appliedPromo = _s,
    bool? applyingPromo,
    Object? promoError = _s,
    String? paymentMode,
    List<Map<String, dynamic>>? paymentMethods,
    Object? selectedMethodId = _s,
    Object? scheduledAt = _s,
    List<TripStop>? stops,
    bool? connected,
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
      liveEtaSec: liveEtaSec == _s ? this.liveEtaSec : liveEtaSec as int?,
      liveRemainingM:
          liveRemainingM == _s ? this.liveRemainingM : liveRemainingM as int?,
      driverRoutePolyline: driverRoutePolyline == _s
          ? this.driverRoutePolyline
          : driverRoutePolyline as String?,
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
      paymentMethods: paymentMethods ?? this.paymentMethods,
      selectedMethodId: selectedMethodId == _s
          ? this.selectedMethodId
          : selectedMethodId as String?,
      scheduledAt:
          scheduledAt == _s ? this.scheduledAt : scheduledAt as DateTime?,
      stops: stops ?? this.stops,
      connected: connected ?? this.connected,
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
        liveEtaSec,
        liveRemainingM,
        driverRoutePolyline,
        fareFinal,
        receipt,
        tipAmount,
        tipping,
        rating,
        appliedPromo,
        applyingPromo,
        promoError,
        paymentMode,
        paymentMethods,
        selectedMethodId,
        scheduledAt,
        stops,
        connected,
        error,
      ];
}
