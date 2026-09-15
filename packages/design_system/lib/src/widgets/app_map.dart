import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import 'route_progress.dart';

/// What a marker represents — drives its icon + colour.
enum MapMarkerKind { pickup, dropoff, driver, plain }

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
    this.recenterTrigger = 0,
    this.recenterZoom,
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
  final LatLng? recenter;

  /// Bump this to force a re-center on [recenter] even when its value is
  /// unchanged — so a "locate me" button works on every tap, not only when the
  /// resolved position differs from last time.
  final int recenterTrigger;

  /// When set, a recenter also zooms to this level (a precise "locate me").
  /// Null keeps the current zoom.
  final double? recenterZoom;

  /// Retained for source compatibility with the old flutter_map backend. Ignored.
  final Object? tileProvider;

  final EdgeInsets boundsPadding;

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

  // Cached route polylines. Recomputing the route split (an O(route) scan) plus
  // copying the whole line on every animation frame janks on mid-range phones,
  // so we rebuild the line only when the route changes or the car has moved
  // enough. The marker still glides at full frame rate; only the (expensive)
  // line recompute is throttled by distance.
  Set<gmaps.Polyline> _polylines = const {};
  LatLng? _polyDriverAt; // interpolated car point the cache was built for
  bool _polyHadDriver = false;
  int _polyRouteLen = -1; // length + endpoints cheaply identify a route change
  LatLng? _polyRouteFirst;
  LatLng? _polyRouteLast;
  static const double _polyResampleMeters = 3.0;

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
    if (widget.recenter != null &&
        (widget.recenter != old.recenter ||
            widget.recenterTrigger != old.recenterTrigger) &&
        (widget.fitBounds == null || widget.fitBounds!.length < 2)) {
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
    final z = widget.recenterZoom;
    await c.animateCamera(
      z != null
          ? gmaps.CameraUpdate.newLatLngZoom(_g(center), z)
          : gmaps.CameraUpdate.newLatLng(_g(center)),
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

  // Pixels of breathing room left around a fitted bounds.
  static const double _boundsPixelPadding = 56;
  // Below this diagonal span the two framed points are effectively on top of
  // each other (the car has nearly reached its target); a bounds-fit would
  // over-zoom or throw, so we centre + hold a street-level zoom instead.
  static const double _minFitSpanMeters = 180;
  static const double _closeZoom = 16.8;

  // The bounds we last animated the camera to. Re-fitting on every GPS tick
  // makes the map re-project constantly (a jank source); we skip a re-fit when
  // the framed points barely moved and only follow once an endpoint shifts
  // more than [_refitThresholdMeters] — a throttled "camera director".
  List<LatLng>? _lastFittedBounds;
  static const double _refitThresholdMeters = 20;

  Future<void> _fit() async {
    final pts = widget.fitBounds;
    if (pts == null || pts.length < 2) return;
    // Throttle the follow: don't re-fit for sub-20m movements.
    if (_lastFittedBounds != null &&
        _boundsClose(pts, _lastFittedBounds!, _refitThresholdMeters)) {
      return;
    }
    final c = await _controller.future;
    if (!mounted) return;
    _lastFittedBounds = List<LatLng>.of(pts);
    // Car almost at its target: settle on the point at street zoom rather than
    // snapping to an over-tight bounds (keeps the "zoom in on arrival" smooth).
    if (_spanMeters(pts) < _minFitSpanMeters) {
      await c.animateCamera(
        gmaps.CameraUpdate.newLatLngZoom(_g(_centroid(pts)), _closeZoom),
      );
      return;
    }
    await c.animateCamera(
      gmaps.CameraUpdate.newLatLngBounds(_boundsOf(pts), _boundsPixelPadding),
    );
  }

  /// True when every point of [a] is within [m] metres of the matching point
  /// of [b] (same length assumed) — i.e. the framing barely changed.
  bool _boundsClose(List<LatLng> a, List<LatLng> b, double m) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (_distanceMeters(a[i], b[i]) > m) return false;
    }
    return true;
  }

  /// Diagonal span of the points' bounding box, in metres.
  double _spanMeters(List<LatLng> pts) {
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    return _distanceMeters(LatLng(minLat, minLng), LatLng(maxLat, maxLng));
  }

  LatLng _centroid(List<LatLng> pts) {
    var lat = 0.0, lng = 0.0;
    for (final p in pts) {
      lat += p.latitude;
      lng += p.longitude;
    }
    return LatLng(lat / pts.length, lng / pts.length);
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
      final icon = isDriver && _driverIcon != null
          ? _driverIcon!
          : _iconFor(m.kind);
      out.add(gmaps.Marker(
        markerId: gmaps.MarkerId('${m.kind.name}_${i++}'),
        position: _g(point),
        icon: icon,
        anchor:
            (isDriver || m.kind == MapMarkerKind.pickup)
                ? const Offset(0.5, 0.5)
                : const Offset(0.5, 1.0),
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
        return gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueAzure);
      case MapMarkerKind.plain:
        return gmaps.BitmapDescriptor.defaultMarkerWithHue(
            gmaps.BitmapDescriptor.hueRose);
    }
  }

  /// Muted colour for the portion of the route the car has already driven.
  static const gmaps.Cap _roundCap = gmaps.Cap.roundCap;
  static final Color _routeDone = const Color(0xFF9AA0A6); // faded grey
  // Within this distance of the leg's end the line is treated as finished and
  // cleared entirely, so it vanishes exactly on arrival rather than leaving a stub.
  static const double _arrivedMeters = 12;

  /// The route line. When a live driver marker is present we **split the route
  /// at the car** and draw only the part *ahead* of it in bold — so the active
  /// line shrinks behind the car as it drives and vanishes on arrival (Uber
  /// style). The already-driven part is drawn faintly. Without a driver we draw
  /// the whole route as one bold line.
  /// Rebuild [_polylines] only when the route changed, the driver appeared or
  /// vanished, or the car moved past [_polyResampleMeters] — keeping the
  /// per-frame build path cheap while the marker glides smoothly.
  void _syncPolylines() {
    final route = widget.route;
    final driver = _currentDriverPoint();
    final hasDriver = driver != null;
    final routeChanged = route.length != _polyRouteLen ||
        (route.isNotEmpty &&
            (route.first != _polyRouteFirst || route.last != _polyRouteLast));
    final moved = hasDriver &&
        (_polyDriverAt == null ||
            _distanceMeters(driver, _polyDriverAt!) > _polyResampleMeters);
    if (!routeChanged && !moved && hasDriver == _polyHadDriver) return;
    _polyRouteLen = route.length;
    _polyRouteFirst = route.isEmpty ? null : route.first;
    _polyRouteLast = route.isEmpty ? null : route.last;
    _polyDriverAt = driver;
    _polyHadDriver = hasDriver;
    _polylines = _computePolylines(route, driver);
  }

  Set<gmaps.Polyline> _computePolylines(List<LatLng> route, LatLng? driver) {
    if (route.length < 2) return const {};
    if (driver == null) {
      return {
        gmaps.Polyline(
          polylineId: const gmaps.PolylineId('route'),
          points: [for (final p in route) _g(p)],
          color: AppColors.accent,
          width: 6,
          startCap: _roundCap,
          endCap: _roundCap,
          jointType: gmaps.JointType.round,
        ),
      };
    }

    final split = splitRouteAtPoint(route, driver);
    // The car has effectively reached the end of this leg — the line "finishes":
    // drop both the remaining line AND the faint travelled trail so nothing
    // lingers at the destination (matches Uber, where the route clears on arrival).
    if (split.remainingMeters < _arrivedMeters) return const {};
    final out = <gmaps.Polyline>{};
    if (split.traveled.length >= 2) {
      out.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route_done'),
        points: [for (final p in split.traveled) _g(p)],
        color: _routeDone.withValues(alpha: 0.5),
        width: 5,
        startCap: _roundCap,
        endCap: _roundCap,
        jointType: gmaps.JointType.round,
      ));
    }
    if (split.remaining.length >= 2) {
      out.add(gmaps.Polyline(
        polylineId: const gmaps.PolylineId('route'),
        points: [for (final p in split.remaining) _g(p)],
        color: AppColors.accent,
        width: 6,
        startCap: _roundCap,
        endCap: _roundCap,
        jointType: gmaps.JointType.round,
      ));
    }
    return out;
  }

  /// Render a **top-down car** to a bitmap, once — the Uber-style vehicle marker
  /// that points "up" (the marker's 0°/north) so [AppMap]'s marker rotation aims
  /// it along the travel bearing. A white halo + soft shadow keep it legible on
  /// any map colour. Falls back to the default marker if rendering fails.
  Future<void> _makeDriverIcon() async {
    try {
      const dim = 120.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final cx = dim / 2, cy = dim / 2;
      final center = Offset(cx, cy);
      const bodyW = 42.0, bodyH = 82.0;
      const hh = bodyH / 2, hw = bodyW / 2;

      RRect rr(double w, double h, double r, [Offset d = Offset.zero]) =>
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: center + d, width: w, height: h),
            Radius.circular(r),
          );

      // A trapezoid glass pane (wider toward the cabin), y measured from centre.
      ui.Path pane(double topY, double topHalf, double botY, double botHalf) =>
          ui.Path()
            ..moveTo(cx - topHalf, cy + topY)
            ..lineTo(cx + topHalf, cy + topY)
            ..lineTo(cx + botHalf, cy + botY)
            ..lineTo(cx - botHalf, cy + botY)
            ..close();

      // Soft drop shadow.
      canvas.drawRRect(
        rr(bodyW + 4, bodyH + 4, 16, const Offset(0, 3)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.28)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // White halo so the car reads on dark roads / water.
      canvas.drawRRect(rr(bodyW + 7, bodyH + 7, 18), Paint()..color = Colors.white);

      // Headlights (front) + taillights (rear) — drawn under the body so the
      // body's rounded corners crop them into the car's nose/tail.
      final head = Paint()..color = const Color(0xFFFFF4D6);
      canvas.drawRRect(rr(9, 7, 3, Offset(-hw + 8, -hh + 4)), head);
      canvas.drawRRect(rr(9, 7, 3, Offset(hw - 8, -hh + 4)), head);
      final tail = Paint()..color = const Color(0xFFFF4D4D);
      canvas.drawRRect(rr(9, 6, 3, Offset(-hw + 8, hh - 4)), tail);
      canvas.drawRRect(rr(9, 6, 3, Offset(hw - 8, hh - 4)), tail);

      // Side mirrors.
      final mirror = Paint()..color = const Color(0xFF2A3346);
      canvas.drawRRect(rr(6, 9, 2.5, const Offset(-hw - 1, -10)), mirror);
      canvas.drawRRect(rr(6, 9, 2.5, const Offset(hw + 1, -10)), mirror);

      // Glossy metallic body (vertical gradient, lighter at the roofline).
      canvas.drawRRect(
        rr(bodyW, bodyH, 15),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, cy - hh),
            Offset(cx, cy + hh),
            const [Color(0xFF3A445C), Color(0xFF141A26)],
          ),
      );

      // Cabin roof (a subtle darker inset between the two windows).
      canvas.drawRRect(
        rr(bodyW - 11, 30, 8),
        Paint()..color = const Color(0xFF20283A),
      );
      // Windshield (front = direction of travel) — bright glass, wider toward
      // the cabin; rear window is dimmer.
      canvas.drawPath(
        pane(-15, 10, -4, 14),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(cx, cy - 15),
            Offset(cx, cy - 4),
            const [Color(0xFFCFE0FF), Color(0xFF9DBBF2)],
          ),
      );
      canvas.drawPath(
        pane(4, 14, 15, 10),
        Paint()..color = const Color(0xFF5B6B88),
      );

      final img =
          await recorder.endRecording().toImage(dim.toInt(), dim.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return;
      final bytes = data.buffer.asUint8List();
      final icon = gmaps.BitmapDescriptor.bytes(bytes);
      if (mounted) setState(() => _driverIcon = icon);
    } catch (_) {
      // Keep the default azure marker if custom rendering fails on a device.
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
    _syncPolylines();
    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: _g(widget.initialCenter),
        zoom: widget.initialZoom,
      ),
      markers: _buildMarkers(),
      polylines: _polylines,
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
