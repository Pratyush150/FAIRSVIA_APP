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

/// A live-ride advisory raised by the server's GPS watchdogs: the driver has
/// left the route, or has been stationary long enough to be worth mentioning.
/// Advisory only — neither changes the ride, the fare, or what the rider can do.
enum TripAlertKind { offRoute, driverStopped }

/// One raised advisory. [raisedAt] makes two consecutive alerts of the same
/// kind distinct values, so the UI's listener fires for the second one too.
class TripAlert extends Equatable {
  TripAlert(this.kind, {this.stoppedSec, DateTime? raisedAt})
      : raisedAt = raisedAt ?? DateTime.now();

  final TripAlertKind kind;

  /// How long the driver had been stationary, for [TripAlertKind.driverStopped].
  final int? stoppedSec;
  final DateTime raisedAt;

  @override
  List<Object?> get props => [kind, stoppedSec, raisedAt];
}

class TripState extends Equatable {
  const TripState({
    this.phase = TripPhase.idle,
    this.pickup,
    this.pickupAddr,
    this.dropoff,
    this.dropoffAddr,
    this.pickupNote,
    this.estimate,
    this.selectedTier,
    this.trip,
    this.driver,
    this.driverLocation,
    this.driverHeading,
    this.driverSeenAt,
    this.driverStale = false,
    this.liveEtaSec,
    this.liveRemainingM,
    this.unreadMessages = 0,
    this.driverRoutePolyline,
    this.fareFinal,
    this.breakdown,
    this.receipt,
    this.tipAmount,
    this.tipping = false,
    this.rating,
    this.ratingTags = const [],
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
    this.notice,
    this.alert,
    this.liveRoutePolyline,
    this.liveRouteLeg,
  });

  final TripPhase phase;
  final GeoPoint? pickup;
  final String? pickupAddr;
  final GeoPoint? dropoff;
  final String? dropoffAddr;

  /// A short note for the driver about the pickup, entered before confirming.
  final String? pickupNote;
  final TripEstimate? estimate;
  final String? selectedTier;
  final Trip? trip;
  final AssignedDriver? driver;
  final GeoPoint? driverLocation;

  /// Compass heading (degrees) from the driver's last ping, so the car marker
  /// keeps pointing the right way even while no new fix arrives.
  final double? driverHeading;

  /// When the last driver ping arrived. Null until the first one.
  final DateTime? driverSeenAt;

  /// No driver ping for [TripCubit.staleAfter]: the car on the map may be
  /// stale, so the matched sheet says "Waiting for your driver's location…".
  final bool driverStale;

  /// Live ETA (s) / distance left (m) along the current leg, recomputed from
  /// every driver ping — approach leg while matched, trip leg once started.
  final int? liveEtaSec;
  final int? liveRemainingM;

  /// Driver messages received while the chat page was not open.
  final int unreadMessages;

  /// Encoded polyline of the driver's route TO the pickup, shown on the map
  /// while the driver is en route/arriving (the "approach" leg). Null falls back
  /// to the trip route.
  final String? driverRoutePolyline;
  final double? fareFinal;

  /// Itemised fare from the `trip:completed` event (the receipt's copy wins
  /// once it loads). Null for trips the backend settled without one.
  final FareBreakdown? breakdown;
  final Receipt? receipt;
  final double? tipAmount;
  final bool tipping;
  final int? rating;

  /// Compliment tags the rider attached to their driver rating (Uber-style).
  final List<String> ratingTags;

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

  /// One-shot informational message (e.g. a payment warning) for the UI to
  /// show as a snackbar; cleared with [TripCubit.clearNotice] once shown.
  final String? notice;

  /// The advisory currently worth showing the rider, or null. Cleared by
  /// [TripCubit.clearAlert] once shown, and by the server's own "all clear"
  /// events (back on route / moving again).
  final TripAlert? alert;

  /// The route the server recomputed after the driver left the planned one —
  /// the road actually being driven. Preferred over the planned line so the
  /// map and the server's ETA describe the same path.
  final String? liveRoutePolyline;

  /// Which leg [liveRoutePolyline] belongs to ('approach' or 'trip'), so a
  /// line from the previous leg is never drawn on this one.
  final String? liveRouteLeg;

  /// The breakdown to draw on the completion sheet: the receipt's (it also
  /// carries the tip) over the socket event's.
  FareBreakdown? get fareBreakdown => receipt?.breakdown ?? breakdown;

  /// What this ride costs, from the best source we currently hold, or null when
  /// nothing has priced it yet.
  ///
  /// Each source counts only when it is non-null AND greater than zero, falling
  /// through otherwise. No ride here is free — there is a minimum fare — so a
  /// zero always means a number we failed to load, and showing the rider a
  /// confident "\$0.00" for that is worse than showing what we quoted them.
  double? get displayFare {
    for (final candidate in [
      receipt?.fare,
      fareFinal,
      trip?.fareFinal,
      trip?.fareEstimate,
      discountedFare,
      selectedFare?.fare,
    ]) {
      if (candidate != null && candidate > 0) return candidate;
    }
    return null;
  }

  /// True once the fare is settled rather than an estimate the metered
  /// distance can still move.
  bool get fareIsFinal =>
      (receipt?.fare ?? fareFinal ?? trip?.fareFinal ?? 0) > 0;

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
    Object? pickupNote = _s,
    Object? estimate = _s,
    Object? selectedTier = _s,
    Object? trip = _s,
    Object? driver = _s,
    Object? driverLocation = _s,
    Object? driverHeading = _s,
    Object? driverSeenAt = _s,
    bool? driverStale,
    Object? liveEtaSec = _s,
    Object? liveRemainingM = _s,
    int? unreadMessages,
    Object? driverRoutePolyline = _s,
    Object? fareFinal = _s,
    Object? breakdown = _s,
    Object? receipt = _s,
    Object? tipAmount = _s,
    bool? tipping,
    Object? rating = _s,
    List<String>? ratingTags,
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
    Object? notice = _s,
    Object? alert = _s,
    Object? liveRoutePolyline = _s,
    Object? liveRouteLeg = _s,
  }) {
    return TripState(
      phase: phase ?? this.phase,
      pickup: pickup == _s ? this.pickup : pickup as GeoPoint?,
      pickupAddr: pickupAddr == _s ? this.pickupAddr : pickupAddr as String?,
      dropoff: dropoff == _s ? this.dropoff : dropoff as GeoPoint?,
      dropoffAddr:
          dropoffAddr == _s ? this.dropoffAddr : dropoffAddr as String?,
      pickupNote: pickupNote == _s ? this.pickupNote : pickupNote as String?,
      estimate: estimate == _s ? this.estimate : estimate as TripEstimate?,
      selectedTier:
          selectedTier == _s ? this.selectedTier : selectedTier as String?,
      trip: trip == _s ? this.trip : trip as Trip?,
      driver: driver == _s ? this.driver : driver as AssignedDriver?,
      driverLocation: driverLocation == _s
          ? this.driverLocation
          : driverLocation as GeoPoint?,
      driverHeading:
          driverHeading == _s ? this.driverHeading : driverHeading as double?,
      driverSeenAt:
          driverSeenAt == _s ? this.driverSeenAt : driverSeenAt as DateTime?,
      driverStale: driverStale ?? this.driverStale,
      liveEtaSec: liveEtaSec == _s ? this.liveEtaSec : liveEtaSec as int?,
      liveRemainingM:
          liveRemainingM == _s ? this.liveRemainingM : liveRemainingM as int?,
      unreadMessages: unreadMessages ?? this.unreadMessages,
      driverRoutePolyline: driverRoutePolyline == _s
          ? this.driverRoutePolyline
          : driverRoutePolyline as String?,
      fareFinal: fareFinal == _s ? this.fareFinal : fareFinal as double?,
      breakdown:
          breakdown == _s ? this.breakdown : breakdown as FareBreakdown?,
      receipt: receipt == _s ? this.receipt : receipt as Receipt?,
      tipAmount: tipAmount == _s ? this.tipAmount : tipAmount as double?,
      tipping: tipping ?? this.tipping,
      rating: rating == _s ? this.rating : rating as int?,
      ratingTags: ratingTags ?? this.ratingTags,
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
      notice: notice == _s ? this.notice : notice as String?,
      alert: alert == _s ? this.alert : alert as TripAlert?,
      liveRoutePolyline: liveRoutePolyline == _s
          ? this.liveRoutePolyline
          : liveRoutePolyline as String?,
      liveRouteLeg:
          liveRouteLeg == _s ? this.liveRouteLeg : liveRouteLeg as String?,
    );
  }

  @override
  List<Object?> get props => [
        phase,
        pickup,
        pickupAddr,
        dropoff,
        dropoffAddr,
        pickupNote,
        estimate,
        selectedTier,
        trip,
        driver,
        driverLocation,
        driverHeading,
        driverSeenAt,
        driverStale,
        liveEtaSec,
        liveRemainingM,
        unreadMessages,
        driverRoutePolyline,
        fareFinal,
        breakdown,
        receipt,
        tipAmount,
        tipping,
        rating,
        ratingTags,
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
        notice,
        alert,
        liveRoutePolyline,
        liveRouteLeg,
      ];
}
