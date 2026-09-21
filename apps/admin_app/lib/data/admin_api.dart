import 'package:core/core.dart';
import 'package:dio/dio.dart';

/// A live driver position (`GET /admin/live`).
class LiveDriver {
  const LiveDriver({
    required this.driverId,
    required this.lat,
    required this.lng,
    required this.status,
    this.tier,
  });

  final String driverId;
  final double lat;
  final double lng;
  final String status;
  final String? tier;

  factory LiveDriver.fromJson(Map<String, dynamic> j) => LiveDriver(
        driverId: j['driverId'] as String,
        lat: (j['lat'] as num).toDouble(),
        lng: (j['lng'] as num).toDouble(),
        status: j['status'] as String? ?? 'online',
        tier: j['tier'] as String?,
      );
}

/// A live active-trip endpoint pair (`GET /admin/live`).
class LiveTrip {
  const LiveTrip({
    required this.id,
    required this.status,
    required this.pickupLat,
    required this.pickupLng,
  });

  final String id;
  final String status;
  final double pickupLat;
  final double pickupLng;

  factory LiveTrip.fromJson(Map<String, dynamic> j) {
    final pickup = (j['pickup'] as Map?)?.cast<String, dynamic>() ?? const {};
    return LiveTrip(
      id: j['id'] as String,
      status: j['status'] as String? ?? '',
      pickupLat: (pickup['lat'] as num?)?.toDouble() ?? 0,
      pickupLng: (pickup['lng'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// The live ops snapshot: online drivers + in-flight trips.
class LiveSnapshot {
  const LiveSnapshot({required this.drivers, required this.trips});

  final List<LiveDriver> drivers;
  final List<LiveTrip> trips;

  static const empty = LiveSnapshot(drivers: [], trips: []);

  factory LiveSnapshot.fromJson(Map<String, dynamic> j) => LiveSnapshot(
        drivers: (j['drivers'] as List<dynamic>? ?? const [])
            .map((d) => LiveDriver.fromJson(d as Map<String, dynamic>))
            .toList(),
        trips: (j['trips'] as List<dynamic>? ?? const [])
            .map((t) => LiveTrip.fromJson(t as Map<String, dynamic>))
            .toList(),
      );
}

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
        currency: j['currency'] as String? ?? 'USD',
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
    required this.docsVerified,
    required this.rating,
    required this.totalTrips,
    required this.liveStatus,
    required this.vehicle,
    this.name,
  });

  final String id;
  final String phone;
  final bool isActive;
  final bool docsVerified;
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
      docsVerified: j['docsVerified'] as bool? ?? false,
      rating: (j['rating'] as num?)?.toDouble() ?? 5,
      totalTrips: (j['totalTrips'] as num?)?.toInt() ?? 0,
      liveStatus: j['liveStatus'] as String? ?? 'offline',
      vehicle: parts.isEmpty ? '—' : '$parts (${v['plate'] ?? '?'})',
      name: j['name'] as String?,
    );
  }
}

/// A support ticket in the admin queue. [messages] is populated only when a
/// single thread is fetched.
class AdminSupportMessage {
  const AdminSupportMessage({
    required this.authorRole,
    required this.body,
    this.createdAt,
  });

  final String authorRole;
  final String body;
  final DateTime? createdAt;

  bool get isFromAdmin => authorRole == 'admin';

  factory AdminSupportMessage.fromJson(Map<String, dynamic> j) =>
      AdminSupportMessage(
        authorRole: j['authorRole'] as String? ?? 'user',
        body: j['body'] as String? ?? '',
        createdAt: j['createdAt'] == null
            ? null
            : DateTime.tryParse(j['createdAt'] as String),
      );
}

class AdminSupportTicket {
  const AdminSupportTicket({
    required this.id,
    required this.subject,
    required this.category,
    required this.status,
    this.updatedAt,
    this.messages = const [],
  });

  final String id;
  final String subject;
  final String category;
  final String status;
  final DateTime? updatedAt;
  final List<AdminSupportMessage> messages;

  factory AdminSupportTicket.fromJson(Map<String, dynamic> j) =>
      AdminSupportTicket(
        id: j['id'] as String,
        subject: j['subject'] as String? ?? '',
        category: j['category'] as String? ?? 'other',
        status: j['status'] as String? ?? 'open',
        updatedAt: j['updatedAt'] == null
            ? null
            : DateTime.tryParse(j['updatedAt'] as String),
        messages: (j['messages'] as List<dynamic>? ?? const [])
            .map((m) => AdminSupportMessage.fromJson(m as Map<String, dynamic>))
            .toList(),
      );
}

class AdminPromo {
  const AdminPromo({
    required this.code,
    required this.kind,
    required this.value,
    required this.active,
    required this.usedCount,
    this.usageLimit,
    required this.minSubtotal,
  });

  final String code;
  final String kind; // 'flat' | 'percent'
  final double value;
  final bool active;
  final int usedCount;
  final int? usageLimit;
  final double minSubtotal;

  /// Human label for the discount, e.g. "20% (max $8)" or "$5 off".
  String get label => kind == 'percent'
      ? '${value.toStringAsFixed(0)}% off'
      : '\$${value.toStringAsFixed(2)} off';

  // Prisma serialises Decimal columns (value, minSubtotal) as JSON *strings*,
  // so parse defensively rather than casting to num.
  static double _num(Object? v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  factory AdminPromo.fromJson(Map<String, dynamic> j) => AdminPromo(
        code: j['code'] as String,
        kind: j['kind'] as String? ?? 'flat',
        value: _num(j['value']),
        active: j['active'] as bool? ?? true,
        usedCount: (j['usedCount'] as num?)?.toInt() ?? 0,
        usageLimit: (j['usageLimit'] as num?)?.toInt(),
        minSubtotal: _num(j['minSubtotal']),
      );
}

class AdminFare {
  const AdminFare({
    required this.tier,
    required this.label,
    required this.baseFare,
    required this.perMile,
    required this.perMin,
    required this.bookingFee,
    required this.minFare,
    required this.capacity,
  });

  final String tier;
  final String label;
  final double baseFare;
  final double perMile;
  final double perMin;
  final double bookingFee;
  final double minFare;
  final int capacity;

  static double _n(Object? v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  factory AdminFare.fromJson(Map<String, dynamic> j) => AdminFare(
        tier: j['tier'] as String,
        label: j['label'] as String? ?? j['tier'] as String,
        baseFare: _n(j['baseFare']),
        perMile: _n(j['perMile']),
        perMin: _n(j['perMin']),
        bookingFee: _n(j['bookingFee']),
        minFare: _n(j['minFare']),
        capacity: (j['capacity'] as num?)?.toInt() ?? 4,
      );
}

class AdminSurgeCell {
  const AdminSurgeCell({required this.cell, required this.demand});
  final String cell;
  final int demand;
}

class AdminSurge {
  const AdminSurge({required this.override, required this.cap, required this.cells});
  final double? override; // active override multiplier, or null
  final double cap;
  final List<AdminSurgeCell> cells;

  static const empty = AdminSurge(override: null, cap: 2.0, cells: []);

  factory AdminSurge.fromJson(Map<String, dynamic> j) => AdminSurge(
        override: (j['override'] as num?)?.toDouble(),
        cap: (j['cap'] as num?)?.toDouble() ?? 2.0,
        cells: ((j['activeCells'] as List?) ?? [])
            .map((e) => AdminSurgeCell(
                  cell: (e as Map)['cell'] as String? ?? '?',
                  demand: (e['demand'] as num?)?.toInt() ?? 0,
                ))
            .toList(),
      );
}

/// A competitor rate card for the price-comparison feature, with calibration
/// provenance (whether it's been fitted from observed fares, and how well).
class AdminComparisonModel {
  const AdminComparisonModel({
    required this.provider,
    required this.displayName,
    required this.productName,
    required this.baseFare,
    required this.perMile,
    required this.perMin,
    required this.bookingFee,
    required this.minFare,
    required this.calibrated,
    required this.residualPct,
  });

  final String provider;
  final String displayName;
  final String productName;
  final double baseFare;
  final double perMile;
  final double perMin;
  final double bookingFee;
  final double minFare;
  final bool calibrated;
  final double residualPct;

  static double _n(Object? v) =>
      v == null ? 0 : (v is num ? v.toDouble() : double.tryParse('$v') ?? 0);

  factory AdminComparisonModel.fromJson(Map<String, dynamic> j) =>
      AdminComparisonModel(
        provider: j['provider'] as String,
        displayName: j['displayName'] as String? ?? j['provider'] as String,
        productName: j['productName'] as String? ?? '',
        baseFare: _n(j['baseFare']),
        perMile: _n(j['perMile']),
        perMin: _n(j['perMin']),
        bookingFee: _n(j['bookingFee']),
        minFare: _n(j['minFare']),
        calibrated: j['calibrated'] as bool? ?? false,
        residualPct: _n(j['residualPct']),
      );
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

  Future<List<AdminDriver>> drivers({int limit = 100, bool pending = false}) async {
    final res = await _guard(
      () => _dio.get<List<dynamic>>('/admin/drivers', queryParameters: {
        'limit': limit,
        if (pending) 'pending': 'true',
      }),
    );
    return res.data!
        .map((e) => AdminDriver.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Approve or reject a driver's documents (KYC gate for going online).
  Future<void> verifyDriver(String driverId, bool approved) => _guard(
        () => _dio.patch('/admin/drivers/$driverId/verify',
            data: {'docsVerified': approved}),
      );

  Future<List<AdminPromo>> promos() async {
    final res =
        await _guard(() => _dio.get<List<dynamic>>('/admin/promos'));
    return res.data!
        .map((e) => AdminPromo.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> createPromo(Map<String, dynamic> body) => _guard(
        () => _dio.post('/admin/promos', data: body),
      );

  Future<void> setPromoActive(String code, bool active) => _guard(
        () => _dio.patch('/admin/promos/$code', data: {'active': active}),
      );

  Future<List<AdminFare>> fares() async {
    final res = await _guard(() => _dio.get<List<dynamic>>('/admin/fares'));
    return res.data!
        .map((e) => AdminFare.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> updateFare(String tier, Map<String, dynamic> body) => _guard(
        () => _dio.patch('/admin/fares/$tier', data: body),
      );

  Future<AdminSurge> surge() async {
    final res =
        await _guard(() => _dio.get<Map<String, dynamic>>('/admin/surge'));
    return AdminSurge.fromJson(res.data!);
  }

  /// Set (or clear, with 1.0) the global surge override multiplier.
  Future<void> setSurge(double multiplier) => _guard(
        () => _dio.patch('/admin/surge', data: {'multiplier': multiplier}),
      );

  /// Competitor rate cards (Uber/Lyft/Empower) + their calibration status.
  Future<List<AdminComparisonModel>> comparisonModels() async {
    final res =
        await _guard(() => _dio.get<List<dynamic>>('/comparison/models'));
    return res.data!
        .map((e) => AdminComparisonModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Record an observed real competitor fare to calibrate that provider's card.
  Future<void> recordFareSample(Map<String, dynamic> body) => _guard(
        () => _dio.post('/comparison/samples', data: body),
      );

  Future<void> setActive(String userId, bool isActive) => _guard(
        () => _dio.patch('/admin/users/$userId/active', data: {
          'isActive': isActive,
        }),
      );

  /// Live ops snapshot: online drivers + in-flight trips.
  Future<LiveSnapshot> live() async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>('/admin/live'),
    );
    return LiveSnapshot.fromJson(res.data ?? const {});
  }

  /// Support queue (`GET /admin/support/tickets`), optionally filtered.
  Future<List<AdminSupportTicket>> supportTickets({String? status}) async {
    final res = await _guard(
      () => _dio.get<List<dynamic>>('/admin/support/tickets', queryParameters: {
        'status': ?status,
      }),
    );
    return res.data!
        .map((e) => AdminSupportTicket.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// A single ticket's thread (via the shared `/support/tickets/:id` — admins
  /// bypass the ownership check on the backend).
  Future<AdminSupportTicket> supportThread(String id) async {
    final res = await _guard(
      () => _dio.get<Map<String, dynamic>>('/support/tickets/$id'),
    );
    return AdminSupportTicket.fromJson(res.data!);
  }

  /// Post an admin reply; returns the refreshed thread.
  Future<AdminSupportTicket> supportReply(String id, String body) async {
    final res = await _guard(
      () => _dio.post<Map<String, dynamic>>(
        '/support/tickets/$id/messages',
        data: {'body': body},
      ),
    );
    return AdminSupportTicket.fromJson(res.data!);
  }

  /// Change a ticket's status (`PATCH /admin/support/tickets/:id`).
  Future<void> supportSetStatus(String id, String status) => _guard(
        () => _dio.patch('/admin/support/tickets/$id', data: {'status': status}),
      );

  /// Refund a trip's payment (full when [amount] is null).
  Future<void> refund(String tripId, {double? amount, String? reason}) => _guard(
        () => _dio.post('/admin/payments/$tripId/refund', data: {
          'amount': ?amount,
          'reason': ?reason,
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
