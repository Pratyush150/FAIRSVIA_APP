import 'package:shared_models/shared_models.dart';
import 'package:test/test.dart';

void main() {
  group('SavedPlace', () {
    test('parses from JSON', () {
      final p = SavedPlace.fromJson({
        'id': 'abc',
        'label': 'Home',
        'address': 'MG Road',
        'lat': 12.97,
        'lng': 77.59,
      });
      expect(p.id, 'abc');
      expect(p.label, 'Home');
      expect(p.address, 'MG Road');
      expect(p.point.lat, 12.97);
      expect(p.point.lng, 77.59);
    });

    test('tolerates a missing address', () {
      final p = SavedPlace.fromJson({
        'id': 'x',
        'label': 'Work',
        'lat': 1.0,
        'lng': 2.0,
      });
      expect(p.address, isNull);
    });
  });

  group('Trip history fields', () {
    final json = {
      'id': 't1',
      'status': 'completed',
      'tier': 'economy',
      'pickup': {'lat': 1.0, 'lng': 2.0, 'address': 'A'},
      'dropoff': {'lat': 3.0, 'lng': 4.0, 'address': 'B'},
      'fareEstimate': 120,
      'fareFinal': 140,
      'requestedAt': '2026-07-14T10:00:00.000Z',
      'completedAt': '2026-07-14T10:20:00.000Z',
    };

    test('parses requestedAt/completedAt timestamps', () {
      final t = Trip.fromJson(json);
      expect(t.requestedAt, isNotNull);
      expect(t.completedAt, isNotNull);
      expect(t.completedAt!.isAfter(t.requestedAt!), isTrue);
    });

    test('fareDisplay prefers the final fare over the estimate', () {
      expect(Trip.fromJson(json).fareDisplay, 140);
    });

    test('fareDisplay falls back to the estimate when no final fare', () {
      final t = Trip.fromJson({...json}..remove('fareFinal'));
      expect(t.fareDisplay, 120);
    });

    test('null timestamps when absent', () {
      final t = Trip.fromJson({
        'id': 't2',
        'status': 'requested',
        'tier': 'economy',
        'pickup': {'lat': 1.0, 'lng': 2.0},
        'dropoff': {'lat': 3.0, 'lng': 4.0},
      });
      expect(t.requestedAt, isNull);
      expect(t.completedAt, isNull);
    });
  });

  group('SupportTicket', () {
    test('parses a ticket with its thread', () {
      final t = SupportTicket.fromJson({
        'id': 'tk1',
        'subject': 'Charged twice',
        'category': 'payment',
        'status': 'active',
        'tripId': 'trip-9',
        'messages': [
          {'id': 'm1', 'authorRole': 'user', 'body': 'Help', 'createdAt': null},
          {'id': 'm2', 'authorRole': 'admin', 'body': 'On it', 'createdAt': null},
        ],
      });
      expect(t.id, 'tk1');
      expect(t.subject, 'Charged twice');
      expect(t.status, 'active');
      expect(t.tripId, 'trip-9');
      expect(t.isClosed, isFalse);
      expect(t.messages, hasLength(2));
      expect(t.messages[0].isFromAdmin, isFalse);
      expect(t.messages[1].isFromAdmin, isTrue);
    });

    test('list view leaves messages empty and flags closed', () {
      final t = SupportTicket.fromJson({
        'id': 'tk2',
        'subject': 'Lost phone',
        'category': 'lost_item',
        'status': 'closed',
      });
      expect(t.messages, isEmpty);
      expect(t.isClosed, isTrue);
    });
  });
}
