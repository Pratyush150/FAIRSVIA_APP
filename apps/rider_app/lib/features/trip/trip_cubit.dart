import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:design_system/design_system.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_models/shared_models.dart';

part 'trip_state.dart';

/// Drives the rider flow: destination → estimate → tier → create → searching,
/// then live tracking (matched → en route → arrived → on trip → completed) via
/// the socket. Cancelling resets to idle.
class TripCubit extends Cubit<TripState> {
  TripCubit(
    this._repository,
    this._realtime,
    this._payments,
    this._ratings, {
    this.staleAfter = const Duration(seconds: 20),
  }) : super(const TripState());

  final TripRepository _repository;
  final RealtimeClient _realtime;
  final PaymentsRemoteDataSource _payments;
  final RatingsRemoteDataSource _ratings;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// How long without a driver ping before the car on the map is flagged
  /// stale ([TripState.driverStale]). Injectable so tests don't wait 20 s.
  final Duration staleAfter;
  Timer? _staleTimer;

  static const String cancelFailedMessage =
      "Couldn't cancel the ride — check your connection and try again";
  static const String driverCancelledMessage = 'Your driver cancelled the trip';
  static const String otpLockedMessage =
      'Too many wrong start codes — ask your driver to retry in 15 min';

  /// Backend error code on POST /trips when the fare/surge moved past the
  /// quote the rider confirmed (409).
  static const String priceChangedCode = 'PRICE_CHANGED';

  /// The re-confirm prompt after a price change; [amount] is the new fare.
  static String priceChangedMessage(double amount) =>
      'Price updated to \$${amount.toStringAsFixed(2)} — tap Confirm to accept';

  /// Subscribe to trip lifecycle events, then connect the socket.
  AccessTokenProvider? _tokenProvider;

  Future<void> _connectRealtime(String token) {
    final provider = _tokenProvider;
    return provider != null
        ? _realtime.connectWith(provider)
        : _realtime.connect(token);
  }

  /// Connects the socket. With [tokenProvider] the handshake fetches a fresh
  /// access token on every (re)connect; without it the given [token] is used.
  Future<void> init(String token, {AccessTokenProvider? tokenProvider}) async {
    _tokenProvider = tokenProvider;
    _myId = AuthInterceptor.jwtSubject(token);
    // Subscribe BEFORE connecting. The realtime streams are broadcast
    // controllers that outlive any one socket and are re-bound to each new
    // one, so registering first means a failed/slow first connect (connect
    // error or timeout) can't leave the session deaf for good — which it did
    // when connect() was awaited first and threw past the subscriptions.
    // resumeFromBackground() therefore only needs to reconnect.
    _subscribe();
    try {
      await _connectRealtime(token);
    } catch (_) {
      // Show the banner; socket.io keeps retrying with backoff and the
      // `connection` stream flips us back to true when it lands.
      emit(state.copyWith(connected: false));
    }
    // If the app was killed and reopened mid-ride, restore the live-tracking
    // screen instead of dropping the rider on the idle "Where to?" home while
    // a driver is actually on the way. REST, so it works even while the
    // socket is still down.
    await _restoreActiveTrip();
  }

  void _subscribe() {
    if (_subs.isNotEmpty) return; // init() is one-shot per cubit
    _subs
      ..add(_realtime.on('trip:matching').listen((_) => _onMatching()))
      ..add(_realtime.on('trip:accepted').listen(_onAccepted))
      ..add(_realtime.on('trip:driver_location').listen(_onDriverLocation))
      ..add(_realtime.on('trip:message').listen(_onMessage))
      ..add(_realtime.on('trip:arrived').listen((_) => _setPhase(TripPhase.driverArrived)))
      ..add(_realtime.on('trip:started').listen((_) => emit(state.copyWith(
            phase: TripPhase.onTrip,
            liveEtaSec: null,
            liveRemainingM: null,
          ))))
      ..add(_realtime.on('trip:completed').listen(_onCompleted))
      ..add(_realtime.on('trip:no_drivers').listen((_) => _onNoDrivers()))
      // Server-side endings/warnings the rider must not be deaf to: the
      // driver cancelling, the start code getting locked after too many
      // wrong attempts, and payment holds/captures failing.
      ..add(_realtime.on('trip:cancelled').listen(_onCancelled))
      ..add(_realtime.on('trip:otp_locked').listen(_onOtpLocked))
      ..add(_realtime.on('trip:payment_warning').listen(_onPaymentWarning))
      // Reconnection resilience: the server replies to `trip:sync` with the
      // authoritative trip so we can rehydrate after a dropped socket.
      ..add(_realtime.on('trip:sync').listen(_onSync))
      ..add(_realtime.reconnects.listen((_) => _resync()))
      // Surface socket up/down edges so the UI can show a reconnecting banner.
      ..add(_realtime.connection.listen((up) {
        if (up != state.connected) emit(state.copyWith(connected: up));
      }));
  }

  /// Pull the server-authoritative in-flight trip (if any) on a cold start.
  Future<void> _restoreActiveTrip() async {
    try {
      final active = await _repository.activeTripDetails();
      if (active == null) return;
      _applyTrip(
        active.trip,
        driver: active.driver,
        driverPolyline: active.driverPolyline,
      );
    } catch (_) {
      // Best effort — socket events will correct the screen if this fails.
    }
  }

  /// Re-establish the socket after the OS suspended the app. iOS tears the
  /// WebSocket down while backgrounded and socket.io's own retry can stay
  /// wedged, leaving "Reconnecting…" up forever — so reconnect explicitly and
  /// re-sync whatever trip is live.
  Future<void> resumeFromBackground(String token) async {
    // Don't trust `isConnected` alone: after a suspend the socket.io client can
    // still report `connected` while its transport is dead. Only skip the
    // reconnect when the live connection stream also says we're up.
    if (_realtime.isConnected && state.connected) {
      _resync();
      return;
    }
    try {
      await _connectRealtime(token);
      emit(state.copyWith(connected: true));
      await _restoreActiveTrip();
      _resync();
    } catch (_) {
      emit(state.copyWith(connected: false));
    }
  }

  /// After a reconnect, ask the server for the current trip state.
  void _resync() {
    final tripId = state.trip?.id;
    if (tripId != null) {
      _realtime.emit('trip:sync', {'tripId': tripId});
    }
  }

  /// Rehydrate the UI phase from the server-authoritative trip snapshot.
  void _onSync(Map<String, dynamic> data) {
    final Trip trip;
    try {
      trip = Trip.fromJson(data);
    } catch (_) {
      return;
    }
    // A sync reply may carry the driver keys too (same shape as the REST
    // active-trip snapshot); use them when present.
    final hasDriver = data['driver'] is Map;
    _applyTrip(
      trip,
      driver: hasDriver ? AssignedDriver.fromAcceptedEvent(data) : null,
      driverPolyline: data['driverPolyline'] as String?,
    );
  }

  /// Move the UI to the phase implied by [trip]'s server-side status. When
  /// the snapshot includes the assigned [driver] / [driverPolyline] (mirroring
  /// the `trip:accepted` payload) they are restored too, so the matched sheet
  /// shows the real driver after a relaunch; otherwise whatever we already
  /// hold is kept.
  void _applyTrip(Trip trip, {AssignedDriver? driver, String? driverPolyline}) {
    final phase = switch (trip.status) {
      TripStatus.requested || TripStatus.matching => TripPhase.searching,
      TripStatus.accepted => TripPhase.driverEnRoute,
      TripStatus.arrived => TripPhase.driverArrived,
      TripStatus.inProgress => TripPhase.onTrip,
      TripStatus.completed || TripStatus.paymentFailed => TripPhase.completed,
      TripStatus.cancelled ||
      TripStatus.noDrivers ||
      TripStatus.expired =>
        TripPhase.idle,
      _ => state.phase,
    };
    if (phase == TripPhase.idle) {
      _resetTracking();
      emit(const TripState());
    } else {
      // Rehydrate everything the map + sheets draw from the trip itself, not
      // just the phase: after a kill+reopen mid-ride there is no `estimate`,
      // so without these there were no pickup/dropoff markers, no route fit
      // and an empty address on the on-trip sheet. The assigned driver and
      // approach polyline aren't part of the Trip model; they come from the
      // snapshot's extra keys when the server sends them, else stay as-is
      // (the UI shows "—"/no approach leg until the next socket event).
      final polyline = (driverPolyline == null || driverPolyline.isEmpty)
          ? state.driverRoutePolyline
          : driverPolyline;
      emit(state.copyWith(
        phase: phase,
        trip: trip,
        pickup: trip.pickup.point,
        pickupAddr: trip.pickup.address ?? state.pickupAddr,
        dropoff: trip.dropoff.point,
        dropoffAddr: trip.dropoff.address ?? state.dropoffAddr,
        stops: trip.stops,
        driver: driver ?? state.driver,
        driverRoutePolyline: polyline,
      ));
    }
  }

  /// The driver cancelled (or the trip was ended server-side): back to Home
  /// with the reason surfaced, so the rider can request again rather than
  /// staring at a driver who is never coming.
  void _onCancelled(Map<String, dynamic> data) {
    final tripId = data['tripId'] as String?;
    final current = state.trip?.id;
    // Late event for a trip we've already moved on from.
    if (tripId != null && current != null && tripId != current) return;
    if (state.phase == TripPhase.idle) return;
    final by = data['by'] as String?;
    final reason = (data['reason'] as String?)?.trim();
    final headline =
        by == 'rider' ? 'Your ride was cancelled' : driverCancelledMessage;
    _resetTracking();
    emit(TripState(
      connected: state.connected,
      error: (reason == null || reason.isEmpty) ? headline : '$headline — $reason',
    ));
  }

  void _onOtpLocked(Map<String, dynamic> data) {
    if (!isCancellable(state.phase)) return;
    emit(state.copyWith(error: otpLockedMessage));
  }

  void _onPaymentWarning(Map<String, dynamic> data) {
    final message = (data['message'] as String?)?.trim();
    emit(state.copyWith(
      notice: (message == null || message.isEmpty)
          ? 'Payment could not be processed'
          : message,
    ));
  }

  /// The UI has shown [TripState.notice]; drop it so the same message can
  /// fire again later.
  void clearNotice() {
    if (state.notice != null) emit(state.copyWith(notice: null));
  }

  /// Forget the live driver position + stale watchdog (trip over / reset).
  void _resetTracking() {
    _staleTimer?.cancel();
    _staleTimer = null;
  }

  void _restartStaleWatchdog() {
    _staleTimer?.cancel();
    _staleTimer = Timer(staleAfter, () {
      if (isClosed || state.driverStale) return;
      emit(state.copyWith(driverStale: true));
    });
  }

  void _onMatching() {
    if (state.phase == TripPhase.requesting ||
        state.phase == TripPhase.searching) {
      emit(state.copyWith(phase: TripPhase.searching));
    }
  }

  void _onAccepted(Map<String, dynamic> data) {
    emit(state.copyWith(
      phase: TripPhase.driverEnRoute,
      driver: AssignedDriver.fromAcceptedEvent(data),
      // Route the driver takes to reach the pickup — drawn during the approach.
      driverRoutePolyline: data['driverPolyline'] as String?,
    ));
  }

  String? _myId;
  bool _chatOpen = false;

  /// Count driver messages that arrive while the chat page is closed, for the
  /// badge on the Message button; our own echoes are ignored.
  void _onMessage(Map<String, dynamic> data) {
    if (_chatOpen) return;
    final from = data['from'] as String?;
    if (from == null || from == _myId) return;
    if (data['tripId'] != null && data['tripId'] != state.trip?.id) return;
    emit(state.copyWith(unreadMessages: state.unreadMessages + 1));
  }

  /// The chat page is open (or just closed): clear the badge / stop counting.
  void setChatOpen(bool open) {
    _chatOpen = open;
    if (open && state.unreadMessages != 0) {
      emit(state.copyWith(unreadMessages: 0));
    }
  }

  void _onDriverLocation(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    final here = GeoPoint(lat, lng);
    // The server now routes the ETA itself (`etaSec`/`remainingM`, with
    // `etaSource` route|straight); prefer it and fall back to our own
    // along-the-polyline estimate when a ping (older backend, no nav leg)
    // omits either number.
    final serverEta = (data['etaSec'] as num?)?.round();
    final serverRemaining = (data['remainingM'] as num?)?.round();
    final live = (serverEta != null && serverRemaining != null)
        ? (etaSec: serverEta, remainingM: serverRemaining)
        : _liveProgress(here);
    final heading = (data['heading'] as num?)?.toDouble();
    _restartStaleWatchdog();
    emit(state.copyWith(
      driverLocation: here,
      // Keep the last known heading when a ping omits it (stationary fix).
      driverHeading: heading ?? state.driverHeading,
      driverSeenAt: DateTime.now(),
      driverStale: false,
      liveEtaSec: live?.etaSec,
      liveRemainingM: live?.remainingM,
    ));
  }

  @visibleForTesting
  void debugDriverLocation(Map<String, dynamic> data) => _onDriverLocation(data);

  /// Remaining distance + ETA along the leg the driver is currently driving
  /// (approach polyline while en route, trip route once started), so the
  /// rider's "Arriving in N min" counts down with the car instead of
  /// freezing at the match-time estimate. Speed is the leg's routed
  /// average (distance / duration), falling back to ~8 m/s city driving.
  ({int etaSec, int remainingM})? _liveProgress(GeoPoint here) {
    String? encoded;
    double? metres;
    double? seconds;
    switch (state.phase) {
      case TripPhase.driverEnRoute:
      case TripPhase.driverArrived:
        encoded = state.driverRoutePolyline;
        metres = state.driver?.etaDistanceM?.toDouble();
        seconds = state.driver?.etaSec?.toDouble();
      case TripPhase.onTrip:
        encoded = state.estimate?.polyline ?? state.trip?.routePolyline;
        metres = state.estimate?.distanceM.toDouble() ??
            state.trip?.distanceM?.toDouble();
        seconds = state.estimate?.durationS.toDouble() ??
            state.trip?.durationS?.toDouble();
      default:
        return null;
    }
    if (encoded == null || encoded.isEmpty) return null;
    final route = decodePolyline(encoded);
    if (route.length < 2) return null;
    final remaining = routeRemainingMeters(route, LatLng(here.lat, here.lng));
    final speed = (metres != null && seconds != null && seconds > 0)
        ? (metres / seconds).clamp(2.0, 30.0)
        : 8.0;
    return (etaSec: (remaining / speed).round(), remainingM: remaining.round());
  }

  void _onCompleted(Map<String, dynamic> data) {
    _resetTracking();
    emit(state.copyWith(
      phase: TripPhase.completed,
      fareFinal: (data['fareFinal'] as num?)?.toDouble(),
      breakdown: FareBreakdown.fromJsonOrNull(data['breakdown']),
    ));
    // Pull the full receipt (fare + fee + payout + tip) for the summary sheet.
    final tripId = state.trip?.id;
    if (tripId != null) unawaited(_loadReceipt(tripId));
  }

  Future<void> _loadReceipt(String tripId) async {
    try {
      final receipt = await _payments.receipt(tripId);
      emit(state.copyWith(receipt: receipt));
    } catch (_) {
      // The fare from the socket event is enough to show a summary.
    }
  }

  /// Tip the driver (added 100% to their payout).
  Future<void> tipDriver(double amount) async {
    final tripId = state.trip?.id;
    if (tripId == null || amount <= 0 || state.tipping) return;
    emit(state.copyWith(tipping: true, error: null));
    try {
      await _payments.tip(tripId, amount);
      emit(state.copyWith(tipping: false, tipAmount: amount));
    } on ApiException catch (e) {
      emit(state.copyWith(tipping: false, error: e.message));
    }
  }

  /// Rate the driver (1–5 stars). One rating per trip.
  Future<void> rateDriver(int stars, {String? comment}) async {
    final tripId = state.trip?.id;
    if (tripId == null || state.rating != null) return;
    try {
      await _ratings.rate(tripId, stars: stars, comment: comment);
      emit(state.copyWith(rating: stars));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  void _onNoDrivers() {
    // Drop back to the ride options (destination + tier retained) with a clear
    // message, so the rider can just re-tap Confirm instead of being stuck on
    // "finding driver" or bounced to a dead-end error screen.
    if (state.estimate != null) {
      emit(state.copyWith(
        phase: TripPhase.choosingRide,
        error: 'No drivers available nearby right now — try again.',
      ));
    } else {
      emit(state.copyWith(
        phase: TripPhase.error,
        error: 'No drivers available right now. Please try again.',
      ));
    }
  }

  void _setPhase(TripPhase phase) => emit(state.copyWith(phase: phase));

  Future<void> chooseDestination({
    required GeoPoint pickup,
    String? pickupAddr,
    required GeoPoint dropoff,
    String? dropoffAddr,
  }) async {
    emit(state.copyWith(
      phase: TripPhase.loadingEstimate,
      pickup: pickup,
      pickupAddr: pickupAddr,
      dropoff: dropoff,
      dropoffAddr: dropoffAddr,
      error: null,
    ));
    try {
      final estimate = await _repository.estimate(pickup, dropoff);
      emit(state.copyWith(
        phase: TripPhase.choosingRide,
        estimate: estimate,
        selectedTier: estimate.tiers.isNotEmpty ? estimate.tiers.first.tier : null,
        appliedPromo: null,
        promoError: null,
        stops: const [],
      ));
      unawaited(loadPaymentMethods());
    } on ApiException catch (e) {
      emit(state.copyWith(phase: TripPhase.error, error: e.message));
    }
  }

  /// Fetch the rider's saved cards for the checkout payment picker (best-effort).
  Future<void> loadPaymentMethods() async {
    try {
      final methods = await _payments.methods();
      // "Card" can't be the selection when there is no card on file.
      final mode = methods.isEmpty && state.paymentMode == 'card'
          ? 'cash'
          : state.paymentMode;
      emit(state.copyWith(paymentMethods: methods, paymentMode: mode));
    } catch (_) {
      // non-fatal — the picker just falls back to Card/Cash.
    }
  }

  /// Choose a specific saved card (mode 'card') for the ride.
  void selectPaymentCard(String methodId) => emit(
        state.copyWith(paymentMode: 'card', selectedMethodId: methodId),
      );

  void selectTier(String tier) => emit(state.copyWith(selectedTier: tier));

  /// Max intermediate stops (mirrors the backend cap).
  static const int maxStops = 3;

  /// Add an intermediate stop and re-estimate the (now longer) route. A promo
  /// is cleared since the fare changes.
  Future<void> addStop(TripStop stop) async {
    final s = state;
    if (s.pickup == null || s.dropoff == null || s.stops.length >= maxStops) {
      return;
    }
    final stops = [...s.stops, stop];
    await _reestimateWithStops(stops);
  }

  Future<void> removeStop(int index) async {
    final s = state;
    if (index < 0 || index >= s.stops.length) return;
    final stops = [...s.stops]..removeAt(index);
    await _reestimateWithStops(stops);
  }

  Future<void> _reestimateWithStops(List<TripStop> stops) async {
    final s = state;
    if (s.pickup == null || s.dropoff == null) return;
    emit(state.copyWith(phase: TripPhase.loadingEstimate, stops: stops));
    try {
      final estimate =
          await _repository.estimate(s.pickup!, s.dropoff!, stops: stops);
      emit(state.copyWith(
        phase: TripPhase.choosingRide,
        estimate: estimate,
        selectedTier:
            estimate.tiers.isNotEmpty ? estimate.tiers.first.tier : null,
        appliedPromo: null,
        promoError: null,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(phase: TripPhase.choosingRide, error: e.message));
    }
  }

  /// Validates and applies a promo code against the selected tier's fare.
  /// On rejection, keeps the flow on the ride sheet and surfaces the reason.
  Future<void> applyPromo(String code) async {
    final trimmed = code.trim();
    final fare = state.selectedFare?.fare;
    if (trimmed.isEmpty || fare == null) return;
    emit(state.copyWith(applyingPromo: true, promoError: null));
    try {
      final quote = await _repository.quotePromo(trimmed, fare);
      emit(state.copyWith(
        applyingPromo: false,
        appliedPromo: quote,
        promoError: null,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(
        applyingPromo: false,
        appliedPromo: null,
        promoError: e.message,
      ));
    }
  }

  void removePromo() =>
      emit(state.copyWith(appliedPromo: null, promoError: null));

  void setPaymentMode(String mode) => emit(state.copyWith(
        paymentMode: mode,
        // Cash clears any chosen card.
        selectedMethodId: mode == 'cash' ? null : state.selectedMethodId,
      ));

  /// Set (or clear, with null) the future time to schedule the ride for.
  void setScheduledAt(DateTime? when) =>
      emit(state.copyWith(scheduledAt: when));

  Future<void> confirmRide() async {
    final s = state;
    if (s.pickup == null || s.dropoff == null || s.selectedTier == null) return;
    emit(state.copyWith(phase: TripPhase.requesting, error: null));
    try {
      final trip = await _repository.createTrip(
        pickup: s.pickup!,
        dropoff: s.dropoff!,
        tier: s.selectedTier!,
        pickupAddr: s.pickupAddr,
        dropoffAddr: s.dropoffAddr,
        promoCode: s.appliedPromo?.code,
        paymentMode: s.paymentMode,
        paymentMethodId: s.paymentMode == 'card' ? s.selectedMethodId : null,
        // The picker clamps to now+6 min, but the rider may sit on the sheet
        // before confirming; re-clamp at send time so the backend's 5-minute
        // lead rule can't reject a ride the UI already accepted.
        scheduledAt: _sendableSchedule(s.scheduledAt),
        stops: s.stops,
        // Price lock: the (gross, pre-promo) fare and surge the rider saw on
        // the sheet. The server refuses with 409 PRICE_CHANGED if they moved.
        quotedFare: s.selectedFare?.fare,
        quotedSurge: s.estimate?.surge,
      );
      // A scheduled ride isn't dispatched now — confirm it and return to idle
      // (it will surface again from the scheduled-rides list at its time).
      if (trip.status == TripStatus.scheduled) {
        emit(state.copyWith(phase: TripPhase.scheduled, trip: trip));
        return;
      }
      emit(state.copyWith(phase: TripPhase.searching, trip: trip));
    } on ApiException catch (e) {
      if (e.code == priceChangedCode && _applyPriceChange(e, s.selectedTier!)) {
        return;
      }
      emit(state.copyWith(phase: TripPhase.choosingRide, error: e.message));
    }
  }

  /// The price moved between the sheet and Confirm: keep the rider on the
  /// ride options with the selected tier re-priced to the server's numbers
  /// and ask them to confirm again (Uber-style). Returns false when the 409
  /// body carries no usable fare, so the caller shows the plain message.
  bool _applyPriceChange(ApiException e, String tier) {
    final body = e.body;
    final estimate = state.estimate;
    if (body == null || estimate == null) return false;
    final est = body['estimate'];
    final fare = ((est is Map ? est['fare'] : null) ?? body['fare']) as num?;
    final surge = ((est is Map ? est['surge'] : null) ?? body['surge']) as num?;
    if (fare == null) return false;
    final repriced = estimate.repriced(
      tier: tier,
      fare: fare.toDouble(),
      surge: surge?.toDouble(),
    );
    // An applied promo stays: its code is re-sent on the next Confirm and
    // the server re-prices the discount against the new fare.
    emit(state.copyWith(
      phase: TripPhase.choosingRide,
      estimate: repriced,
      error: priceChangedMessage(fare.toDouble()),
    ));
    return true;
  }

  /// Cancels the active trip and returns the cancellation fee charged (0 when
  /// none), so the UI can tell the rider they were charged.
  /// Phases in which the rider has a live request/assignment to cancel.
  static bool isCancellable(TripPhase phase) => switch (phase) {
        TripPhase.requesting ||
        TripPhase.searching ||
        TripPhase.driverEnRoute ||
        TripPhase.driverArrived =>
          true,
        _ => false,
      };

  static DateTime? _sendableSchedule(DateTime? when) {
    if (when == null) return null;
    final floor = DateTime.now().add(const Duration(minutes: 6));
    return when.isBefore(floor) ? floor : when;
  }

  Future<double> cancelTrip() async {
    // The trip may have ended while the confirm dialog was open (e.g. the
    // no-drivers timeout bounced us back to the ride options). There is
    // nothing to cancel then — keep the chosen destination and tiers instead
    // of wiping the whole flow back to Home.
    if (!isCancellable(state.phase)) return 0;
    final trip = state.trip;
    var fee = 0.0;
    if (trip != null) {
      emit(state.copyWith(error: null));
      try {
        fee = await _repository.cancelTrip(trip.id, reason: 'Cancelled by rider');
      } catch (_) {
        // The server still has a live trip (and a driver on the way) — going
        // idle here would hide a ride that is very much still happening. Keep
        // the sheet, say why, and let the rider tap Cancel again.
        emit(state.copyWith(error: cancelFailedMessage));
        return 0;
      }
    }
    _resetTracking();
    emit(const TripState());
    return fee;
  }

  void reset() {
    _resetTracking();
    emit(const TripState());
  }

  @override
  Future<void> close() {
    _resetTracking();
    for (final s in _subs) {
      s.cancel();
    }
    // The home page only unmounts on sign-out (or app teardown); drop the
    // socket so the server doesn't keep treating this identity as present,
    // and so the next sign-in connects with the new user's token.
    _realtime.disconnect();
    return super.close();
  }
}
