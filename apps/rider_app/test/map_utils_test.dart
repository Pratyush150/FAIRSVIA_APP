import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:rider_app/features/trip/map_utils.dart';

void main() {
  const pickup = LatLng(25.7743, -80.1937); // Miami

  group('MapUtils.spanMeters', () {
    test('is ~0 for coincident points and empty input', () {
      expect(MapUtils.spanMeters(const [pickup, pickup]), closeTo(0, 0.001));
      expect(MapUtils.spanMeters(const []), 0);
      expect(MapUtils.spanMeters(const [pickup]), 0);
    });

    test('measures the bounding-box diagonal in metres', () {
      // ~111 m north.
      const north = LatLng(25.7743 + 0.001, -80.1937);
      expect(MapUtils.spanMeters(const [pickup, north]), closeTo(111, 2));
      // A 30 m car↔pickup gap is under the arrival threshold; 200 m isn't.
      const near = LatLng(25.7743 + 0.00027, -80.1937);
      expect(MapUtils.spanMeters(const [pickup, near]), lessThan(60));
      const far = LatLng(25.7743 + 0.0018, -80.1937);
      expect(MapUtils.spanMeters(const [pickup, far]), greaterThan(60));
    });
  });

  group('MapUtils.boxAround', () {
    test('returns a square of 2×halfSpan metres centred on the point', () {
      final box = MapUtils.boxAround(pickup, 125);
      expect(box, hasLength(2));
      expect(MapUtils.spanMeters(box), closeTo(250 * 1.4142, 2));
      // Centred: corners are symmetric about the pickup.
      expect(
        (box[0].latitude + box[1].latitude) / 2,
        closeTo(pickup.latitude, 1e-9),
      );
      expect(
        (box[0].longitude + box[1].longitude) / 2,
        closeTo(pickup.longitude, 1e-9),
      );
      // South-west first, north-east second (what a bounds fit expects).
      expect(box[0].latitude, lessThan(box[1].latitude));
      expect(box[0].longitude, lessThan(box[1].longitude));
    });
  });
}
