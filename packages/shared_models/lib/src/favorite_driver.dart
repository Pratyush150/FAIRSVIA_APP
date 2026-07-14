import 'package:equatable/equatable.dart';

/// A rider's favourite driver (as returned by GET /me/favorites).
class FavoriteDriver extends Equatable {
  const FavoriteDriver({
    required this.driverId,
    this.name,
    this.vehicleModel,
    this.plateNumber,
    this.ratingAvg,
  });

  final String driverId;
  final String? name;
  final String? vehicleModel;
  final String? plateNumber;
  final double? ratingAvg;

  factory FavoriteDriver.fromJson(Map<String, dynamic> json) => FavoriteDriver(
        driverId: json['driverId'] as String,
        name: json['name'] as String?,
        vehicleModel: json['vehicleModel'] as String?,
        plateNumber: json['plateNumber'] as String?,
        ratingAvg: (json['ratingAvg'] as num?)?.toDouble(),
      );

  @override
  List<Object?> get props =>
      [driverId, name, vehicleModel, plateNumber, ratingAvg];
}
