import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmaps;
import 'package:latlong2/latlong.dart';

import '../theme/app_colors.dart';
import 'map_styles.dart';
import 'route_progress.dart';

/// What a marker represents — drives its icon + colour.
/// [me] is the rider's own position (blue dot), [driver] the gliding car.
enum MapMarkerKind { pickup, dropoff, driver, me, plain }

/// How the camera behaves. [fit] frames [AppMap.fitBounds] / recenters on
/// demand; [followDriver] keeps the driver marker centred, heading-up, at
/// street zoom (Uber Driver's navigation view) until the user pans — a
/// recenter request resumes following.
///
/// [followDriverEdge] is the rider's live-tracking view: the camera holds
/// still while the car is comfortably inside the viewport and only pans once
/// it nears an edge, which keeps the route ahead on screen without the map
/// sliding under the rider on every GPS fix. Zoom is never changed, so a
/// pinch the rider made survives; panning suspends following until the next
/// recenter, exactly as [followDriver] does.
enum MapCameraMode { fit, followDriver, followDriverEdge }

/// A point to draw on [AppMap].
class AppMapMarker {
  const AppMapMarker({
    required this.point,
    this.kind = MapMarkerKind.plain,
    this.label,
    this.heading,
    this.stale = false,
  });

  final LatLng point;
  final MapMarkerKind kind;
  final String? label;

  /// True when this position is known to be out of date (no ping for a while).
  /// The marker is drawn faded so the map says "last known", not "live" —
  /// leaving a stale car at full strength is the map quietly lying.
  final bool stale;

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
    this.recenterTrigger = 0,
    this.recenterZoom,
    this.tileProvider,
    this.boundsPadding = const EdgeInsets.all(64),
    this.cameraMode = MapCameraMode.fit,
    this.onFollowingChanged,
    this.pulseAt,
  });

  /// Draws the "finding your driver" radar here: three rings spreading from
  /// the pickup every [pulsePeriod] (audit 3.8). Null draws nothing. With the
  /// system's Reduce Motion / Remove animations on, the rings stand still.
  final LatLng? pulseAt;

  static const Duration pulsePeriod = Duration(milliseconds: 1600);

  /// Ring radius range in metres: a ring starts at the pin and spreads to a
  /// couple of blocks, the distance a nearby driver would come from.
  static const double pulseMinM = 30;
  static const double pulseMaxM = 260;

  /// The three rings at [t] (0..1 through one period): (radius m, opacity).
  /// Pure so the drawing rule can be tested without a map.
  @visibleForTesting
  static List<(double, double)> pulseRings(double t) => [
        for (var i = 0; i < 3; i++)
          () {
            final p = (t + i / 3) % 1.0;
            return (pulseMinM + (pulseMaxM - pulseMinM) * p, (1 - p) * 0.55);
          }(),
      ];

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

  /// See [MapCameraMode].
  final MapCameraMode cameraMode;

  /// Fired when automatic camera following starts or stops, so the app can
  /// offer a "Recenter" control exactly while the camera is *not* following.
  /// True means the camera is tracking the car; false means the user has taken
  /// it over by panning. Never fired in [MapCameraMode.fit], where there is
  /// nothing to follow.
  final ValueChanged<bool>? onFollowingChanged;

  /// Fraction of the viewport, per side, treated as the "edge" in
  /// [MapCameraMode.followDriverEdge]. The car is left alone while it sits in
  /// the middle band; crossing into a margin pans the camera back onto it.
  /// 0.28 keeps roughly the middle 44% quiet, which is enough to stop a car
  /// drifting off screen between pans without the map twitching on every fix.
  static const double edgeMargin = 0.28;

  /// Whether the camera should pan to keep [target] comfortably on screen,
  /// given the currently visible box [sw]..[ne]. Pure so the rule can be
  /// tested without a live map controller.
  ///
  /// Returns false when the box is not measurable (zero/negative span, which
  /// also covers a view straddling the antimeridian) — there is nothing to
  /// compare against, so the camera is left alone.
  @visibleForTesting
  static bool needsEdgePan(LatLng target, LatLng sw, LatLng ne,
      {double margin = edgeMargin}) {
    final latSpan = ne.latitude - sw.latitude;
    final lngSpan = ne.longitude - sw.longitude;
    if (latSpan <= 0 || lngSpan <= 0) return false;
    final insideLat = target.latitude >= sw.latitude + latSpan * margin &&
        target.latitude <= ne.latitude - latSpan * margin;
    final insideLng = target.longitude >= sw.longitude + lngSpan * margin &&
        target.longitude <= ne.longitude - lngSpan * margin;
    return !(insideLat && insideLng);
  }

  /// Fraction of the viewport's half-span the camera aims *past* the car, in
  /// its direction of travel, when it pans to keep up. Centring the car exactly
  /// wastes the half of the screen behind it; leading it puts the route the
  /// rider is about to drive into view instead. 0.30 is about a third of the
  /// way to the edge — enough to show what's coming without pushing the car
  /// itself near the margin that triggered the pan.
  static const double lookAheadFraction = 0.30;

  /// Where the camera should aim when following a car at [target] travelling on
  /// [bearingDeg], given the currently visible box [sw]..[ne].
  ///
  /// Returns a point offset from the car along its heading, so the upcoming
  /// route occupies the screen rather than the road already driven. Falls back
  /// to [target] itself when the viewport is not measurable or no heading is
  /// known — a look-ahead in an unknown direction is worse than none.
  ///
  /// Pure, so the rule is testable without a live map controller.
  @visibleForTesting
  static LatLng lookAhead(
    LatLng target,
    double? bearingDeg,
    LatLng sw,
    LatLng ne, {
    double fraction = lookAheadFraction,
  }) {
    if (bearingDeg == null) return target;
    final latSpan = ne.latitude - sw.latitude;
    final lngSpan = ne.longitude - sw.longitude;
    if (latSpan <= 0 || lngSpan <= 0) return target;
    final rad = bearingDeg * math.pi / 180;
    // Bearing is clockwise from north: north components the latitude, east the
    // longitude. Scaling each axis by its own half-span keeps the lead inside
    // the viewport whatever its aspect ratio.
    final dLat = math.cos(rad) * (latSpan / 2) * fraction;
    final dLng = math.sin(rad) * (lngSpan / 2) * fraction;
    return LatLng(target.latitude + dLat, target.longitude + dLng);
  }

  /// How far the camera centre must travel during one gesture before it counts
  /// as a deliberate pan.
  static const double panThresholdMeters = 40.0;

  /// How much the zoom level must change during one gesture before it counts
  /// as a deliberate zoom. A fifth of a level is well below anything a person
  /// does on purpose and well above animation jitter.
  static const double zoomThreshold = 0.2;

  /// Whether a settled gesture was the user taking over the camera.
  ///
  /// True for a deliberate drag OR a deliberate zoom. Both count, because the
  /// spec is "if the user pans, drags or zooms, pause automatic following" —
  /// and because measuring only the drag made the outcome depend on *how* the
  /// user zoomed: a centred pinch survived, an off-centre double-tap did not.
  ///
  /// Pure so the rule can be tested without a live map controller.
  @visibleForTesting
  static bool isUserGesture(double movedMeters, bool zoomed) =>
      zoomed || movedMeters > panThresholdMeters;

  /// How long the driver marker should glide for, given the gap between the
  /// last two fixes. Stretching the glide over the real interval keeps the car
  /// moving until the next fix lands, instead of darting ahead in a fixed
  /// window and then sitting frozen — which reads as jumping even though the
  /// position is interpolated. Clamped so a stalled stream can't leave it
  /// crawling, and a burst can't make it strobe.
  @visibleForTesting
  static Duration glideFor(Duration gap) =>
      Duration(milliseconds: gap.inMilliseconds.clamp(400, 2500));

  /// Whether a rebuild from [old] to [next] carries a recenter request the
  /// camera should honour. A request is suppressed while [fitBounds] frames
  /// two or more points (the fit owns the camera then).
  @visibleForTesting
  static bool recenterChanged(AppMap old, AppMap next) =>
      next.recenter != null &&
      (next.recenter != old.recenter ||
          next.recenterSeq != old.recenterSeq ||
          next.recenterTrigger != old.recenterTrigger) &&
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
  // When the last fix landed. The glide is stretched to match the gap between
  // fixes: a fixed 900ms animation against a 3s ping makes the car dart ahead
  // and then sit frozen, which reads as jumping even though it interpolates.
  DateTime? _lastFixAt;
  // The bearing the car is drawn at, and the one it is turning toward. The
  // marker eases between them over the glide instead of snapping: a car that
  // teleports from pointing north to pointing east reads as a glitch even when
  // its position interpolates perfectly.
  double _driverBearing = 0;
  double _driverBearingFrom = 0;
  gmaps.BitmapDescriptor? _driverIcon; // custom car puck, generated once
  gmaps.BitmapDescriptor? _meIcon; // rider's blue "you are here" dot
  gmaps.BitmapDescriptor? _pickupIcon; // black ring, white centre
  gmaps.BitmapDescriptor? _dropoffIcon; // black square, white centre
  // Follow mode: suspended once the user pans until the next recenter.
  bool _userPanned = false;
  // Camera moves WE started, which must not be mistaken for the user taking
  // over. This is a deadline, not a flag: a plain bool was cleared only by
  // `onCameraIdle`, so an `animateCamera` that moved the camera nowhere (the
  // target was already on screen — common on a recenter) never produced an
  // idle event and left the flag latched **on**, silently swallowing the next
  // real pan. A deadline always expires.
  DateTime? _programmaticUntil;
  /// Longest a programmatic camera animation is assumed to take.
  static const Duration _programmaticWindow = Duration(milliseconds: 1200);
  // Camera target and zoom when the current gesture began, so a gesture can be
  // measured rather than guessed at.
  //
  // Measuring only the centre was not enough: a pinch centred on the screen
  // barely moves it and survived, while a double-tap zoom shifts the centre
  // toward the tap and suspended following. Same intent from the user, two
  // different outcomes — which is worse than either rule applied consistently.
  // Both are now treated as deliberate interaction, per the spec: any pan,
  // drag or zoom pauses automatic following and raises the recenter control.
  gmaps.LatLng? _gestureStartTarget;
  double? _gestureStartZoom;
  double? _lastCameraZoom;

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
    _makeMeIcon();
    _makeStopIcons();
  }

  @override
  void dispose() {
    _pulseTimer?.cancel();
    _driverAnim.dispose();
    super.dispose();
  }

  // --- Pickup radar ----------------------------------------------------------
  // Circles are platform objects, so they are re-sent on a ~12 fps tick rather
  // than every frame: smooth enough for a slow spreading ring, and cheap on
  // the platform channel.
  Timer? _pulseTimer;
  final Stopwatch _pulseClock = Stopwatch();

  void _syncPulse(bool reduceMotion) {
    final want = widget.pulseAt != null && !reduceMotion;
    if (want && _pulseTimer == null) {
      _pulseClock
        ..reset()
        ..start();
      _pulseTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
        if (mounted) setState(() {});
      });
    } else if (!want && _pulseTimer != null) {
      _pulseTimer!.cancel();
      _pulseTimer = null;
      _pulseClock.stop();
    }
  }

  Set<gmaps.Circle> _buildPulse(bool reduceMotion) {
    final at = widget.pulseAt;
    if (at == null) return const {};
    final period = AppMap.pulsePeriod.inMilliseconds;
    // Reduce Motion: a still frame with the rings evenly spread.
    final t = reduceMotion
        ? 0.0
        : (_pulseClock.elapsedMilliseconds % period) / period;
    final colour = AppColors.highlight;
    return {
      for (final (i, (radius, opacity)) in AppMap.pulseRings(t).indexed)
        gmaps.Circle(
          circleId: gmaps.CircleId('pulse$i'),
          center: _g(at),
          radius: radius,
          strokeWidth: 2,
          strokeColor: colour.withValues(alpha: opacity),
          fillColor: colour.withValues(alpha: opacity * 0.25),
          zIndex: 0,
        ),
    };
  }

  /// True while a camera move we started is still expected to be in flight.
  bool get _isProgrammatic {
    final until = _programmaticUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  /// Start or stop automatic following, telling the app when it changes so it
  /// can show a "Recenter" control exactly while following is suspended.
  ///
  /// The notification is deferred to after the frame. Following changes from
  /// `didUpdateWidget` (a mode change, an honoured recenter), which runs
  /// *during* build — and a listener that calls setState there throws
  /// "setState() called during build", taking the whole screen down with it.
  /// The flag itself flips immediately; only the telling waits.
  void _setFollowing(bool following) {
    if (_userPanned == !following) return; // no change
    _userPanned = !following;
    final notify = widget.onFollowingChanged;
    if (notify == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Re-check: the state can flip back before the frame ends (a pan
      // immediately followed by a recenter), and reporting a change that is
      // no longer true would leave the app's control out of step with us.
      if (mounted && _userPanned == !following) notify(following);
    });
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
    final paddingMoved =
        (old.boundsPadding.bottom - widget.boundsPadding.bottom).abs() > 24 ||
            (old.boundsPadding.top - widget.boundsPadding.top).abs() > 24;
    if (paddingMoved) {
      // The sheet grew or shrank (e.g. the ride list replaced "finding the
      // best route…"). Re-frame so the route sits above the new sheet edge —
      // but only after this frame: the new map padding reaches the native
      // map with this build, and a camera move issued before it is framed
      // against the old padding (the route ended up behind the sheet).
      _lastFittedBounds = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(milliseconds: 120), () {
          if (!mounted) return;
          _lastFittedBounds = null;
          _fit();
        });
      });
    } else if (!_sameBounds(old.fitBounds, widget.fitBounds)) {
      _fit();
    }
    if (AppMap.recenterChanged(old, widget)) {
      _setFollowing(true);
      if (widget.cameraMode == MapCameraMode.followDriver &&
          _driverMarker(widget.markers) != null) {
        _followDriver();
      } else {
        _moveTo(widget.recenter!);
      }
    }
    if (old.cameraMode != widget.cameraMode) {
      _setFollowing(true);
      if (widget.cameraMode == MapCameraMode.followDriver) {
        _followDriver();
      } else if (widget.cameraMode == MapCameraMode.followDriverEdge) {
        // Entering rider follow: nudge once if the car is already off-centre,
        // then leave the camera alone until it nears an edge.
        _followDriverEdge();
      } else {
        _resetToNorthUp();
      }
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
        // Ease out of whatever angle is currently on screen, so the car turns
        // through the corner rather than snapping to the new bearing.
        _driverBearingFrom = _currentDriverBearing();
        _driverBearing = _driverMarker(widget.markers)?.heading ??
            _bearing(from, next);
      }
      _driverFrom = from;
      _driverTo = next;
      // Stretch the glide over the observed gap between fixes so the car is
      // still moving when the next one lands, instead of arriving early and
      // freezing. Clamped so a stalled stream can't leave it crawling.
      final now = DateTime.now();
      final gap = _lastFixAt == null
          ? _driverAnim.duration!
          : now.difference(_lastFixAt!);
      _lastFixAt = now;
      _driverAnim.duration = AppMap.glideFor(gap);
      _driverAnim
        ..reset()
        ..forward();
      if (widget.cameraMode == MapCameraMode.followDriver) {
        _followDriver();
      } else if (widget.cameraMode == MapCameraMode.followDriverEdge) {
        _followDriverEdge();
      }
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

  /// The angle the car is drawn at right now, easing from the bearing it held
  /// when the fix landed to the new one over the same window as the glide.
  /// Interpolated the short way round the compass so a turn through north
  /// (350° → 10°) sweeps 20°, not 340° the wrong way.
  double _currentDriverBearing() {
    final t = _driverAnim.isAnimating ? _driverAnim.value : 1.0;
    var delta = (_driverBearing - _driverBearingFrom) % 360;
    if (delta > 180) delta -= 360;
    if (delta < -180) delta += 360;
    return (_driverBearingFrom + delta * t) % 360;
  }

  /// Heading-up street view centred on the car (zoom 17, slight tilt).
  Future<void> _followDriver() async {
    if (_userPanned) return;
    final target = _driverTo ?? _driverMarker(widget.markers)?.point;
    if (target == null) return;
    final c = await _controller.future;
    if (!mounted || _userPanned) return;
    _programmaticUntil = DateTime.now().add(_programmaticWindow);
    // Keep the car centred but leave the map flat and north-up at the same
    // street zoom the rider sees: the heading-up, tilted variant made the
    // driver's map look like a different product in the field.
    await c.animateCamera(
      gmaps.CameraUpdate.newCameraPosition(
        gmaps.CameraPosition(
          target: _g(target),
          zoom: widget.initialZoom,
          bearing: 0,
          tilt: 0,
        ),
      ),
    );
  }


  /// Rider live-tracking camera: pan only when the car nears the edge of what
  /// is on screen, and never change zoom (a pinch the rider made must stick).
  Future<void> _followDriverEdge() async {
    if (_userPanned) return;
    final target = _currentDriverPoint() ?? _driverTo;
    if (target == null) return;
    final c = await _controller.future;
    if (!mounted || _userPanned) return;
    final gmaps.LatLngBounds region;
    try {
      region = await c.getVisibleRegion();
    } catch (_) {
      return; // controller not ready yet; the next fix will retry
    }
    if (!mounted || _userPanned) return;
    final sw = LatLng(region.southwest.latitude, region.southwest.longitude);
    final ne = LatLng(region.northeast.latitude, region.northeast.longitude);
    if (!AppMap.needsEdgePan(target, sw, ne)) return;
    _programmaticUntil = DateTime.now().add(_programmaticWindow);
    // Aim PAST the car along its heading so the road it is about to drive
    // fills the screen, instead of re-centring it and handing half the
    // viewport back to the road already behind it.
    final aim = AppMap.lookAhead(target, _driverBearing, sw, ne);
    // newLatLng, not newLatLngZoom: keep whatever zoom is on screen.
    await c.animateCamera(gmaps.CameraUpdate.newLatLng(_g(aim)));
  }

  /// Leaving follow mode: undo the heading-up rotation/tilt so the idle map
  /// isn't left pointing wherever the car last drove.
  Future<void> _resetToNorthUp() async {
    final target = _driverTo ??
        _driverMarker(widget.markers)?.point ??
        widget.recenter ??
        widget.initialCenter;
    final c = await _controller.future;
    if (!mounted) return;
    // Keep the street-level zoom the driver was already at; never fall back
    // to the wide initial zoom (that snapped the map out to a city view).
    final current = await c.getZoomLevel();
    final zoom = current < 15 ? 16.0 : current;
    if (!mounted) return;
    _programmaticUntil = DateTime.now().add(_programmaticWindow);
    await c.animateCamera(
      gmaps.CameraUpdate.newCameraPosition(
        gmaps.CameraPosition(
          target: _g(target),
          zoom: zoom,
          bearing: 0,
          tilt: 0,
        ),
      ),
    );
  }

  Future<void> _moveTo(LatLng center) async {
    final c = await _controller.future;
    if (!mounted) return;
    // Recenter also restores a street-level zoom: after a route fit the camera
    // is zoomed out over the whole trip, and "recenter" without a zoom left
    // the rider looking at the entire city. [recenterZoom] lets a "locate me"
    // tap pick a precise zoom instead.
    _programmaticUntil = DateTime.now().add(_programmaticWindow);
    await c.animateCamera(
      gmaps.CameraUpdate.newLatLngZoom(
        _g(center),
        widget.recenterZoom ?? widget.initialZoom,
      ),
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
    // A fit is OUR camera move. Without this it looks exactly like a long drag
    // to the gesture classifier — which is how framing a route on the first
    // frame of a phase silently suspended follow mode and raised the Recenter
    // pill before the rider had touched the map.
    _programmaticUntil = DateTime.now().add(_programmaticWindow);
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
      final isMe = m.kind == MapMarkerKind.me;
      final icon = isDriver && _driverIcon != null
          ? _driverIcon!
          : isMe && _meIcon != null
              ? _meIcon!
              : m.kind == MapMarkerKind.pickup && _pickupIcon != null
                  ? _pickupIcon!
                  : m.kind == MapMarkerKind.dropoff && _dropoffIcon != null
                      ? _dropoffIcon!
                      : _iconFor(m.kind);
      final centred = isDriver ||
          isMe ||
          m.kind == MapMarkerKind.pickup ||
          (m.kind == MapMarkerKind.dropoff && _dropoffIcon != null);
      out.add(gmaps.Marker(
        markerId: gmaps.MarkerId('${m.kind.name}_${i++}'),
        position: _g(point),
        icon: icon,
        anchor: centred ? const Offset(0.5, 0.5) : const Offset(0.5, 1.0),
        zIndexInt: isDriver ? 3 : (isMe ? 2 : 1),
        rotation: isDriver ? _currentDriverBearing() : (m.heading ?? 0),
        // A position we know is out of date is drawn faded: the rider can see
        // the last place the car was without the map implying it is there now.
        alpha: m.stale ? 0.45 : 1.0,
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
          color: AppColors.highlight,
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
        color: AppColors.highlight,
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

  /// Ride-hailing stop pins: pickup = a black ring with a white centre,
  /// drop-off = a black square with a white centre. White outer edge so both
  /// read on the light and the dark basemap.
  Future<void> _makeStopIcons() async {
    Future<gmaps.BitmapDescriptor?> draw(bool square) async {
      const dim = 64.0;
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      const c = Offset(dim / 2, dim / 2);
      final white = Paint()..color = Colors.white;
      final black = Paint()..color = Colors.black;
      final shadow = Paint()
        ..color = const Color(0x40000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      if (square) {
        canvas.drawRect(Rect.fromCenter(center: c + const Offset(0, 1.5), width: 40, height: 40), shadow);
        canvas.drawRect(Rect.fromCenter(center: c, width: 40, height: 40), white);
        canvas.drawRect(Rect.fromCenter(center: c, width: 32, height: 32), black);
        canvas.drawRect(Rect.fromCenter(center: c, width: 11, height: 11), white);
      } else {
        canvas.drawCircle(c + const Offset(0, 1.5), 20, shadow);
        canvas.drawCircle(c, 20, white);
        canvas.drawCircle(c, 16, black);
        canvas.drawCircle(c, 6, white);
      }
      final img = await recorder.endRecording().toImage(dim.toInt(), dim.toInt());
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) return null;
      return gmaps.BitmapDescriptor.bytes(data.buffer.asUint8List(), width: 22);
    }

    try {
      final pickup = await draw(false);
      final dropoff = await draw(true);
      if (mounted) {
        setState(() {
          _pickupIcon = pickup;
          _dropoffIcon = dropoff;
        });
      }
    } catch (_) {
      // Fall back to the default markers.
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
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncPolylines();
    _syncPulse(reduceMotion);
    return gmaps.GoogleMap(
      initialCameraPosition: gmaps.CameraPosition(
        target: _g(widget.initialCenter),
        zoom: widget.initialZoom,
      ),
      // Themed basemap: a night style in dark mode (so the map doesn't glow
      // white under light status-bar icons) and a de-cluttered light style.
      style: dark ? mapNightStyle : mapLightStyle,
      markers: _buildMarkers(),
      polylines: _polylines,
      circles: _buildPulse(reduceMotion),
      padding: widget.boundsPadding,
      myLocationEnabled: false,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: false,
      mapToolbarEnabled: false,
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      // Explicit rather than relying on the plugin default: pinch-to-zoom and
      // scroll are the two gestures this map depends on, and the iOS SDK has
      // historically differed from Android on what is on by default.
      zoomGesturesEnabled: true,
      scrollGesturesEnabled: true,
      onMapCreated: (c) {
        if (!_controller.isCompleted) _controller.complete(c);
        // Without this the first gesture has no "before" position to compare
        // against and cannot be classified as a pan.
        _lastCameraTarget ??= _g(widget.initialCenter);
        _fit();
        widget.onMapReady?.call();
      },
      onCameraMoveStarted: () {
        // Don't decide yet: a pinch and a drag both land here. Remember where
        // the centre was and classify once the gesture settles.
        if (!_isProgrammatic && widget.cameraMode != MapCameraMode.fit) {
          // Seeded in onMapCreated, so the very FIRST drag of a session is
          // classified too — it used to be missed (null start), leaving the
          // camera fighting the user until they panned a second time.
          _gestureStartTarget = _lastCameraTarget;
          _gestureStartZoom = _lastCameraZoom;
        }
      },
      onCameraMove: (pos) {
        _lastCameraTarget = pos.target;
        _lastCameraZoom = pos.zoom;
      },
      onCameraIdle: () {
        final start = _gestureStartTarget;
        final startZoom = _gestureStartZoom;
        _gestureStartTarget = null;
        _gestureStartZoom = null;
        if (start != null && !_isProgrammatic) {
          final end = _lastCameraTarget;
          // No end position to compare against: treat it as a pan rather than
          // silently keeping a camera the user may have moved.
          final moved = end == null
              ? double.infinity
              : _distanceMeters(
                  LatLng(start.latitude, start.longitude),
                  LatLng(end.latitude, end.longitude),
                );
          final zoomed = startZoom != null &&
              _lastCameraZoom != null &&
              (_lastCameraZoom! - startZoom).abs() > AppMap.zoomThreshold;
          if (AppMap.isUserGesture(moved, zoomed)) _setFollowing(false);
        }
        _programmaticUntil = null;
        final t = _lastCameraTarget;
        if (t != null && widget.onCenterChanged != null) {
          widget.onCenterChanged!(LatLng(t.latitude, t.longitude));
        }
      },
    );
  }
}
