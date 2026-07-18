import 'package:shared_models/shared_models.dart';

import 'places_remote_data_source.dart';
import 'trip_remote_data_source.dart';

/// Facade over the places + trips data sources used by the rider (and later
/// driver) trip flows.
class TripRepository {
  TripRepository(this._places, this._trips);

  final PlacesRemoteDataSource _places;
  final TripRemoteDataSource _trips;

  Future<List<PlacePrediction>> autocomplete(String query, {String? sessionToken}) =>
      _places.autocomplete(query, sessionToken: sessionToken);

  Future<PlaceDetails> placeDetails(String placeId) =>
      _places.details(placeId);

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
    String? promoCode,
    String? paymentMode,
    String? paymentMethodId,
    DateTime? scheduledAt,
    List<TripStop> stops = const [],
  }) =>
      _trips.create(
        pickup: pickup,
        dropoff: dropoff,
        tier: tier,
        pickupAddr: pickupAddr,
        dropoffAddr: dropoffAddr,
        promoCode: promoCode,
        paymentMode: paymentMode,
        paymentMethodId: paymentMethodId,
        scheduledAt: scheduledAt,
        stops: stops,
      );

  /// The rider's upcoming scheduled rides.
  Future<List<Trip>> scheduled() => _trips.scheduled();

  /// Prices a promo code against a fare subtotal (rejection reason on failure).
  Future<PromoQuote> quotePromo(String code, num subtotal) =>
      _trips.quotePromo(code, subtotal);

  Future<Trip> getTrip(String id) => _trips.getById(id);

  Future<void> cancelTrip(String id, {String? reason}) =>
      _trips.cancel(id, reason: reason);
}
