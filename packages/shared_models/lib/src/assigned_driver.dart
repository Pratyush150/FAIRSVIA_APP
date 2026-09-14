import 'package:equatable/equatable.dart';

/// Driver + vehicle details shown to the rider once matched (`trip:accepted`).
class AssignedDriver extends Equatable {
  const AssignedDriver({
    required this.name,
    required this.rating,
    this.id,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.plate,
    this.phone,
    this.etaSec,
    this.etaDistanceM,
  });

  /// The driver's user id (used to favourite them). Null on older payloads.
  final String? id;
  final String name;
  final double rating;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? plate;

  /// The driver's phone number for the rider's "Call" action. Null when the
  /// backend doesn't include it (older payloads / privacy-masked builds), in
  /// which case the UI hides the button rather than dialling nothing.
  final String? phone;

  /// Live driver→pickup ETA (seconds) and distance (metres) from the backend's
  /// approach route at match time. Null when the driver's position was unknown
  /// or routing failed, so the UI simply omits the countdown rather than lying.
  final int? etaSec;
  final int? etaDistanceM;

  String get vehicleLabel => [
        if (vehicleColor != null) vehicleColor,
        vehicleMake,
        vehicleModel,
      ].whereType<String>().join(' ');

  /// "Arriving in N min" when an ETA is known, else null (caller falls back to a
  /// generic status like "On the way"). Rounds up so a 10s ETA reads "1 min".
  String? get etaLabel {
    final s = etaSec;
    if (s == null || s <= 0) return null;
    final mins = (s / 60).ceil();
    return 'Arriving in $mins min';
  }

  factory AssignedDriver.fromAcceptedEvent(Map<String, dynamic> json) {
    final driver = (json['driver'] as Map?)?.cast<String, dynamic>() ?? {};
    final vehicle = (json['vehicle'] as Map?)?.cast<String, dynamic>() ?? {};
    return AssignedDriver(
      id: driver['id'] as String?,
      name: driver['name'] as String? ?? 'Your driver',
      rating: (driver['rating'] as num?)?.toDouble() ?? 5.0,
      vehicleMake: vehicle['make'] as String?,
      vehicleModel: vehicle['model'] as String?,
      vehicleColor: vehicle['color'] as String?,
      plate: vehicle['plate'] as String?,
      phone: _nonEmpty(driver['phone'] as String?),
      etaSec: (json['etaSec'] as num?)?.toInt(),
      etaDistanceM: (json['etaDistanceM'] as num?)?.toInt(),
    );
  }

  static String? _nonEmpty(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  @override
  List<Object?> get props => [
        id,
        name,
        rating,
        vehicleMake,
        vehicleModel,
        vehicleColor,
        plate,
        phone,
        etaSec,
        etaDistanceM,
      ];
}
