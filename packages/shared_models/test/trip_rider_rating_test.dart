import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

/// The rider's rating on the assigned driver's view of a live trip.
void main() {
  Map<String, dynamic> base([Map<String, dynamic>? rider]) => {
        'id': 't1',
        'status': 'accepted',
        'tier': 'economy',
        'pickup': {'lat': 1.0, 'lng': 2.0},
        'dropoff': {'lat': 1.1, 'lng': 2.1},
        'rider': ?rider,
      };

  test('reads rider.rating as a double', () {
    final t = Trip.fromJson(base({'name': 'Priya', 'rating': 4.8}));
    expect(t.riderRating, 4.8);
    final i = Trip.fromJson(base({'name': 'Priya', 'rating': 5}));
    expect(i.riderRating, 5.0);
  });

  test('is null without a rider block or rating', () {
    expect(Trip.fromJson(base()).riderRating, isNull);
    expect(Trip.fromJson(base({'name': 'Priya'})).riderRating, isNull);
    expect(Trip.fromJson(base({'rating': null})).riderRating, isNull);
  });

  test('takes part in equality', () {
    expect(
      Trip.fromJson(base({'rating': 4.2})),
      isNot(Trip.fromJson(base({'rating': 4.9}))),
    );
  });
}
