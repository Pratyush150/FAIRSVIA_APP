import 'package:shared_models/shared_models.dart';

import 'places_remote_data_source.dart';
import 'trip_remote_data_source.dart';

/// Facade over the places + trips data sources used by the rider (and later
/// driver) trip flows.
class TripRepository {
  TripRepository(this._places, this._trips);

  final PlacesRemoteDataSource _places;
  final TripRemoteDataSource _trips;

  /// Place search; [near] (the rider's position) biases results and lets the
  /// backend attach `distanceM` per prediction.
  Future<List<PlacePrediction>> autocomplete(
    String query, {
    String? sessionToken,
    GeoPoint? near,
  }) =>
      _places.autocomplete(query, sessionToken: sessionToken, near: near);

  Future<PlaceDetails> placeDetails(String placeId) =>
      _places.details(placeId);

  /// Resolve the rider's GPS coordinates to a human address (pickup label).
  Future<PlaceDetails> reverseGeocode(double lat, double lng) =>
      _places.reverse(lat, lng);

  /// Fresh road route between two points, for live re-routing when the car
  /// leaves the drawn path. Returns the encoded polyline (null = keep current).
  Future<String?> route({
    required double fromLat,
    required double fromLng,
    required double toLat,
    required double toLng,
  }) =>
      _places.route(
        fromLat: fromLat,
        fromLng: fromLng,
        toLat: toLat,
        toLng: toLng,
      );

  Future<TripEstimate> estimate(
    GeoPoint pickup,
    GeoPoint dropoff, {
    List<TripStop> stops = const [],
  }) =>
      _trips.estimate(pickup, dropoff, stops: stops);

  Future<Trip> createTrip({
    required GeoPoint pickup,
    required GeoPoint dropoff,
    required String tier,
    String? pickupAddr,
    String? dropoffAddr,
    String? pickupNote,
    TripPassenger? passenger,
    String? promoCode,
    String? paymentMode,
    String? paymentMethodId,
    DateTime? scheduledAt,
    List<TripStop> stops = const [],
    double? quotedFare,
    double? quotedSurge,
  }) =>
      _trips.create(
        pickup: pickup,
        dropoff: dropoff,
        tier: tier,
        pickupAddr: pickupAddr,
        dropoffAddr: dropoffAddr,
        pickupNote: pickupNote,
        passenger: passenger,
        promoCode: promoCode,
        paymentMode: paymentMode,
        paymentMethodId: paymentMethodId,
        scheduledAt: scheduledAt,
        stops: stops,
        quotedFare: quotedFare,
        quotedSurge: quotedSurge,
      );

  /// The rider's upcoming scheduled rides.
  Future<List<Trip>> scheduled() => _trips.scheduled();

  /// The rider's in-flight trip, if any — used to restore live tracking after
  /// the app is killed and reopened mid-ride.
  Future<Trip?> activeTrip() => _trips.active();

  /// [activeTrip] plus the assigned driver / approach route when the server
  /// includes them, so the matched sheet can be rebuilt after a relaunch.
  Future<ActiveTrip?> activeTripDetails() => _trips.activeDetails();

  /// Prices a promo code against a fare subtotal (rejection reason on failure).
  Future<PromoQuote> quotePromo(String code, num subtotal) =>
      _trips.quotePromo(code, subtotal);

  Future<Trip> getTrip(String id) => _trips.getById(id);

  /// Cancels the trip; returns the cancellation fee charged (0 when none).
  Future<double> cancelTrip(String id, {String? reason}) =>
      _trips.cancel(id, reason: reason);
}
