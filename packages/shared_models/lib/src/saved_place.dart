import 'package:equatable/equatable.dart';

import 'geo_point.dart';

/// A rider's saved place (Home / Work / a custom label).
class SavedPlace extends Equatable {
  const SavedPlace({
    required this.id,
    required this.label,
    required this.point,
    this.address,
  });

  final String id;
  final String label;
  final GeoPoint point;
  final String? address;

  factory SavedPlace.fromJson(Map<String, dynamic> json) => SavedPlace(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        point: GeoPoint(
          (json['lat'] as num).toDouble(),
          (json['lng'] as num).toDouble(),
        ),
        address: json['address'] as String?,
      );

  @override
  List<Object?> get props => [id, label, point, address];
}
