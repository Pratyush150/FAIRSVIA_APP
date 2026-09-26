import 'package:test/test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  group('cleanPlaceLabel', () {
    test('strips a leading Unnamed Road', () {
      expect(cleanPlaceLabel('Unnamed Road, Dattwadi, Pune'), 'Dattwadi, Pune');
      expect(cleanPlaceLabel('unnamed road , Dattwadi'), 'Dattwadi');
    });
    test('bare Unnamed Road falls back', () {
      expect(cleanPlaceLabel('Unnamed Road'), '');
      expect(cleanPlaceLabel('Unnamed road', fallback: 'Pinned'), 'Pinned');
      expect(cleanPlaceLabel(null, fallback: 'x'), 'x');
    });
    test('leaves real names alone', () {
      expect(cleanPlaceLabel(' Sinhagad Rd, Pune '), 'Sinhagad Rd, Pune');
      expect(cleanPlaceLabel('Unnamed Roadside Dhaba'), 'Unnamed Roadside Dhaba');
    });
    test('PlaceDetails never shows Unnamed Road', () {
      const p = PlaceDetails(
        placeId: 'x',
        address: 'Unnamed Road, Dattwadi, Pune',
        location: GeoPoint(18.5, 73.86),
      );
      expect(p.title, 'Dattwadi, Pune');
      expect(p.shortAddress, 'Dattwadi, Pune');
      const q = PlaceDetails(
        placeId: 'x',
        address: 'Unnamed Road, Dattwadi, Pune',
        location: GeoPoint(18.5, 73.86),
        label: 'Unnamed Road',
        detail: 'Dattwadi, Pune',
      );
      expect(q.shortAddress, 'Dattwadi, Pune');
    });
  });
}
