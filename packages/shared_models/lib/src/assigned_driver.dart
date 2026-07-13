import 'package:equatable/equatable.dart';

/// Driver + vehicle details shown to the rider once matched (`trip:accepted`).
class AssignedDriver extends Equatable {
  const AssignedDriver({
    required this.name,
    required this.rating,
    this.vehicleMake,
    this.vehicleModel,
    this.vehicleColor,
    this.plate,
  });

  final String name;
  final double rating;
  final String? vehicleMake;
  final String? vehicleModel;
  final String? vehicleColor;
  final String? plate;

  String get vehicleLabel => [
        if (vehicleColor != null) vehicleColor,
        vehicleMake,
        vehicleModel,
      ].whereType<String>().join(' ');

  factory AssignedDriver.fromAcceptedEvent(Map<String, dynamic> json) {
    final driver = (json['driver'] as Map?)?.cast<String, dynamic>() ?? {};
    final vehicle = (json['vehicle'] as Map?)?.cast<String, dynamic>() ?? {};
    return AssignedDriver(
      name: driver['name'] as String? ?? 'Your driver',
      rating: (driver['rating'] as num?)?.toDouble() ?? 5.0,
      vehicleMake: vehicle['make'] as String?,
      vehicleModel: vehicle['model'] as String?,
      vehicleColor: vehicle['color'] as String?,
      plate: vehicle['plate'] as String?,
    );
  }

  @override
  List<Object?> get props =>
      [name, rating, vehicleMake, vehicleModel, vehicleColor, plate];
}
