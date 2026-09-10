import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_models/shared_models.dart';

part 'driver_state.dart';

/// Drives the driver experience: connect → go online → receive/accept offers →
/// drive lifecycle. Location capture lives in the UI (geolocator) and is fed in
/// via [sendLocation] so this cubit stays testable.
class DriverCubit extends Cubit<DriverState> {
  DriverCubit(this._realtime, this._remote, this._ratings)
      : super(const DriverState());

  final RealtimeClient _realtime;
  final DriverRemoteDataSource _remote;
  final RatingsRemoteDataSource _ratings;
  final List<StreamSubscription<dynamic>> _subs = [];

  Future<void> init(String token) async {
    await _realtime.connect(token);
    _subs
      ..add(_realtime.on('trip:offer').listen(
          (d) => _onOffer(RideOffer.fromJson(d))))
      ..add(_realtime.on('trip:offer_expired').listen((_) => _onOfferExpired()))
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
        emit(state.copyWith(phase: DriverPhase.online, trip: null));
      } else {
        emit(state.copyWith(trip: fresh));
      }
    } catch (_) {
      // Keep the last-known trip; the next event will correct us.
    }
  }

  Future<void> goOnline() async {
    emit(state.copyWith(busy: true, error: null));
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
  }

  void declineOffer() {
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
    emit(state.copyWith(phase: DriverPhase.offered, offer: offer));
  }

  void _onOfferExpired() {
    if (state.phase == DriverPhase.offered) {
      emit(state.copyWith(phase: DriverPhase.online, offer: null, busy: false));
    }
  }

  Future<void> _onAssigned(String tripId, {String? approachPolyline}) async {
    try {
      final trip = await _remote.getTrip(tripId);
      emit(state.copyWith(
        phase: DriverPhase.enRoute,
        trip: trip,
        offer: null,
        busy: false,
        approachPolyline: approachPolyline,
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(busy: false, error: e.message));
    }
  }

  void _onCancelledByRider() {
    emit(state.copyWith(
      phase: DriverPhase.online,
      trip: null,
      offer: null,
      busy: false,
      error: 'The rider cancelled the trip',
    ));
  }

  @override
  Future<void> close() {
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
