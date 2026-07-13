import 'package:core/core.dart';
import 'package:dio/dio.dart';

/// Dashboard headline counters (`GET /admin/stats`).
class AdminStats {
  const AdminStats({
    required this.users,
    required this.drivers,
    required this.onlineDrivers,
    required this.activeTrips,
    required this.completedTrips,
    required this.tripsByStatus,
    required this.grossRevenue,
    required this.platformRevenue,
  });

  final int users;
  final int drivers;
  final int onlineDrivers;
  final int activeTrips;
  final int completedTrips;
  final Map<String, int> tripsByStatus;
  final double grossRevenue;
  final double platformRevenue;

  factory AdminStats.fromJson(Map<String, dynamic> j) => AdminStats(
        users: (j['users'] as num?)?.toInt() ?? 0,
        drivers: (j['drivers'] as num?)?.toInt() ?? 0,
        onlineDrivers: (j['onlineDrivers'] as num?)?.toInt() ?? 0,
        activeTrips: (j['activeTrips'] as num?)?.toInt() ?? 0,
        completedTrips: (j['completedTrips'] as num?)?.toInt() ?? 0,
        tripsByStatus: {
          for (final e in (j['tripsByStatus'] as Map? ?? {}).entries)
            e.key as String: (e.value as num).toInt(),
        },
        grossRevenue: (j['grossRevenue'] as num?)?.toDouble() ?? 0,
        platformRevenue: (j['platformRevenue'] as num?)?.toDouble() ?? 0,
      );
}

class AdminParty {
  const AdminParty({required this.id, this.name, this.phone});
  final String id;
  final String? name;
  final String? phone;

  static AdminParty? fromJson(Map<String, dynamic>? j) => j == null
      ? null
      : AdminParty(
          id: j['id'] as String,
          name: j['name'] as String?,
          phone: j['phone'] as String?,
        );
}

class AdminTrip {
  const AdminTrip({
    required this.id,
    required this.status,
    required this.tier,
    required this.fare,
    required this.currency,
    this.rider,
    this.driver,
    this.pickup,
    this.dropoff,
    this.requestedAt,
  });

  final String id;
  final String status;
  final String tier;
  final double fare;
  final String currency;
  final AdminParty? rider;
  final AdminParty? driver;
  final String? pickup;
  final String? dropoff;
  final DateTime? requestedAt;

  factory AdminTrip.fromJson(Map<String, dynamic> j) => AdminTrip(
        id: j['id'] as String,
        status: j['status'] as String,
        tier: j['tier'] as String? ?? '',
        fare: (j['fare'] as num?)?.toDouble() ?? 0,
        currency: j['currency'] as String? ?? 'INR',
        rider: AdminParty.fromJson(j['rider'] as Map<String, dynamic>?),
        driver: AdminParty.fromJson(j['driver'] as Map<String, dynamic>?),
        pickup: j['pickup'] as String?,
        dropoff: j['dropoff'] as String?,
        requestedAt: j['requestedAt'] == null
            ? null
            : DateTime.tryParse(j['requestedAt'] as String),
      );
}

class AdminUser {
  const AdminUser({
    required this.id,
    required this.phone,
    required this.role,
    required this.ratingAvg,
    required this.ratingCount,
    required this.isActive,
    this.name,
  });

  final String id;
  final String phone;
  final String role;
  final double ratingAvg;
  final int ratingCount;
  final bool isActive;
  final String? name;

  factory AdminUser.fromJson(Map<String, dynamic> j) => AdminUser(
        id: j['id'] as String,
        phone: j['phone'] as String,
        role: j['role'] as String? ?? 'rider',
        ratingAvg: (j['ratingAvg'] as num?)?.toDouble() ?? 5,
        ratingCount: (j['ratingCount'] as num?)?.toInt() ?? 0,
        isActive: j['isActive'] as bool? ?? true,
        name: j['name'] as String?,
      );
}

class AdminDriver {
  const AdminDriver({
    required this.id,
    required this.phone,
    required this.isActive,
    required this.rating,
    required this.totalTrips,
    required this.liveStatus,
    required this.vehicle,
    this.name,
  });

  final String id;
  final String phone;
  final bool isActive;
  final double rating;
  final int totalTrips;
  final String liveStatus;
  final String vehicle;
  final String? name;

  factory AdminDriver.fromJson(Map<String, dynamic> j) {
    final v = j['vehicle'] as Map<String, dynamic>? ?? {};
    final parts = [
      v['color'],
      v['make'],
      v['model'],
    ].whereType<String>().join(' ');
    return AdminDriver(
      id: j['id'] as String,
      phone: j['phone'] as String? ?? '',
      isActive: j['isActive'] as bool? ?? true,
      rating: (j['rating'] as num?)?.toDouble() ?? 5,
      totalTrips: (j['totalTrips'] as num?)?.toInt() ?? 0,
      liveStatus: j['liveStatus'] as String? ?? 'offline',
      vehicle: parts.isEmpty ? '—' : '$parts (${v['plate'] ?? '?'})',
      name: j['name'] as String?,
    );
  }
}

/// REST calls for the admin dashboard (all role-gated on the backend).
class AdminApi {
  AdminApi(this._dio);
  final Dio _dio;

  Future<AdminStats> stats() async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>('/admin/stats'),
    );
    return AdminStats.fromJson(res.data!);
  }

  Future<List<AdminTrip>> trips({String? status, int limit = 50}) async {
    final res = await _guard(
      () => _dio.get<List<dynamic>>('/admin/trips', queryParameters: {
        'status': ?status,
        'limit': limit,
      }),
    );
    return res.data!
        .map((e) => AdminTrip.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminUser>> users({String? q, int limit = 100}) async {
    final res = await _guard(
      () => _dio.get<List<dynamic>>('/admin/users', queryParameters: {
        if (q != null && q.isNotEmpty) 'q': q,
        'limit': limit,
      }),
    );
    return res.data!
        .map((e) => AdminUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<AdminDriver>> drivers({int limit = 100}) async {
    final res = await _guard(
      () => _dio.get<List<dynamic>>('/admin/drivers', queryParameters: {
        'limit': limit,
      }),
    );
    return res.data!
        .map((e) => AdminDriver.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setActive(String userId, bool isActive) => _guard(
        () => _dio.patch('/admin/users/$userId/active', data: {
          'isActive': isActive,
        }),
      );

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw ApiException.fromDio(e);
    }
  }
}
