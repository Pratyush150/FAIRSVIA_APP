import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import 'map_styles.dart';

/// What a marker represents — drives its icon + colour.
/// [me] is the rider's own position (blue dot), [driver] the gliding car.
enum MapMarkerKind { pickup, dropoff, driver, me, plain }

/// A point to draw on [AppMap].
class AppMapMarker {
  const AppMapMarker({
    required this.point,
    this.kind = MapMarkerKind.plain,
    this.label,
    this.heading,
  });

  final LatLng point;
  final MapMarkerKind kind;
  final String? label;

  /// Optional compass heading (degrees, 0 = north) for the driver marker. When
  /// null, [AppMap] derives the heading from successive positions.
  final double? heading;
}

/// Shared map built on the **Google Maps SDK**. Public API stays in latlong2
/// [LatLng] (converted internally) so callers don't depend on the maps package.
/// The driver marker **glides** between GPS updates and **rotates** to its travel
/// bearing (like Uber), instead of jumping.
class AppMap extends StatefulWidget {
  const AppMap({
    super.key,
    required this.initialCenter,
    this.initialZoom = 14,
    this.markers = const [],
    this.route = const [],
    this.fitBounds,
    this.onMapReady,
    this.onCenterChanged,
    this.recenter,
    this.recenterSeq = 0,
    this.tileProvider,
    this.boundsPadding = const EdgeInsets.all(64),
  });

  final LatLng initialCenter;
  final double initialZoom;
  final List<AppMapMarker> markers;
  final List<LatLng> route;
  final List<LatLng>? fitBounds;
  final VoidCallback? onMapReady;
  final ValueChanged<LatLng>? onCenterChanged;
  /// Camera target to snap to. The camera moves when this point changes OR
  /// when [recenterSeq] changes — see [recenterSeq].
  final LatLng? recenter;

  /// Monotonic request token for [recenter]. [LatLng] has value equality, so
  /// re-supplying the same point (a "recenter on me" tap while the GPS fix
  /// hasn't moved — always the case with a mocked location) is otherwise
  /// indistinguishable from no request at all. Bump this on every explicit
  /// request; callers that only follow a moving point can leave it at 0.
  final int recenterSeq;

  /// Retained for source compatibility with the old flutter_map backend. Ignored.
  final Object? tileProvider;

  final EdgeInsets boundsPadding;

  /// Whether a rebuild from [old] to [next] carries a recenter request the
  /// camera should honour. A request is suppressed while [fitBounds] frames
  /// two or more points (the fit owns the camera then).
  @visibleForTesting
  static bool recenterChanged(AppMap old, AppMap next) =>
      next.recenter != null &&
      (next.recenter != old.recenter || next.recenterSeq != old.recenterSeq) &&
      (next.fitBounds == null || next.fitBounds!.length < 2);

  @override
  State<AppMap> createState() => _AppMapState();
}

gmaps.LatLng _g(LatLng p) => gmaps.LatLng(p.latitude, p.longitude);

class _AppMapState extends State<AppMap> with SingleTickerProviderStateMixin {
  final Completer<gmaps.GoogleMapController> _controller = Completer();
  gmaps.LatLng? _lastCameraTarget;

  // --- Driver-marker interpolation (the smooth "gliding car") ---
  late final AnimationController _driverAnim;
  LatLng? _driverFrom; // where the car is gliding from
  LatLng? _driverTo; // ...to (the latest GPS fix)
  double _driverBearing = 0;
  gmaps.BitmapDescriptor? _driverIcon; // custom car puck, generated once
  gmaps.BitmapDescriptor? _meIcon; // rider's blue "you are here" dot

  @override
  void initState() {
    super.initState();
    _driverAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..addListener(() {
        if (mounted) setState(() {}); // redraw the gliding car each tick
      });
    final initialDriver = _driverMarker(widget.markers)?.point;
    _driverFrom = initialDriver;
    _driverTo = initialDriver;
    _makeDriverIcon();
    _makeMeIcon();
  }

  @override
  void dispose() {
    _driverAnim.dispose();
    super.dispose();
  }

  AppMapMarker? _driverMarker(List<AppMapMarker> ms) {
    for (final m in ms) {
      if (m.kind == MapMarkerKind.driver) return m;
    }
    return null;
  }

  @override
  void didUpdateWidget(AppMap old) {
    super.didUpdateWidget(old);
    if (!_sameBounds(old.fitBounds, widget.fitBounds)) {
      _fit();
    }
    if (AppMap.recenterChanged(old, widget)) {
      _moveTo(widget.recenter!);
    }
    // Animate the driver from its current (possibly mid-glide) position to the
    // new GPS fix, and rotate toward the direction of travel.
    final next = _driverMarker(widget.markers)?.point;
    final prevTarget = _driverTo;
    if (next != null &&
        (prevTarget == null ||
            next.latitude != prevTarget.latitude ||
            next.longitude != prevTarget.longitude)) {
      final from = _currentDriverPoint() ?? next;
      if (_distanceMeters(from, next) > 1.0) {
        _driverBearing = _driverMarker(widget.markers)?.heading ??
            _bearing(from, next);
      }
      _driverFrom = from;
      _driverTo = next;
      _driverAnim
        ..reset()
        ..forward();
    } else if (next == null) {
      _driverFrom = null;
      _driverTo = null;
    }
  }

  /// The driver's on-screen point right now (interpolated mid-glide).
  LatLng? _currentDriverPoint() {
    final a = _driverFrom, b = _driverTo;
    if (a == null || b == null) return null;
    final t = _driverAnim.isAnimating ? _driverAnim.value : 1.0;
    return LatLng(
      a.latitude + (b.latitude - a.latitude) * t,
      a.longitude + (b.longitude - a.longitude) * t,
    );
  }

  Future<void> _moveTo(LatLng center) async {
    final c = await _controller.future;
    if (!mounted) return;
    // Recenter also restores a street-level zoom: after a route fit the camera
    // is zoomed out over the whole trip, and "recenter" without a zoom left
    // the rider looking at the entire city.
    await c.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(_g(center), widget.initialZoom),
    );
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

  Future<void> _fit() async {
    final pts = widget.fitBounds;
    if (pts == null || pts.length < 2) return;
    final c = await _controller.future;
    if (!mounted) return;
    await c.animateCamera(
      gmaps.CameraUpdate.newLatLngBounds(_boundsOf(pts), 56),
    );
  }

  gmaps.LatLngBounds _boundsOf(List<LatLng> pts) {
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < minLat) minLat = p.latitude;
      if (p.latitude > maxLat) maxLat = p.latitude;
      if (p.longitude < minLng) minLng = p.longitude;
      if (p.longitude > maxLng) maxLng = p.longitude;
    }
    return gmaps.LatLngBounds(
      southwest: gmaps.LatLng(minLat, minLng),
      northeast: gmaps.LatLng(maxLat, maxLng),
    );
  }

  Set<gmaps.Marker> _buildMarkers() {
    final out = <gmaps.Marker>{};
    var i = 0;
    for (final m in widget.markers) {
      final isDriver = m.kind == MapMarkerKind.driver;
      // The driver marker uses the interpolated (gliding) point + travel bearing;
      // everything else is static.
      final point = isDriver ? (_currentDriverPoint() ?? m.point) : m.point;
      final isMe = m.kind == MapMarkerKind.me;
      final icon = isDriver && _driverIcon != null
          ? _driverIcon!
          : isMe && _meIcon != null
              ? _meIcon!
              : _iconFor(m.kind);
      out.add(gmaps.Marker(
        markerId: gmaps.MarkerId('${m.kind.name}_${i++}'),
        position: _g(point),
        icon: icon,
        anchor:
            (isDriver || isMe || m.kind == MapMarkerKind.pickup)
                ? const Offset(0.5, 0.5)
                : const Offset(0.5, 1.0),
        zIndexInt: isDriver ? 3 : (isMe ? 2 : 1),
        rotation: isDriver ? _driverBearing : (m.heading ?? 0),
        flat: isDriver,
        infoWindow: m.label != null
            ? gmaps.InfoWindow(title: m.label)
            : gmaps.InfoWindow.noText,
      ));
    }
    return out;
  }

  gmaps.BitmapDescriptor _iconFor(MapMarkerKind kind) {
    switch (kind) {
      case MapMarkerKind.pickup:
        return gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueGreen);
      case MapMarkerKind.dropoff:
        return gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRed);
      case MapMarkerKind.driver:
      case MapMarkerKind.me:
        return gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueAzure);
      case MapMarkerKind.plain:
        return gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRose);
    }
  }

  Set<gmaps.Polyline> _buildPolylines() {
    if (widget.route.length < 2) return const {};
    return {
      gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route'),
        points: [for (final p in widget.route) _g(p)],
        color: AppColors.accent,
        width: 5,
      ),
    };
  }

  /// Render a white circular "puck" with a dark navigation arrow to a bitmap,
  /// once — the Uber-style vehicle marker that rotates to the travel bearing.
  /// Falls back to the default marker if rendering fails.
  Future<void> _makeDriverIcon() async {
    try {
      const dim = 108.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final center = const Offset(dim / 2, dim / 2);
      // soft shadow
      canvas.drawCircle(
        center,
        36,
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // white disc + dark ring
      canvas.drawCircle(center, 32, Paint()..color = Colors.white);
      canvas.drawCircle(
        center,
        32,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = const Color(0xFF10121A),
      );
      // navigation arrow glyph (points "up" = the marker's 0°/north, then the
      // marker rotation aims it along the bearing)
      final tp = TextPainter(textDirection: TextDirection.ltr)
        ..text = TextSpan(
          text: String.fromCharCode(Icons.navigation_rounded.codePoint),
          style: TextStyle(
            fontSize: 38,
            fontFamily: Icons.navigation_rounded.fontFamily,
            package: Icons.navigation_rounded.fontPackage,
            color: const Color(0xFF10121A),
          ),
        )
        ..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));

      final img =
          await recorder.endRecording().toImage(dim.toInt(), dim.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      // The bitmap is rasterised at 108 px for crispness; without an explicit
      // logical size the SDK draws it 1:1 in points (108 pt — ~4x a default
      // marker). `width` scales it to ~36 pt on both platforms, keeping the
      // aspect ratio (the source is square).
      final icon = gmaps.BitmapDescriptor.bytes(bytes, width: 36);
      if (mounted) setState(() => _driverIcon = icon);
    } catch (_) {
      // Keep the default azure marker if custom rendering fails on a device.
    }
  }

  /// Uber-style "you are here" dot: blue disc, white ring, soft halo.
  Future<void> _makeMeIcon() async {
    try {
      const dim = 72.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const center = Offset(dim / 2, dim / 2);
      canvas.drawCircle(center, 34, Paint()..color = const Color(0x334285F4));
      canvas.drawCircle(center, 15, Paint()..color = Colors.white);
      canvas.drawCircle(center, 11, Paint()..color = const Color(0xFF4285F4));
      final img =
          await recorder.endRecording().toImage(dim.toInt(), dim.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final icon =
          gmaps.BitmapDescriptor.bytes(data.buffer.asUint8List(), width: 24);
      if (mounted) setState(() => _meIcon = icon);
    } catch (_) {
      // Fall back to the default marker.
    }
  }

  double _bearing(LatLng a, LatLng b) {
    final lat1 = a.latitude * math.pi / 180;
    final lat2 = b.latitude * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dLon) * math.cos(lat2);
    final x = math.cos(lat1) * math.sin(lat2) -
        math.sin(lat1) * math.cos(lat2) * math.cos(dLon);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _distanceMeters(LatLng a, LatLng b) {
    const r = 6371000.0;
    final dLat = (b.latitude - a.latitude) * math.pi / 180;
    final dLon = (b.longitude - a.longitude) * math.pi / 180;
    final la1 = a.latitude * math.pi / 180, la2 = b.latitude * math.pi / 180;
    final h = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(la1) * math.cos(la2) * math.sin(dLon / 2) * math.sin(dLon / 2);
    return 2 * r * math.asin(math.min(1.0, math.sqrt(h)));
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: _g(widget.initialCenter),
        zoom: widget.initialZoom,
      ),
      // Themed basemap: a night style in dark mode (so the map doesn't glow
      // white under light status-bar icons) and a de-cluttered light style.
      style: dark ? mapNightStyle : mapLightStyle,
      markers: _buildMarkers(),
      polylines: _buildPolylines(),
      padding: widget.boundsPadding,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      onMapCreated: (c) {
        if (!_controller.isCompleted) _controller.complete(c);
        _fit();
        widget.onMapReady?.call();
      },
      onCameraMove: widget.onCenterChanged == null
          ? null
          : (pos) => _lastCameraTarget = pos.target,
      onCameraIdle: widget.onCenterChanged == null
          ? null
          : () {
              final t = _lastCameraTarget;
              if (t != null) {
                widget.onCenterChanged!(LatLng(t.latitude, t.longitude));
              }
            },
    );
  }
}
