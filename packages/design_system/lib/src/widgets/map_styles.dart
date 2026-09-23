/// Google Maps JSON styles applied by [AppMap] per theme brightness.
///
/// Embedded as constants (not assets) so no pubspec/asset wiring is needed and
/// the style ships with the widget.
///
/// Both are quiet greyscale basemaps, the ride-hailing look: the map is
/// context, not content. Roads read as light strokes, water and parks are
/// barely tinted, and business/POI/transit labels and road-number shields are
/// hidden, so the only strong marks on screen are ours — the route, the car,
/// the pickup and drop-off pins.
library;

/// Light mode: pale grey land, white roads, soft grey highways.
const String mapLightStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#f5f5f5"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#6b6b6b"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#f5f5f5"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#9e9e9e"}]},
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#eeeeee"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#e3ebe3"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#7a7a7a"}]},
  {"featureType": "road.arterial", "elementType": "geometry", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#e0e0e0"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#616161"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#9e9e9e"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#d6dde3"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#9e9e9e"}]}
]
''';

/// Dark mode: near-black land, dark grey roads, muted labels — so the map
/// doesn't glow under the light status-bar icons.
const String mapNightStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1c1c1c"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#8a8a8a"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#1c1c1c"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#222222"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1f2620"}]},
  {"featureType": "road", "elementType": "geometry", "stylers": [{"color": "#2e2e2e"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8a8a8a"}]},
  {"featureType": "road.highway", "elementType": "geometry", "stylers": [{"color": "#3d3d3d"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#a0a0a0"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0f141a"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#4e5a66"}]}
]
''';
