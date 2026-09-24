import 'package:test/test.dart';
import 'package:shared_models/shared_models.dart';

void main() {
  group('PlaceDetails label/detail', () {
    const full = '204, Mote Mangal Karyalay Rd, Dattwadi, Shobhapur, Dattwadi, '
        'Kasba Peth, Pune, Maharashtra 411011, India';

    test('reads label + detail from a reverse-geocode response', () {
      final p = PlaceDetails.fromJson({
        'placeId': 'ChIJ',
        'address': full,
        'location': {'lat': 18.5074, 'lng': 73.8553},
        'label': 'Mote Mangal Karyalay Rd',
        'detail': 'Dattwadi, Pune',
      });
      expect(p.address, full); // full address untouched
      expect(p.label, 'Mote Mangal Karyalay Rd');
      expect(p.detail, 'Dattwadi, Pune');
      expect(p.title, 'Mote Mangal Karyalay Rd');
      expect(p.caption, 'Dattwadi, Pune');
      expect(p.shortAddress, 'Mote Mangal Karyalay Rd, Dattwadi, Pune');
    });

    test('older backend (no label/detail) falls back to the full address', () {
      final p = PlaceDetails.fromJson({
        'placeId': 'x',
        'address': full,
        'location': {'lat': 18.5, 'lng': 73.8},
      });
      expect(p.label, isNull);
      expect(p.detail, isNull);
      expect(p.title, full);
      expect(p.caption, '');
      expect(p.shortAddress, full);
    });

    test('blank label is ignored; empty detail gives no trailing comma', () {
      const blank = PlaceDetails(
        placeId: 'x',
        address: 'Bhukum, Pune',
        location: GeoPoint(18.5, 73.7),
        label: '  ',
        detail: 'ignored',
      );
      expect(blank.title, 'Bhukum, Pune');
      expect(blank.caption, '');

      const noDetail = PlaceDetails(
        placeId: 'x',
        address: 'Bhukum, Maharashtra 412115, India',
        location: GeoPoint(18.5, 73.7),
        label: 'Bhukum',
        detail: '',
      );
      expect(noDetail.shortAddress, 'Bhukum');
    });

    test('missing placeId (bad-coordinate reverse response) does not throw', () {
      final p = PlaceDetails.fromJson({
        'address': 'Current location',
        'location': {'lat': 18.5, 'lng': 73.8},
        'label': 'Current location',
        'detail': '',
      });
      expect(p.placeId, '');
      expect(p.shortAddress, 'Current location');
    });

    test('label/detail take part in equality', () {
      const a = PlaceDetails(
          placeId: 'x', address: 'a', location: GeoPoint(1, 2), label: 'L');
      const b = PlaceDetails(
          placeId: 'x', address: 'a', location: GeoPoint(1, 2), label: 'M');
      expect(a == b, isFalse);
    });
  });
}
