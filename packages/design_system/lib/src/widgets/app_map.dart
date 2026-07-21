import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';

// Polished map styling via MapTiler when a key is supplied
// (--dart-define=MAPTILER_KEY=xxx, optionally MAPTILER_STYLE=streets-v2|
// satellite|dataviz-dark|...). Without a key the map falls back to plain
// OpenStreetMap tiles, so the app still renders a real map with no config.
const String _maptilerKey = String.fromEnvironment('MAPTILER_KEY');
const String _maptilerStyle =
    String.fromEnvironment('MAPTILER_STYLE', defaultValue: 'streets-v2');

/// The active raster tile URL template. MapTiler when keyed, else OSM.
String get _tileUrlTemplate => _maptilerKey.isNotEmpty
    ? 'https://api.maptiler.com/maps/$_maptilerStyle/{z}/{x}/{y}.png?key=$_maptilerKey'
    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

/// What a marker represents — drives its icon + colour.
enum MapMarkerKind { pickup, dropoff, driver, plain }

/// A point to draw on [AppMap].
class AppMapMarker {
  const AppMapMarker({
    required this.point,
    this.kind = MapMarkerKind.plain,
    this.label,
  });

  final LatLng point;
  final MapMarkerKind kind;
  final String? label;
}

/// Shared map built on OpenStreetMap tiles via flutter_map — no API key needed,
/// renders on mobile and web alike. Wraps tiles + an optional route polyline +
/// markers, and (when [fitBounds] is supplied) fits the camera to those points.
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14,
    this.markers = const [],
    this.route = const [],
    this.fitBounds,
    this.onMapReady,
    this.tileProvider,
  });

  final LatLng initialCenter;
  final double initialZoom;
  final List<AppMapMarker> markers;

  /// Decoded route to draw as a polyline (empty = none).
  final List<LatLng> route;

  /// When set (and containing ≥2 points), the camera fits to these on build and
  /// whenever the list changes — e.g. [pickup, dropoff] on the estimate screen.
  final List<LatLng>? fitBounds;

  final VoidCallback? onMapReady;

  /// Overrides the tile source (defaults to OSM over the network). Injected in
  /// tests with an offline provider so no network is touched.
  final TileProvider? tileProvider;

  @override
  State<AppMap> createState() => _AppMapState();
}

class _AppMapState extends State<AppMap> {
  final MapController _controller = MapController();

  @override
  void didUpdateWidget(AppMap old) {
    super.didUpdateWidget(old);
    if (!_sameBounds(old.fitBounds, widget.fitBounds)) {
      _fit();
    }
  }

  bool _sameBounds(List<LatLng>? a, List<LatLng>? b) {
    if (a == null || b == null) return a == b;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].latitude != b[i].latitude || a[i].longitude != b[i].longitude) {
        return false;
      }
    }
    return true;
  }

  void _fit() {
    final pts = widget.fitBounds;
    if (pts == null || pts.length < 2) return;
    // Defer to after the frame so the map has a size to fit within.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _controller.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pts),
          padding: const EdgeInsets.all(64),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return FlutterMap(
      mapController: _controller,
      options: MapOptions(
        initialCenter: widget.initialCenter,
        initialZoom: widget.initialZoom,
        minZoom: 3,
        maxZoom: 19,
        interactionOptions: const InteractionOptions(
          // Pan + pinch-zoom, but no rotation (keeps north up, simpler UX).
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
        onMapReady: () {
          _fit();
          widget.onMapReady?.call();
        },
      ),
      children: [
        TileLayer(
          urlTemplate: _tileUrlTemplate,
          // OSM tile-usage policy asks for an identifying UA (MapTiler is fine
          // with it too).
          userAgentPackageName: 'in.novarobotics.ubernav',
          maxZoom: 19,
          tileProvider: widget.tileProvider,
        ),
        if (widget.route.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: widget.route,
                color: AppColors.accent,
                strokeWidth: 5,
              ),
            ],
          ),
        MarkerLayer(
          markers: [
            for (final m in widget.markers)
              Marker(
                point: m.point,
                width: 44,
                height: 44,
                // Anchor each glyph on its coordinate correctly: teardrop pins
                // (dropoff/plain, an Icons.location_on) touch the point with
                // their bottom tip; the round pickup dot and the moving car sit
                // CENTERED on the point, so the car tracks the route line
                // instead of floating beside it.
                alignment: (m.kind == MapMarkerKind.dropoff ||
                        m.kind == MapMarkerKind.plain)
                    ? Alignment.bottomCenter
                    : Alignment.center,
                child: _MarkerPin(kind: m.kind),
              ),
          ],
        ),
      ],
    );
  }
}

class _MarkerPin extends StatelessWidget {
  const _MarkerPin({required this.kind});
  final MapMarkerKind kind;

  @override
  Widget build(BuildContext context) {
    switch (kind) {
      case MapMarkerKind.pickup:
        return const Icon(Icons.trip_origin, color: AppColors.accent, size: 26);
      case MapMarkerKind.dropoff:
        return const Icon(Icons.location_on, color: Color(0xFF2E7D32), size: 40);
      case MapMarkerKind.driver:
        return const Icon(Icons.local_taxi, color: Color(0xFF1565C0), size: 34);
      case MapMarkerKind.plain:
        return const Icon(Icons.location_on, color: AppColors.accent, size: 40);
    }
  }
}
