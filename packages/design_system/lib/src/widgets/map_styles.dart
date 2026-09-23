/// Google Maps JSON styles applied by [AppMap] per theme brightness.
///
/// Embedded as constants (not assets) so no pubspec/asset wiring is needed and
/// the style ships with the widget.
///
/// Quiet but legible: neutral land, clearly drawn roads with readable names,
/// parks in a soft green and water in a turquoise tint that echoes the brand.
/// Business/POI/transit labels and road-number shields are hidden, so the
/// strongest marks on screen are ours — the route, the car, the pickup and
/// drop-off pins.
library;

/// Light mode: light grey land, white roads with a grey edge, darker labels.
const String mapLightStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#eceef0"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#4a4f55"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#ffffff"}, {"weight": 3}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#2b3035"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#6b7178"}]},
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#e3e6e8"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#d2e8d4"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#d3d7db"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#5a6066"}]},
  {"featureType": "road.arterial", "elementType": "geometry.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#fdfdfd"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#bfc5ca"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#3d4247"}]},
  {"featureType": "road.local", "elementType": "labels.text.fill", "stylers": [{"color": "#7a8087"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#b3dfe2"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#3f8b90"}]}
]
''';

/// Dark mode: charcoal land, roads clearly lighter than the land, readable
/// labels, deep-teal water — so the map doesn't glow, yet streets are easy
/// to follow.
const String mapNightStyle = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1a1e21"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#b3bbc2"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#1a1e21"}, {"weight": 3}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d6dde2"}]},
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.business", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#20252a"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1c2e23"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#3a4147"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#2a3035"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#a7afb6"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#4f575e"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#d0d6db"}]},
  {"featureType": "road.local", "elementType": "geometry.fill", "stylers": [{"color": "#343a40"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0d3a3e"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#5fb3b8"}]}
]
''';
