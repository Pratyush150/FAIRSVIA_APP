import 'package:dio/dio.dart';

import '../network/api_exception.dart';

/// A local emergency service number, e.g. Police 102.
class EmergencyNumber {
  const EmergencyNumber(this.label, this.number);

  factory EmergencyNumber.fromJson(Map<String, dynamic> j) =>
      EmergencyNumber(j['label'] as String, j['number'] as String);

  final String label;
  final String number;

  /// Used until the server's list arrives, so the call buttons work even
  /// offline. Matches the backend default (Uzbekistan).
  static const fallback = [
    EmergencyNumber('Police', '102'),
    EmergencyNumber('Ambulance', '103'),
    EmergencyNumber('Fire', '101'),
  ];
}

/// Someone the user wants texted when they press SOS.
class EmergencyContact {
  const EmergencyContact({
    required this.id,
    required this.name,
    required this.phone,
  });

  factory EmergencyContact.fromJson(Map<String, dynamic> j) => EmergencyContact(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String,
      );

  final String id;
  final String name;
  final String phone;
}

/// What an SOS press actually did, so the UI can say exactly that.
class SosResult {
  const SosResult({
    required this.incidentId,
    required this.contactsNotified,
    required this.contactsTotal,
    required this.repeat,
    required this.emergencyNumbers,
  });

  factory SosResult.fromJson(Map<String, dynamic> j) => SosResult(
        incidentId: j['incidentId'] as String? ?? '',
        contactsNotified: (j['contactsNotified'] as num?)?.toInt() ?? 0,
        contactsTotal: (j['contactsTotal'] as num?)?.toInt() ?? 0,
        repeat: j['repeat'] as bool? ?? false,
        emergencyNumbers: ((j['emergencyNumbers'] as List?) ?? const [])
            .cast<Map<String, dynamic>>()
            .map(EmergencyNumber.fromJson)
            .toList(),
      );

  final String incidentId;
  final int contactsNotified;
  final int contactsTotal;

  /// A second press within a couple of minutes: same incident, contacts not
  /// texted again.
  final bool repeat;
  final List<EmergencyNumber> emergencyNumbers;
}

/// Safety toolkit: SOS, local emergency numbers, emergency contacts.
class SafetyRemoteDataSource {
  SafetyRemoteDataSource(this._dio);
  final Dio _dio;

  static const maxContacts = 3;

  Future<SosResult> raiseSos(String tripId, {double? lat, double? lng}) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/trips/$tripId/sos',
          data: {'lat': ?lat, 'lng': ?lng},
        );
        return SosResult.fromJson(res.data ?? const {});
      });

  Future<List<EmergencyNumber>> emergencyNumbers() => _guard(() async {
        final res = await _dio.get<Map<String, dynamic>>('/safety/config');
        final list = (res.data?['emergencyNumbers'] as List?) ?? const [];
        return list
            .cast<Map<String, dynamic>>()
            .map(EmergencyNumber.fromJson)
            .toList();
      });

  Future<List<EmergencyContact>> contacts() => _guard(() async {
        final res =
            await _dio.get<List<dynamic>>('/users/me/emergency-contacts');
        return (res.data ?? const [])
            .cast<Map<String, dynamic>>()
            .map(EmergencyContact.fromJson)
            .toList();
      });

  Future<EmergencyContact> addContact(String name, String phone) =>
      _guard(() async {
        final res = await _dio.post<Map<String, dynamic>>(
          '/users/me/emergency-contacts',
          data: {'name': name, 'phone': phone},
        );
        return EmergencyContact.fromJson(res.data!);
      });

  Future<void> removeContact(String id) => _guard(
      () => _dio.delete<Map<String, dynamic>>('/users/me/emergency-contacts/$id'));

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
