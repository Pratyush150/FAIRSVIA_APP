import 'package:equatable/equatable.dart';

import 'geo_point.dart';

/// A Places autocomplete suggestion (no coordinates yet).
class PlacePrediction extends Equatable {
  const PlacePrediction({
    required this.placeId,
    required this.primaryText,
    required this.secondaryText,
    required this.description,
    this.distanceM,
  });

  final String placeId;
  final String primaryText;
  final String secondaryText;
  final String description;

  /// Straight-line metres from the rider's position sent with the search
  /// (`lat`/`lng`), when the backend/provider reported it. Null otherwise.
  final int? distanceM;

  factory PlacePrediction.fromJson(Map<String, dynamic> json) =>
      PlacePrediction(
        placeId: json['placeId'] as String,
        primaryText: json['primaryText'] as String? ?? '',
        secondaryText: json['secondaryText'] as String? ?? '',
        description: json['description'] as String? ?? '',
        distanceM: (json['distanceM'] as num?)?.round(),
      );

  /// Nearest first — but only when *every* prediction carries a distance.
  /// Google's location bias is soft, so a partially-known list is left in the
  /// provider's relevance order rather than pushing unknowns to the bottom.
  /// Stable: equal distances keep their incoming order.
  static List<PlacePrediction> sortedByDistance(List<PlacePrediction> list) {
    if (list.length < 2 || list.any((p) => p.distanceM == null)) return list;
    final indexed = list.indexed.toList()
      ..sort((a, b) {
        final byDistance = a.$2.distanceM!.compareTo(b.$2.distanceM!);
        return byDistance != 0 ? byDistance : a.$1.compareTo(b.$1);
      });
    return [for (final (_, p) in indexed) p];
  }

  @override
  List<Object?> get props =>
      [placeId, primaryText, secondaryText, description, distanceM];
}

/// Resolved place details: address + coordinates.
///
/// Reverse-geocode responses also carry a short [label] (landmark / building /
/// road, never a house number or plus code — "Mote Mangal Karyalay Rd") and a
/// [detail] caption (locality + city — "Dattwadi, Pune"). Both are optional:
/// older backends and place-details lookups send only [address]. Display code
/// should use [title] / [caption] / [shortAddress], which fall back to
/// [address] when there is no label.
class PlaceDetails extends Equatable {
  const PlaceDetails({
    required this.placeId,
    required this.address,
    required this.location,
    this.label,
    this.detail,
  });

  final String placeId;

  /// The provider's full address. Kept as-is for backwards compatibility.
  final String address;
  final GeoPoint location;

  /// Short name for the main line, when the backend supplied one.
  final String? label;

  /// Short caption under [label], when the backend supplied one.
  final String? detail;

  bool get _hasLabel => label != null && label!.trim().isNotEmpty;

  /// Main line: the short label, else the full address.
  String get title => _hasLabel ? label!.trim() : address;

  /// Caption under [title]; empty when there is no label (the title is then
  /// already the full address) or no detail.
  String get caption => _hasLabel ? (detail ?? '').trim() : '';

  /// One-line form for places that hold a single string (trip pickup/dropoff,
  /// text fields): "Mote Mangal Karyalay Rd, Dattwadi, Pune".
  String get shortAddress =>
      caption.isEmpty ? title : '$title, $caption';

  factory PlaceDetails.fromJson(Map<String, dynamic> json) => PlaceDetails(
        placeId: json['placeId'] as String? ?? '',
        address: json['address'] as String? ?? '',
        location: GeoPoint.fromJson(json['location'] as Map<String, dynamic>),
        label: json['label'] as String?,
        detail: json['detail'] as String?,
      );

  @override
  List<Object?> get props => [placeId, address, location, label, detail];
}
