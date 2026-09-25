import 'package:test/test.dart';
import 'package:shared_models/shared_models.dart';

Map<String, dynamic> _base() => {
      'id': 't1',
      'status': 'completed',
      'tier': 'economy',
      'pickup': {'lat': 41.31, 'lng': 69.24, 'address': 'A'},
      'dropoff': {'lat': 41.33, 'lng': 69.28, 'address': 'B'},
    };

void main() {
  test('parses the history driver block and myRating', () {
    final t = Trip.fromJson({
      ..._base(),
      'driver': {
        'name': ' Aziz Karimov ',
        'avatarUrl': 'https://cdn.example/aziz.jpg',
        'vehicleLabel': 'White Chevrolet Cobalt',
        'plate': '01A123BC',
      },
      'myRating': 4,
    });
    expect(t.driverName, 'Aziz Karimov');
    expect(t.driverAvatarUrl, 'https://cdn.example/aziz.jpg');
    expect(t.driverVehicleLabel, 'White Chevrolet Cobalt');
    expect(t.myRating, 4);
    expect(t.hasMyRatingField, isTrue);
  });

  test('myRating: null means unrated when the field is present', () {
    final t = Trip.fromJson({..._base(), 'myRating': null});
    expect(t.myRating, isNull);
    expect(t.hasMyRatingField, isTrue);
  });

  test('older payloads without driver/myRating still parse', () {
    final t = Trip.fromJson(_base());
    expect(t.driverName, isNull);
    expect(t.driverAvatarUrl, isNull);
    expect(t.myRating, isNull);
    expect(t.hasMyRatingField, isFalse);
  });

  test('empty or non-string driver fields are ignored', () {
    final t = Trip.fromJson({
      ..._base(),
      'driver': {'name': '  ', 'avatarUrl': null, 'rating': 4.9},
    });
    expect(t.driverName, isNull);
    expect(t.driverAvatarUrl, isNull);
  });
}
