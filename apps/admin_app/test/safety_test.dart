import 'package:admin_app/cubit/admin_cubit.dart';
import 'package:admin_app/data/admin_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockApi extends Mock implements AdminApi {}

Map<String, dynamic> _incident(String id, String status) => {
      'id': id,
      'tripId': 't-$id',
      'status': status,
      'raisedByRole': 'rider',
      'lat': 41.3265,
      'lng': 69.2285,
      'contactsNotified': 1,
      'contactsTotal': 2,
      'createdAt': '2026-09-23T07:00:00.000Z',
      'note': null,
      'trip': {
        'status': 'in_progress',
        'pickup': 'Amir Temur Square',
        'dropoff': 'Chorsu Bazaar',
        'rider': {'id': 'r1', 'fullName': 'Aziza', 'phone': '+998901110001'},
        'driver': {
          'id': 'd1',
          'fullName': 'Bekzod',
          'phone': '+998901110002',
          'plate': '01A123BC',
        },
      },
    };

void main() {
  group('AdminSafetyIncident', () {
    test('parses the server shape and knows who pressed SOS', () {
      final i = AdminSafetyIncident.fromJson(_incident('a', 'open'));
      expect(i.isOpen, isTrue);
      expect(i.raisedBy?.name, 'Aziza');
      expect(i.driver?.plate, '01A123BC');
      expect(i.mapUrl, 'https://maps.google.com/?q=41.32650,69.22850');
    });

    test('has no map link without a location', () {
      final j = _incident('a', 'open')..['lat'] = null;
      expect(AdminSafetyIncident.fromJson(j).mapUrl, isNull);
    });
  });

  group('AdminCubit safety', () {
    late _MockApi api;

    setUp(() {
      api = _MockApi();
      when(() => api.stats()).thenAnswer((_) async => throw Exception('n/a'));
    });

    test('counts only unacknowledged incidents as open', () async {
      when(() => api.safetyIncidents()).thenAnswer((_) async => [
            AdminSafetyIncident.fromJson(_incident('a', 'open')),
            AdminSafetyIncident.fromJson(_incident('b', 'acknowledged')),
            AdminSafetyIncident.fromJson(_incident('c', 'resolved')),
          ]);
      final cubit = AdminCubit(api);
      await cubit.start();
      expect(cubit.state.openIncidents, 1);
      expect(cubit.state.incidents, hasLength(3));
      await cubit.close();
    });

    test('acknowledging refreshes the count', () async {
      var status = 'open';
      when(() => api.safetyIncidents()).thenAnswer(
          (_) async => [AdminSafetyIncident.fromJson(_incident('a', status))]);
      when(() => api.updateIncident('a', 'acknowledged'))
          .thenAnswer((_) async => status = 'acknowledged');
      final cubit = AdminCubit(api);
      await cubit.start();
      expect(cubit.state.openIncidents, 1);

      await cubit.updateIncident('a', 'acknowledged');
      expect(cubit.state.openIncidents, 0);
      await cubit.close();
    });
  });
}
