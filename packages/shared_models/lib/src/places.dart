import 'package:equatable/equatable.dart';

import 'geo_point.dart';

/// A Places autocomplete suggestion (no coordinates yet).
class PlacePrediction extends Equatable {
  const PlacePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.description,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String description;

  factory PlacePrediction.fromJson(Map<String, dynamic> json) =>
      PlacePrediction(
        placeId: json['placeId'] as String,
        primaryText: json['primaryText'] as String? ?? '',
        secondaryText: json['secondaryText'] as String? ?? '',
        description: json['description'] as String? ?? '',
      );

  @override
  List<Object?> get props => [placeId, primaryText, secondaryText, description];
}

/// Resolved place details: address + coordinates.
class PlaceDetails extends Equatable {
  const PlaceDetails({
    required this.placeId,
    required this.address,
    required this.location,
  });

  final String placeId;
  final String address;
  final GeoPoint location;

  factory PlaceDetails.fromJson(Map<String, dynamic> json) => PlaceDetails(
        placeId: json['placeId'] as String,
        address: json['address'] as String? ?? '',
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
      );

  @override
  List<Object?> get props => [placeId, address, location];
}
