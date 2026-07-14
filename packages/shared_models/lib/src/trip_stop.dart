import 'package:equatable/equatable.dart';

import 'geo_point.dart';

/// An intermediate stop on a multi-stop trip (pickup → stops… → dropoff).
/// Serializes to the backend shape `{lat, lng, addr?}`.
class TripStop extends Equatable {
  const TripStop({required this.point, this.address});

  final GeoPoint point;
  final String? address;

  factory TripStop.fromJson(Map<String, dynamic> json) => TripStop(
        point: GeoPoint(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        address: json['addr'] as String? ?? json['address'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'lat': point.lat,
        'lng': point.lng,
        if (address != null) 'addr': address,
      };

  @override
  List<Object?> get props => [point, address];
}
