// ignore_for_file: avoid_print, avoid_relative_lib_imports
// End-to-end smoke test of the Flutter TRIP client layer against the live
// backend (VM, no Flutter). Requires the backend running.
//
//   dart run tool/trip_smoke.dart [baseUrl]
import 'package:dio/dio.dart';

import '../lib/src/auth/auth_remote_data_source.dart';
import '../lib/src/trip/places_remote_data_source.dart';
import '../lib/src/trip/trip_remote_data_source.dart';

Future<void> main(List<String> args) async {
  final baseUrl = args.isNotEmpty ? args.first : 'http://localhost:3000/api/v1';
  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    connectTimeout: const Duration(seconds: 5),
    receiveTimeout: const Duration(seconds: 5),
  ));

  // Log in to get a token.
  final auth = AuthRemoteDataSource(dio);
  final phone = '+198${DateTime.now().millisecondsSinceEpoch % 100000000}';
  final otp = await auth.requestOtp(phone);
  final session = await auth.verifyOtp(phone, otp.devCode!);
  dio.options.headers['Authorization'] =
      'Bearer ${session.tokens.accessToken}';
  print('› logged in as $phone');

  final places = PlacesRemoteDataSource(dio);
  final trips = TripRemoteDataSource(dio);

  final predictions = await places.autocomplete('MG');
  print('✓ autocomplete  ${predictions.length} results, first="${predictions.first.primaryText}"');

  final details = await places.details(predictions.first.placeId);
  print('✓ placeDetails  ${details.location.lat},${details.location.lng}');

  final pickup = details.location; // reuse as a nearby pickup base
  final estimate = await trips.estimate(pickup, details.location);
  print('✓ estimate      ${estimate.tiers.length} tiers, economy=\$${estimate.tiers.first.fare}');

  final trip = await trips.create(
    pickup: pickup,
    dropoff: details.location,
    tier: 'economy',
    pickupAddr: 'Pickup',
    dropoffAddr: details.address,
  );
  print('✓ createTrip    id=${trip.id} status=${trip.status.name} fare=\$${trip.fareEstimate}');

  final fetched = await trips.getById(trip.id);
  print('✓ getTrip       status=${fetched.status.name}');

  await trips.cancel(trip.id, reason: 'smoke test');
  final afterCancel = await trips.getById(trip.id);
  print('✓ cancelTrip    status=${afterCancel.status.name}');

  if (afterCancel.status.name != 'cancelled') {
    throw StateError('cancel did not take effect');
  }
  print('SMOKE OK — Flutter trip client ↔ backend verified end-to-end');
}
