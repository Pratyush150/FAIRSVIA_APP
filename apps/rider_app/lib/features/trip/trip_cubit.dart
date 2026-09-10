import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:core/core.dart';
import 'package:equatable/equatable.dart';
import 'package:shared_models/shared_models.dart';

part 'trip_state.dart';

/// Drives the rider flow: destination → estimate → tier → create → searching,
/// then live tracking (matched → en route → arrived → on trip → completed) via
/// the socket. Cancelling resets to idle.
class TripCubit extends Cubit<TripState> {
  TripCubit(this._repository, this._realtime, this._payments, this._ratings)
      : super(const TripState());

  final TripRepository _repository;
  final RealtimeClient _realtime;
  final PaymentsRemoteDataSource _payments;
  final RatingsRemoteDataSource _ratings;
  final List<StreamSubscription<dynamic>> _subs = [];

  /// Connect the socket and subscribe to trip lifecycle events.
  Future<void> init(String token) async {
    await _realtime.connect(token);
    _subs
      ..add(_realtime.on('trip:matching').listen((_) => _onMatching()))
      ..add(_realtime.on('trip:accepted').listen(_onAccepted))
      ..add(_realtime.on('trip:driver_location').listen(_onDriverLocation))
      ..add(_realtime.on('trip:arrived').listen((_) => _setPhase(TripPhase.driverArrived)))
      ..add(_realtime.on('trip:started').listen((_) => _setPhase(TripPhase.onTrip)))
      ..add(_realtime.on('trip:completed').listen(_onCompleted))
      ..add(_realtime.on('trip:no_drivers').listen((_) => _onNoDrivers()))
      // Reconnection resilience: the server replies to `trip:sync` with the
      // authoritative trip so we can rehydrate after a dropped socket.
      ..add(_realtime.on('trip:sync').listen(_onSync))
      ..add(_realtime.reconnects.listen((_) => _resync()))
      // Surface socket up/down edges so the UI can show a reconnecting banner.
      ..add(_realtime.connection.listen((up) {
        if (up != state.connected) emit(state.copyWith(connected: up));
      }));
    // If the app was killed and reopened mid-ride, restore the live-tracking
    // screen instead of dropping the rider on the idle "Where to?" home while
    // a driver is actually on the way.
    await _restoreActiveTrip();
  }

  /// Pull the server-authoritative in-flight trip (if any) on a cold start.
  Future<void> _restoreActiveTrip() async {
    try {
      final trip = await _repository.activeTrip();
      if (trip == null) return;
      _applyTrip(trip);
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
      await _realtime.connect(token);
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
    _applyTrip(trip);
  }

  /// Move the UI to the phase implied by [trip]'s server-side status.
  void _applyTrip(Trip trip) {
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
      emit(const TripState());
    } else {
      emit(state.copyWith(phase: phase, trip: trip));
    }
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

  void _onDriverLocation(Map<String, dynamic> data) {
    final lat = (data['lat'] as num?)?.toDouble();
    final lng = (data['lng'] as num?)?.toDouble();
    if (lat == null || lng == null) return;
    emit(state.copyWith(driverLocation: GeoPoint(lat, lng)));
  }

  void _onCompleted(Map<String, dynamic> data) {
    emit(state.copyWith(
      phase: TripPhase.completed,
      fareFinal: (data['fareFinal'] as num?)?.toDouble(),
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
      emit(state.copyWith(paymentMethods: methods));
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
        scheduledAt: s.scheduledAt,
        stops: s.stops,
      );
      // A scheduled ride isn't dispatched now — confirm it and return to idle
      // (it will surface again from the scheduled-rides list at its time).
      if (trip.status == TripStatus.scheduled) {
        emit(state.copyWith(phase: TripPhase.scheduled, trip: trip));
        return;
      }
      emit(state.copyWith(phase: TripPhase.searching, trip: trip));
    } on ApiException catch (e) {
      emit(state.copyWith(phase: TripPhase.choosingRide, error: e.message));
    }
  }

  /// Cancels the active trip and returns the cancellation fee charged (0 when
  /// none), so the UI can tell the rider they were charged.
  Future<double> cancelTrip() async {
    final trip = state.trip;
    var fee = 0.0;
    if (trip != null) {
      try {
        fee = await _repository.cancelTrip(trip.id, reason: 'Cancelled by rider');
      } catch (_) {
        // Best-effort: reset the UI regardless.
      }
    }
    emit(const TripState());
    return fee;
  }

  void reset() => emit(const TripState());

  @override
  Future<void> close() {
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
