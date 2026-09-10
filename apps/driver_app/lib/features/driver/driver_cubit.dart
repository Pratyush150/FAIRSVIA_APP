import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_models/shared_models.dart';

import 'location_stream.dart';

part 'driver_state.dart';

/// Drives the driver experience: connect → go online → receive/accept offers →
/// drive lifecycle. Location capture lives in the UI (geolocator) and is fed in
/// via [sendLocation] so this cubit stays testable.
class DriverCubit extends Cubit<DriverState> {
  DriverCubit(
    this._realtime,
    this._remote,
    this._ratings, {
    LocationAccessCheck? checkLocation,
    Duration acceptGrace = const Duration(seconds: 5),
  })  : _checkLocation = checkLocation ?? checkLocationAccess,
        _acceptGrace = acceptGrace, // ignore: prefer_initializing_formals
        super(const DriverState());

  final RealtimeClient _realtime;
  final DriverRemoteDataSource _remote;
  final RatingsRemoteDataSource _ratings;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Pre-online location gate (see [goOnline]); injectable for tests.
  final LocationAccessCheck _checkLocation;

  /// How long past the offer window we wait for `trip:assigned` after the
  /// driver tapped Accept before giving up on that offer (see [acceptOffer]).
  final Duration _acceptGrace;
  Timer? _acceptTimer;

  Future<void> init(String token) async {
    // Register every listener BEFORE connecting: a slow/failed first connect
    // used to throw out of here with nothing subscribed, leaving a session that
    // later reconnected fine at the socket level but never heard an offer,
    // assignment, cancellation or up/down edge.
    _subs
      ..add(_realtime.on('trip:offer').listen(
          (d) => _onOffer(RideOffer.fromJson(d))))
      ..add(_realtime.on('trip:offer_expired').listen(
          (d) => _onOfferExpired(tripId: d['tripId'] as String?)))
      ..add(_realtime.on('trip:assigned').listen((d) => _onAssigned(
            d['tripId'] as String,
            // Route from the driver's car to the pickup, so the map can show
            // exactly where they're collecting the rider from.
            approachPolyline: d['driverPolyline'] as String?,
          )))
      ..add(_realtime.on('trip:cancelled').listen((_) => _onCancelledByRider()))
      // Reconnection resilience: re-announce presence and re-fetch the active
      // trip after a dropped socket so the driver's screen stays truthful.
      ..add(_realtime.reconnects.listen((_) => _onReconnect()))
      // Surface socket up/down edges so the UI can show a reconnecting banner.
      ..add(_realtime.connection.listen((up) {
        if (up != state.connected) emit(state.copyWith(connected: up));
      }));
    await _realtime.connect(token);
    // If this app was killed and reopened mid-trip, restore the live trip
    // screen instead of showing the idle "go online" home.
    await _restoreActiveTrip();
  }

  /// Maps a server trip status to the driver's in-trip phase (null = not a
  /// driver-actionable phase, e.g. a rider-side requested/matching trip).
  static DriverPhase? _phaseForStatus(TripStatus status) {
    switch (status) {
      case TripStatus.accepted:
        return DriverPhase.enRoute;
      case TripStatus.arrived:
        return DriverPhase.arrived;
      case TripStatus.inProgress:
        return DriverPhase.onTrip;
      default:
        return null;
    }
  }

  Future<void> _restoreActiveTrip() async {
    try {
      final trip = await _remote.getActiveTrip();
      if (trip == null) return;
      final phase = _phaseForStatus(trip.status);
      if (phase == null) return;
      // We have a live assigned trip → we're effectively online; re-announce
      // presence and restore the trip screen at the right phase.
      _realtime.emit('driver:status', {'status': 'online'});
      emit(state.copyWith(phase: phase, trip: trip));
    } catch (_) {
      // Best effort — offers/events will correct the screen if this fails.
    }
  }

  /// Re-establish the socket after the OS suspended the app. iOS tears the
  /// WebSocket down while backgrounded and socket.io's own retry can stay
  /// wedged — leaving a driver who looks "Online" but receives no offers.
  Future<void> resumeFromBackground(String token) async {
    // Don't trust `isConnected` alone: after a suspend the socket.io client can
    // still report `connected` while its transport is dead. Only skip the
    // reconnect when the live connection stream also says we're up.
    if (_realtime.isConnected && state.connected) {
      await _onReconnect();
      return;
    }
    try {
      await _realtime.connect(token);
      emit(state.copyWith(connected: true));
      await _restoreActiveTrip();
      await _onReconnect();
    } catch (_) {
      emit(state.copyWith(connected: false));
    }
  }

  Future<void> _onReconnect() async {
    if (state.isOnline) {
      _realtime.emit('driver:status', {'status': 'online'});
    }
    final trip = state.trip;
    if (trip == null) return;
    try {
      final fresh = await _remote.getTrip(trip.id);
      // If the rider cancelled while we were offline, drop back to online.
      if (fresh.status == TripStatus.cancelled ||
          fresh.status == TripStatus.completed) {
        emit(state.copyWith(phase: DriverPhase.online, trip: null, riderName: null));
      } else {
        emit(state.copyWith(trip: fresh));
      }
    } catch (_) {
      // Keep the last-known trip; the next event will correct us.
    }
  }

  Future<void> goOnline() async {
    emit(state.copyWith(busy: true, error: null, locationIssue: null));
    // Gate on location access BEFORE flipping the server-side status: an
    // online driver who can't stream GPS never enters the dispatch geo index,
    // so they'd sit "Online" forever without a single offer. Stay offline and
    // tell them what to fix instead.
    final access = await _checkLocation();
    if (access != LocationAccess.granted) {
      emit(state.copyWith(
        busy: false,
        error: locationAccessMessage(access),
        locationIssue: access,
      ));
      return;
    }
    try {
      await _remote.setStatus('online');
      _realtime.emit('driver:status', {'status': 'online'});
      emit(state.copyWith(phase: DriverPhase.online, busy: false));
    } on ApiException catch (e) {
      final needsOnboarding = e.message.toLowerCase().contains('onboarding');
      emit(state.copyWith(
        busy: false,
        error: e.message,
        needsOnboarding: needsOnboarding,
      ));
    }
  }

  Future<void> goOffline() async {
    _cancelAcceptTimer();
    try {
      await _remote.setStatus('offline');
    } catch (_) {/* best effort */}
    _realtime.emit('driver:status', {'status': 'offline'});
    emit(state.copyWith(phase: DriverPhase.offline, offer: null));
  }

  Future<void> onboard({
    required String make,
    required String model,
    required String plate,
    required String tier,
    String? color,
  }) async {
    // Clear needsOnboarding immediately: the dialog is already up, and any
    // interim emission that still carries needsOnboarding=true would make the
    // page listener open a second copy of it.
    emit(state.copyWith(busy: true, error: null, needsOnboarding: false));
    try {
      await _remote.onboarding(
        vehicleMake: make,
        vehicleModel: model,
        plateNumber: plate,
        vehicleTier: tier,
        vehicleColor: color,
      );
      emit(state.copyWith(busy: false, needsOnboarding: false));
      await goOnline();
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  /// Feed a GPS fix in; forwarded to the backend when online/on a trip.
  void sendLocation(double lat, double lng, {double heading = 0, double speed = 0}) {
    if (state.phase == DriverPhase.offline) return;
    _realtime.emit('driver:location', {
      'lat': lat,
      'lng': lng,
      'heading': heading,
      'speed': speed,
    });
  }

  void acceptOffer() {
    final offer = state.offer;
    if (offer == null) return;
    _realtime.emit('trip:accept', {'tripId': offer.tripId});
    emit(state.copyWith(busy: true));
    // Safety net: if neither `trip:assigned` nor `trip:offer_expired` arrives
    // within the offer window (+ grace), the accept was lost — the rider
    // cancelled mid-window, the socket dropped, or the server never answered.
    // Without this the driver stared at an infinite Accept spinner with
    // Decline disabled, and no new offer could reach them (phase stuck at
    // `offered`).
    _cancelAcceptTimer();
    _acceptTimer = Timer(
      Duration(seconds: offer.expiresInSec) + _acceptGrace,
      () {
        _acceptTimer = null;
        if (isClosed) return;
        if (state.phase != DriverPhase.offered ||
            state.offer?.tripId != offer.tripId) {
          return;
        }
        emit(state.copyWith(
          phase: DriverPhase.online,
          offer: null,
          busy: false,
          error: 'That ride was taken or cancelled',
        ));
      },
    );
  }

  void _cancelAcceptTimer() {
    _acceptTimer?.cancel();
    _acceptTimer = null;
  }

  void declineOffer() {
    _cancelAcceptTimer();
    final offer = state.offer;
    if (offer != null) {
      _realtime.emit('trip:decline', {'tripId': offer.tripId});
    }
    emit(state.copyWith(phase: DriverPhase.online, offer: null, busy: false));
  }

  Future<void> markArrived() async {
    final trip = state.trip;
    if (trip == null) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _remote.arrived(trip.id);
      emit(state.copyWith(phase: DriverPhase.arrived, busy: false));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  Future<void> startTrip(String otp) async {
    final trip = state.trip;
    if (trip == null) return;
    emit(state.copyWith(busy: true, error: null));
    try {
      await _remote.start(trip.id, otp);
      emit(state.copyWith(phase: DriverPhase.onTrip, busy: false));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  Future<void> completeTrip() async {
    final trip = state.trip;
    if (trip == null) return;
    emit(state.copyWith(busy: true, error: null));

    Map<String, dynamic> receipt;
    try {
      receipt = await _remote.complete(trip.id);
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
      return;
    } catch (_) {
      emit(state.copyWith(
          busy: false, error: 'Could not complete the trip. Try again.'));
      return;
    }

    // The trip is completed server-side now — move to `completed` IMMEDIATELY so
    // a follow-up failure (e.g. loading earnings) can't leave the driver stranded
    // on the trip screen re-tapping "Complete" on an already-completed trip.
    final isCash = receipt['paymentMode'] == 'cash';
    final cash = isCash ? (receipt['fareFinal'] as num?)?.toDouble() : null;
    emit(state.copyWith(
      phase: DriverPhase.completed,
      trip: null,
      riderName: null,
      busy: false,
      lastTripId: trip.id,
      riderRating: null,
      cashToCollect: cash,
    ));

    // Earnings total is a nice-to-have on the completion sheet — load it
    // best-effort, never reverting the completion above.
    try {
      final earnings = await _remote.earnings(range: 'today');
      if (!isClosed) emit(state.copyWith(lastEarned: earnings.total));
    } catch (_) {
      // Leave lastEarned as-is; the driver is already on the completed sheet.
    }
  }

  /// Rate the rider (1–5) for the just-completed trip.
  Future<void> rateRider(int stars) async {
    final tripId = state.lastTripId;
    if (tripId == null || state.riderRating != null) return;
    try {
      await _ratings.rate(tripId, stars: stars);
      emit(state.copyWith(riderRating: stars));
    } on ApiException catch (e) {
      emit(state.copyWith(error: e.message));
    }
  }

  /// Dismiss the completion sheet and go back online.
  void dismissCompleted() {
    emit(state.copyWith(
      phase: DriverPhase.online,
      lastTripId: null,
      riderRating: null,
    ));
  }

  void _onOffer(RideOffer offer) {
    // Only surface offers while idle-online.
    if (state.phase != DriverPhase.online) return;
    // Drop any stale error (e.g. the previous "taken or cancelled" reset) so
    // the page listener doesn't re-toast it over the new card on this phase
    // change, and so a repeat of the same message can surface again later.
    emit(state.copyWith(phase: DriverPhase.offered, offer: offer, error: null));
  }

  /// The server withdrew an offer — the window elapsed, or the driver accepted
  /// but the trip couldn't be assigned to them (rider cancelled mid-window,
  /// taken by another driver). Clears the card even mid-Accept; a stale event
  /// for some other trip is ignored so it can't wipe a newer offer.
  void _onOfferExpired({String? tripId}) {
    if (state.phase != DriverPhase.offered) return;
    if (tripId != null && state.offer?.tripId != tripId) return;
    _cancelAcceptTimer();
    emit(state.copyWith(
      phase: DriverPhase.online,
      offer: null,
      busy: false,
      error: state.busy ? 'That ride was taken or cancelled' : null,
    ));
  }

  Future<void> _onAssigned(String tripId, {String? approachPolyline}) async {
    try {
      final trip = await _remote.getTrip(tripId);
      _cancelAcceptTimer();
      emit(state.copyWith(
        phase: DriverPhase.enRoute,
        trip: trip,
        offer: null,
        busy: false,
        approachPolyline: approachPolyline,
        // The Trip model carries no rider profile; keep the name from the
        // offer card so the chat header can address the rider by name.
        riderName: state.offer?.riderName,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  void _onCancelledByRider() {
    _cancelAcceptTimer();
    emit(state.copyWith(
      phase: DriverPhase.online,
      trip: null,
      riderName: null,
      offer: null,
      busy: false,
      error: 'The rider cancelled the trip',
    ));
  }

  @override
  Future<void> close() {
    _cancelAcceptTimer();
    for (final s in _subs) {
      s.cancel();
    }
    // The driver home only unmounts on sign-out (or app teardown). Disconnect
    // so the dispatcher stops treating this driver as online — otherwise the
    // ghost identity keeps receiving offers, and the next sign-in could act
    // over the previous user's socket.
    _realtime.disconnect();
    return super.close();
  }
}
