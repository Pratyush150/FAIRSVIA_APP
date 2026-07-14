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
      ..add(_realtime.reconnects.listen((_) => _resync()));
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
    emit(state.copyWith(
      phase: TripPhase.error,
      error: 'No drivers available right now. Please try again.',
    ));
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
      ));
    } on ApiException catch (e) {
      emit(state.copyWith(phase: TripPhase.error, error: e.message));
    }
  }

  void selectTier(String tier) => emit(state.copyWith(selectedTier: tier));

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

  void setPaymentMode(String mode) =>
      emit(state.copyWith(paymentMode: mode));

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
      );
      emit(state.copyWith(phase: TripPhase.searching, trip: trip));
    } on ApiException catch (e) {
      emit(state.copyWith(phase: TripPhase.choosingRide, error: e.message));
    }
  }

  Future<void> cancelTrip() async {
    final trip = state.trip;
    if (trip != null) {
      try {
        await _repository.cancelTrip(trip.id, reason: 'Cancelled by rider');
      } catch (_) {
        // Best-effort: reset the UI regardless.
      }
    }
    emit(const TripState());
  }

  void reset() => emit(const TripState());

  @override
  Future<void> close() {
    for (final s in _subs) {
      s.cancel();
    }
    return super.close();
  }
}
