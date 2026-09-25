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
    this.restPollEvery = const Duration(seconds: 15),
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

  /// While driver pings are stale, how often to pull the trip over REST (and,
  /// from the second round, rebuild the socket). Injectable for tests.
  final Duration restPollEvery;
  Timer? _restPoll;
  String? _lastToken;

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
      'Price updated to ${Fmt.money(amount)} — tap Confirm to accept';

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
    _lastToken = token;
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
      ..add(_realtime.on('trip:matching').listen(_onMatching))
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
      // Live-ride watchdogs: the server sees every GPS fix, so it — not this
      // app — decides when the driver has left the route or stopped moving.
      // Each has a matching "all clear" so a raised banner can come down.
      ..add(_realtime.on('trip:off_route').listen(_onOffRoute))
      ..add(_realtime.on('trip:back_on_route').listen(_onAllClear))
      ..add(_realtime.on('trip:driver_stopped').listen(_onDriverStopped))
      ..add(_realtime.on('trip:driver_moving').listen(_onAllClear))
      ..add(_realtime.on('trip:route_updated').listen(_onRouteUpdated))
      ..add(_realtime.on('trip:stops_updated').listen(_onStopsUpdated))
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
    _lastToken = token;
    // After an OS suspend, socket.io often still reports the socket as
    // `connected` while its transport is actually dead (a "zombie" socket),
    // and anything emitted into it is silently dropped. The rider app has no
    // background execution, unlike the driver, so it misses every event while
    // the screen is off. That is how a rider came back from a locked screen to
    // a frozen "on the way" card after the driver had already completed the
    // ride: `trip:completed` was gone, and a `trip:sync` emitted on the dead
    // socket went nowhere.
    //
    // So on every resume: (1) pull the trip over REST, which needs no socket
    // and applies a completion or cancel that happened while we were away;
    // (2) force a fresh connection rather than trusting `isConnected`. A brief
    // reconnect on resume is cheap; a stuck trip is not.
    await _refreshTripOverRest();
    await _reconnectHard(token);
  }

  Future<void> _reconnectHard(String token) async {
    try {
      _realtime.disconnect();
      await _connectRealtime(token);
      if (isClosed) return;
      emit(state.copyWith(connected: true));
      await _restoreActiveTrip();
      _resync();
    } catch (_) {
      if (!isClosed) emit(state.copyWith(connected: false));
    }
  }

  /// Server truth for the trip we hold, over REST (works with a dead socket).
  Future<void> _refreshTripOverRest() async {
    final id = state.trip?.id;
    if (id == null) return;
    try {
      final fresh = await _repository.getTrip(id);
      if (isClosed) return;
      _applyTrip(fresh);
    } catch (_) {
      // Still offline; the stale watchdog keeps retrying.
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
    } else if (phase == TripPhase.completed &&
        state.phase != TripPhase.completed) {
      // The `trip:completed` event was missed (socket down at the time):
      // show the summary from the trip row and fetch the receipt for the
      // itemised fare/tip.
      _resetTracking();
      emit(state.copyWith(
        phase: TripPhase.completed,
        trip: trip,
        fareFinal: trip.fareFinal ?? state.fareFinal,
      ));
      unawaited(_loadReceipt(trip.id));
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
        // Seed the car's position from the snapshot so a restored screen shows
        // it where it is now. Without this the marker sat at whatever we last
        // saw before the app was suspended — or nowhere at all after a cold
        // start — until the next `trip:driver_location` ping arrived.
        // The snapshot is read from the same Redis fix the live pings come
        // from, so it is never staler than what we hold: prefer it, and keep
        // the current position only when the server had no fix to give.
        driverLocation: driver?.lastLocation ?? state.driverLocation,
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

  /// True while there is a live ride an advisory could be about. A late event
  /// for a finished trip must not pop a dialog over the home screen.
  bool _isRiding() =>
      state.phase == TripPhase.driverEnRoute ||
      state.phase == TripPhase.driverArrived ||
      state.phase == TripPhase.onTrip;

  bool _isThisTrip(Map<String, dynamic> data) {
    final tripId = data['tripId'] as String?;
    final current = state.trip?.id;
    return tripId == null || current == null || tripId == current;
  }

  void _onOffRoute(Map<String, dynamic> data) {
    if (!_isRiding() || !_isThisTrip(data)) return;
    emit(state.copyWith(alert: TripAlert(TripAlertKind.offRoute)));
  }

  void _onDriverStopped(Map<String, dynamic> data) {
    if (!_isRiding() || !_isThisTrip(data)) return;
    emit(state.copyWith(
      alert: TripAlert(
        TripAlertKind.driverStopped,
        stoppedSec: (data['stoppedSec'] as num?)?.round(),
      ),
    ));
  }

  /// The condition that raised an advisory has passed (back on the route, or
  /// moving again): take any banner down.
  void _onAllClear(Map<String, dynamic> data) {
    if (state.alert == null || !_isThisTrip(data)) return;
    emit(state.copyWith(alert: null));
  }

  /// The UI has shown [TripState.alert]; drop it so the same kind of advisory
  /// can be raised again later in the ride.
  void clearAlert() {
    if (state.alert != null) emit(state.copyWith(alert: null));
  }

  /// The server re-routed the current leg from where the driver actually is.
  /// Taking its line means the drawn route and the server's ETA agree, and the
  /// app doesn't pay for a second routing call to work the same thing out.
  /// A stop was added to this ride (here or on another of the rider's
  /// devices): draw the new route and re-read the trip for its stops and
  /// re-priced estimate.
  void _onStopsUpdated(Map<String, dynamic> data) {
    if (!_isThisTrip(data)) return;
    final polyline = data['routePolyline'] as String?;
    if (polyline != null && polyline.isNotEmpty) {
      emit(state.copyWith(liveRoutePolyline: polyline, liveRouteLeg: 'trip'));
    }
    unawaited(_refreshTripOverRest());
  }

  void _onRouteUpdated(Map<String, dynamic> data) {
    if (!_isThisTrip(data)) return;
    final polyline = data['polyline'] as String?;
    if (polyline == null || polyline.isEmpty) return;
    emit(state.copyWith(
      liveRoutePolyline: polyline,
      liveRouteLeg: data['phase'] as String?,
    ));
  }


  /// Forget the live driver position + stale watchdog (trip over / reset).
  void _resetTracking() {
    _staleTimer?.cancel();
    _staleTimer = null;
    _restPoll?.cancel();
    _restPoll = null;
  }

  void _restartStaleWatchdog() {
    _staleTimer?.cancel();
    // A fresh ping means the socket is alive: stop any REST fallback.
    _restPoll?.cancel();
    _restPoll = null;
    _staleTimer = Timer(staleAfter, () {
      if (isClosed || state.driverStale) return;
      emit(state.copyWith(driverStale: true));
      _startRestPoll();
    });
  }

  /// No driver pings for [staleAfter]: the socket may be dead without having
  /// told us. Pull the trip over REST every [restPollEvery] so an arrival,
  /// start or completion still shows, and from the second silent round
  /// rebuild the socket as well.
  void _startRestPoll() {
    _restPoll?.cancel();
    var rounds = 0;
    _restPoll = Timer.periodic(restPollEvery, (t) async {
      if (isClosed || state.trip == null) {
        t.cancel();
        return;
      }
      rounds++;
      await _refreshTripOverRest();
      if (isClosed || state.trip == null || !state.driverStale) {
        t.cancel();
        return;
      }
      final token = _lastToken;
      if (rounds >= 2 && token != null) await _reconnectHard(token);
    });
  }

  void _onMatching(Map<String, dynamic> data) {
    if (state.phase == TripPhase.requesting ||
        state.phase == TripPhase.searching) {
      // How long the server keeps looking: its own deadline, or the window
      // length counted from now (an older server sends neither).
      final endsAt = DateTime.tryParse('${data['searchEndsAt'] ?? ''}');
      final windowSec = data['searchWindowSec'];
      emit(state.copyWith(
        phase: TripPhase.searching,
        searchEndsAt: endsAt?.toLocal() ??
            (windowSec is num
                ? DateTime.now().add(Duration(seconds: windowSec.toInt()))
                : state.searchEndsAt),
      ));
    }
  }

  Future<void> _onAccepted(Map<String, dynamic> data) async {
    final tripId = data['tripId'] as String?;
    final otp = data['startOtp'] as String?;
    var trip = state.trip;
    // A scheduled ride fires while this screen has no trip loaded (or a
    // stale one), and a trip booked earlier may predate its start code:
    // pull the server copy so the card shows pickup, dropoff and the code.
    final needsTrip = tripId != null &&
        (trip == null ||
            trip.id != tripId ||
            (otp != null && trip.startOtp == null));
    if (needsTrip) {
      try {
        trip = await _repository.getTrip(tripId);
      } catch (_) {
        // Keep whatever we have; the socket events still drive the phases.
      }
    }
    if (isClosed) return;
    emit(state.copyWith(
      phase: TripPhase.driverEnRoute,
      trip: trip,
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
    final reported = (data['fareFinal'] as num?)?.toDouble();
    emit(state.copyWith(
      phase: TripPhase.completed,
      // Never let a completion event without a usable fare wipe out one we
      // already hold — that is how a finished ride showed \$0.00.
      fareFinal: (reported != null && reported > 0)
          ? reported
          : (state.fareFinal ?? state.trip?.fareDisplay),
      alert: null,
      breakdown: FareBreakdown.fromJsonOrNull(data['breakdown']),
    ));
    // Pull the full receipt (fare + fee + payout + tip) for the summary sheet.
    final tripId = state.trip?.id;
    if (tripId != null) unawaited(_loadReceipt(tripId));
  }

  /// How many times the receipt is re-fetched before giving up, and how long
  /// to wait between attempts. A rider on a weak signal at the end of a ride
  /// would otherwise be left looking at a summary with no money on it.
  static const int receiptAttempts = 4;
  static const Duration receiptRetryDelay = Duration(seconds: 3);

  Future<void> _loadReceipt(String tripId) async {
    for (var attempt = 0; attempt < receiptAttempts; attempt++) {
      if (isClosed) return;
      try {
        final receipt = await _payments.receipt(tripId);
        if (isClosed) return;
        // Only replace what we have with something that actually says a fare.
        // A capture still settling can answer with zero, and the number from
        // the completion event is better than blanking the sheet.
        if (receipt.fare > 0 || state.fareFinal == null) {
          emit(state.copyWith(receipt: receipt));
        }
        if (receipt.fare > 0) return;
      } catch (_) {
        // Offline or a hiccup — fall through to the retry.
      }
      // Still on this trip's summary? If the rider has moved on, stop.
      if (state.phase != TripPhase.completed || state.trip?.id != tripId) return;
      if (attempt < receiptAttempts - 1) {
        await Future<void>.delayed(receiptRetryDelay);
      }
    }
  }

  /// Tip the driver (added 100% to their payout).
  Future<void> tipDriver(double amount) async {
    if (amount <= 0 || state.tipping) return;
    final tripId = state.trip?.id;
    // No trip to tip against (a completion restored without its trip payload).
    // Returning silently left the rider tapping a button that did nothing and
    // never said why; say it instead.
    if (tripId == null) {
      emit(state.copyWith(
        error: "This ride's details are still loading — try the tip again in "
            'a moment.',
      ));
      return;
    }
    emit(state.copyWith(tipping: true, error: null));
    try {
      await _payments.tip(tripId, amount);
      emit(state.copyWith(tipping: false, tipAmount: amount));
    } on ApiException catch (e) {
      emit(state.copyWith(tipping: false, error: e.message));
    }
  }

  /// Rate the driver (1–5 stars), or change a rating already given.
  ///
  /// The backend upserts one rating per (trip, rater) and recomputes the
  /// driver's average from the rows, so re-rating is a correction rather than
  /// a second vote. Riders mis-tap, and having to live with a one-star slip
  /// is worse for the driver than letting it be fixed.
  Future<void> rateDriver(int stars, {String? comment}) async {
    final tripId = state.trip?.id;
    if (tripId == null || stars < 1 || stars > 5) return;
    final previous = state.rating;
    if (previous == stars) return;
    // Show the new value immediately; put the old one back if it doesn't stick.
    emit(state.copyWith(rating: stars));
    try {
      await _ratings.rate(
        tripId,
        stars: stars,
        comment: comment,
        // Compliments describe a good ride; they make no sense pinned to a
        // rating the rider has just lowered.
        tags: stars >= 4 ? state.ratingTags : const [],
      );
      if (stars < 4 && state.ratingTags.isNotEmpty) {
        emit(state.copyWith(ratingTags: const []));
      }
    } on ApiException catch (e) {
      emit(state.copyWith(rating: previous, error: e.message));
    }
  }

  /// Attach/replace compliment tags on the rating already given for this trip
  /// (the backend updates the existing rating). No-op until a star rating exists.
  Future<void> updateRatingTags(List<String> tags) async {
    final tripId = state.trip?.id;
    final stars = state.rating;
    if (tripId == null || stars == null) return;
    try {
      await _ratings.rate(tripId, stars: stars, tags: tags);
      emit(state.copyWith(ratingTags: tags));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  /// What the ride options say when a request came back with no driver.
  /// The options sheet matches on it to drop that tier's stale pickup ETA.
  static const String noDriversNearby =
      'No drivers available nearby right now — try again.';

  void _onNoDrivers() {
    // Drop back to the ride options (destination + tier retained) with a clear
    // message, so the rider can just re-tap Confirm instead of being stuck on
    // "finding driver" or bounced to a dead-end error screen.
    if (state.estimate != null) {
      emit(state.copyWith(
        phase: TripPhase.choosingRide,
        error: noDriversNearby,
      ));
    } else {
      emit(state.copyWith(
        phase: TripPhase.error,
        error: 'No drivers available right now. Please try again.',
      ));
    }
  }

  void _setPhase(TripPhase phase) => emit(state.copyWith(phase: phase));

  /// The offer picked on the Offers page, held outside the per-ride state so
  /// the resets between rides (`const TripState()`) don't drop it.
  AvailablePromo? _offer;

  @override
  void emit(TripState state) => super.emit(
        state.offerPromo == _offer ? state : state.copyWith(offerPromo: _offer),
      );

  /// "Apply to next ride" from the Offers page / a Home offer banner. When
  /// the ride sheet is already open, the code is applied right away.
  Future<void> selectOffer(AvailablePromo offer) async {
    _offer = offer;
    emit(state.copyWith(offerPromo: offer));
    if (state.phase == TripPhase.choosingRide) await applyPromo(offer.code);
  }

  /// Drops the picked offer (and its applied quote, if it is the one applied).
  void clearOffer() {
    final code = _offer?.code;
    _offer = null;
    emit(state.copyWith(
      offerPromo: null,
      appliedPromo: state.appliedPromo?.code == code ? null : state.appliedPromo,
      promoError: state.appliedPromo?.code == code ? null : state.promoError,
    ));
  }

  /// Applies the picked offer to a fresh ride sheet, if there is one.
  Future<void> _applyOffer() async {
    final offer = _offer;
    if (offer == null || state.phase != TripPhase.choosingRide) return;
    await applyPromo(offer.code);
  }

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
        selectedTier: FareTier.defaultTier(estimate.tiers),
        appliedPromo: null,
        promoError: null,
        stops: const [],
      ));
      unawaited(loadPaymentMethods());
      await _applyOffer();
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

  /// Picks a tier; an applied promo is re-priced against the new fare so the
  /// discount on the sheet and Confirm stays true.
  Future<void> selectTier(String tier) async {
    emit(state.copyWith(selectedTier: tier));
    final applied = state.appliedPromo;
    if (applied != null) await applyPromo(applied.code);
  }

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
        selectedTier: FareTier.defaultTier(estimate.tiers),
        appliedPromo: null,
        promoError: null,
      ));
      await _applyOffer();
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

  /// Removes the applied code; if it came from a picked offer, that offer is
  /// dropped too (the rider said no to it).
  void removePromo() {
    if (_offer != null && _offer?.code == state.appliedPromo?.code) {
      clearOffer();
      return;
    }
    emit(state.copyWith(appliedPromo: null, promoError: null));
  }

  void setPaymentMode(String mode) => emit(state.copyWith(
        paymentMode: mode,
        // Cash clears any chosen card.
        selectedMethodId: mode == 'cash' ? null : state.selectedMethodId,
      ));

  /// Set (or clear, with null) the future time to schedule the ride for.
  void setScheduledAt(DateTime? when) =>
      emit(state.copyWith(scheduledAt: when));

  /// Set (or clear) the rider's pickup note for the driver.
  void setPickupNote(String? note) {
    final trimmed = note?.trim();
    emit(state.copyWith(
        pickupNote: (trimmed == null || trimmed.isEmpty) ? null : trimmed));
  }

  /// Set (or clear) the person this ride is being booked for. Null means the
  /// ordinary case: the rider is the passenger.
  void setPassenger(TripPassenger? passenger) =>
      emit(state.copyWith(passenger: passenger));

  Future<void> confirmRide() async {
    final s = state;
    if (s.pickup == null || s.dropoff == null || s.selectedTier == null) return;
    emit(state.copyWith(
      phase: TripPhase.requesting,
      error: null,
      searchEndsAt: null, // a new search gets its own window
    ));
    try {
      final trip = await _repository.createTrip(
        pickup: s.pickup!,
        dropoff: s.dropoff!,
        tier: s.selectedTier!,
        pickupAddr: s.pickupAddr,
        dropoffAddr: s.dropoffAddr,
        pickupNote: s.pickupNote,
        passenger: s.passenger,
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
      // The picked offer has been spent on this ride.
      if (s.appliedPromo != null && s.appliedPromo?.code == _offer?.code) {
        _offer = null;
      }
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
      // Keep "Details" honest across a re-price: the server sends the fresh
      // itemisation with the 409, so the lines still sum to the new fare.
      breakdown: FareBreakdown.fromJsonOrNull(
        est is Map ? est['breakdown'] : null,
      ),
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

  /// Max stops on a ride (mirrors the backend's MAX_STOPS).
  static const int maxRideStops = 3;

  /// Whether a stop can be added to the ride in [s] (pure, so widgets and
  /// tests can ask without a live cubit).
  static bool canAddStopTo(TripState s) =>
      s.trip != null &&
      s.trip!.stops.length < maxRideStops &&
      (s.phase == TripPhase.driverEnRoute ||
          s.phase == TripPhase.driverArrived ||
          s.phase == TripPhase.onTrip);

  /// What adding [stop] to the ride under way would cost.
  Future<StopQuote> quoteRideStop(TripStop stop) =>
      _repository.quoteStop(state.trip!.id, stop);

  /// Add [stop] at the fare the rider confirmed. Throws [ApiException] (409
  /// PRICE_CHANGED when the price has since moved).
  Future<void> addRideStop(TripStop stop, double quotedFare) async {
    final id = state.trip!.id;
    await _repository.addStop(id, stop, quotedFare: quotedFare);
    await _refreshTripOverRest();
  }

  /// Tell the driver waiting at the pickup that the rider is coming out.
  /// Returns false (and leaves the button available) when it failed.
  Future<bool> imOnMyWay() async {
    final trip = state.trip;
    if (trip == null) return false;
    try {
      await _repository.onMyWay(trip.id);
      emit(state.copyWith(riderComingSent: true));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// [reason] is the rider's chosen cancellation reason (for ops/analytics);
  /// defaults to a generic label when none was given.
  /// "End trip here" mid-ride. Returns true once the server has completed
  /// the trip (the completed sheet follows via [_onCompleted]); false with
  /// [TripState.error] set when it could not.
  Future<bool> endTripEarly({String? reason}) async {
    final trip = state.trip;
    if (trip == null || state.phase != TripPhase.onTrip) return false;
    emit(state.copyWith(error: null));
    try {
      final receipt =
          await _repository.endTripEarly(trip.id, reason: reason);
      // The socket's `trip:completed` may already have moved us on.
      if (!isClosed && state.phase == TripPhase.onTrip) _onCompleted(receipt);
      return true;
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
      return false;
    } catch (_) {
      emit(state.copyWith(
          error: 'Could not end the trip. Check your connection and try again.'));
      return false;
    }
  }

  Future<double> cancelTrip({String? reason}) async {
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
        fee = await _repository.cancelTrip(
          trip.id,
          reason: (reason == null || reason.isEmpty)
              ? 'Cancelled by rider'
              : reason,
        );
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
    selectedTip = null;
    emit(const TripState());
  }

  /// The tip the rider has tapped on the completed sheet, not yet sent. A tap
  /// selects it, a second tap clears it; it is charged when they tap Done
  /// (owner: no separate "Add tip" confirm step).
  double? selectedTip;

  /// Done on the completed sheet: send the selected tip (if any and not sent
  /// yet), then close the ride. A failed tip keeps the sheet open with the
  /// error so the rider can retry or clear the tip.
  Future<void> finishRide() async {
    final tip = selectedTip;
    final alreadyTipped = (state.tipAmount ?? 0) > 0;
    if (tip != null && tip > 0 && !alreadyTipped) {
      await tipDriver(tip);
      if (state.error != null) return;
    }
    reset();
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
