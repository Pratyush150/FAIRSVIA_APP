import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'features/account/driver_profile_stats.dart';
import 'features/driver/call_rider_button.dart';
import 'features/driver/destination_mode.dart';
import 'features/driver/driver_cubit.dart';
import 'features/driver/location_priming_page.dart';
import 'features/driver/location_stream.dart';
import 'features/driver/no_show_timer.dart';
import 'features/driver/vehicle_setup_dialog.dart';
import 'features/fatigue/fatigue_panel.dart';
import 'features/incentives/driver_rates.dart';
import 'features/incentives/quests.dart';
import 'features/trip_extras/trip_extras.dart';
import 'features/home_extras/driver_home_extras.dart';

/// Top-down 3D render of the driver's own vehicle tier for their car on the
/// map (the same art the rider sees for this driver); unknown/absent tiers
/// get the generic 'driver' car.
String driverCarAssetFor(String? tier) {
  const known = {'economy', 'comfort', 'xl', 'premium', 'auto', 'bike'};
  final name = known.contains(tier) ? tier : 'driver';
  return 'packages/design_system/assets/vehicles/top/$name.png';
}

/// Driver home: map + online toggle, interrupting offer modal, and the
/// en-route → arrived → on-trip lifecycle sheets.
class DriverHomePage extends StatelessWidget {
  const DriverHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          DriverCubit(
        sl<RealtimeClient>(),
        sl<DriverRemoteDataSource>(),
        sl<RatingsRemoteDataSource>(),
      ),
      child: const _DriverHomeView(),
    );
  }
}

class _DriverHomeView extends StatefulWidget {
  const _DriverHomeView();

  @override
  State<_DriverHomeView> createState() => _DriverHomeViewState();
}

class _DriverHomeViewState extends State<_DriverHomeView>
    with WidgetsBindingObserver {
  // City centre shown before the first GPS fix. Configurable per build with
  // --dart-define=FALLBACK_LOCATION=<lat>,<lng> (matches the rider app);
  // otherwise the market's launch city (Market.cityCenter). It used to default
  // to Miami, so a driver in Pune saw a US city until the first GPS fix.
  static final LatLng _fallback = _parseFallback();
  static LatLng _parseFallback() {
    const raw = String.fromEnvironment('FALLBACK_LOCATION');
    final parts = raw.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    // The market's launch city (Pune for the pilot), not a US default.
    final (lat, lng) = Market.current.cityCenter;
    return LatLng(lat, lng);
  }
  StreamSubscription<Position>? _posSub;
  // Presence heartbeat: geolocator only emits when the driver MOVES
  // (distanceFilter), so a driver parked waiting for rides stops pinging and
  // gets evicted from the dispatch pool — the app still says "Online" but new
  // requests find "no drivers" until they toggle offline/online. Re-send the
  // last known position on this timer so presence stays fresh while stationary.
  Timer? _heartbeat;

  // Busy-areas shading: polled while the driver is free (no trip, no offer).
  Timer? _demandTick;
  DateTime? _demandAt;
  static const _demandEvery = Duration(minutes: 2);
  // The driver's own live position — drawn as the car marker so they can see
  // themselves relative to the pickup (Uber-style).
  LatLng? _myLocation;
  bool _onboardingShowing = false;
  // Which simulated drive is currently running (phase + route). The listener
  // fires on error changes too; restarting the sim on those teleported the car
  // back to the route start on any mid-trip error snackbar.
  String? _simKey;
  // Memo for _fitBounds: it decodes the approach polyline, and the page
  // rebuilds on every GPS tick.
  String? _fitKey;
  List<LatLng>? _fitCache;

  // --- Live re-routing ---
  // When the driver leaves the drawn route (takes a different/shorter road), we
  // re-fetch the optimal road route from where they actually are, so the line
  // relocates onto the road taken. [_rerouteGate] rate-limits it.
  final RerouteGate _rerouteGate = RerouteGate();
  String? _liveRoutePolyline;
  String? _liveRouteLeg;

  // The driver's registered vehicle tier (from their profile) — picks the
  // top-down car drawn for them on the map.
  String? _vehicleTier;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
    _primeLocation();
    _loadVehicleTier();
    // Cheap tick; the fetch itself happens at most every [_demandEvery] and
    // only once we have a fix (the server caches per area for a minute).
    _demandTick = Timer.periodic(const Duration(seconds: 10), (_) {
      _maybeLoadDemand();
    });
  }

  void _maybeLoadDemand() {
    if (!mounted) return;
    final at = _myLocation;
    if (at == null) return;
    final cubit = context.read<DriverCubit>();
    if (cubit.state.trip != null) return;
    final last = _demandAt;
    if (last != null && DateTime.now().difference(last) < _demandEvery) return;
    _demandAt = DateTime.now();
    unawaited(cubit.loadDemand(at.latitude, at.longitude));
  }

  Future<void> _loadVehicleTier() async {
    try {
      final profile = await sl<DriverRemoteDataSource>().me();
      if (mounted && profile.vehicleTier != _vehicleTier) {
        setState(() => _vehicleTier = profile.vehicleTier);
      }
    } catch (_) {
      // Not onboarded yet / offline: the generic car stays until it loads.
    }
  }

  /// One fix at startup so the idle/offline map opens on the driver instead
  /// of the city fallback. Streaming (and pinging the server) only starts
  /// when they go online.
  Future<void> _primeLocation() async {
    if (kIsWeb) return;
    try {
      // First run (or an Android "deny" that may be asked again): explain
      // why on RideVela's own screen before the OS dialog appears.
      if (await locationPromptPending()) {
        if (!mounted) return;
        final cubit = context.read<DriverCubit>();
        final access =
            await Navigator.of(context).push(LocationPrimingPage.route());
        if (access != LocationAccess.granted) {
          if (access != null) cubit.setLocationIssue(access);
          return;
        }
      } else {
        // Already decided: never prompt here, just show the banner if it is
        // blocked (going online still re-checks and may ask for precision).
        final access = await currentLocationAccess();
        if (!mounted) return;
        if (access != LocationAccess.granted) {
          context.read<DriverCubit>().setLocationIssue(access);
          return;
        }
      }
      final pos = await driverPositionStream()
          .first
          .timeout(const Duration(seconds: 10));
      if (!mounted || _myLocation != null) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
    } catch (_) {
      // No fix yet: the fallback centre stays until they go online.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS kills the WebSocket while the app is suspended; without this a driver
    // returning from another app still reads "Online" but never gets an offer.
    if (state == AppLifecycleState.resumed) {
      _resumeSocket();
      unawaited(_recheckLocationIssue());
    }
  }

  /// Back from Settings: drop the location banner once access is fixed (or
  /// update it to what is still wrong).
  Future<void> _recheckLocationIssue() async {
    if (context.read<DriverCubit>().state.locationIssue == null) return;
    final access = await currentLocationAccess();
    if (!mounted) return;
    context.read<DriverCubit>().setLocationIssue(access);
  }

  Future<void> _connect() async {
    // A fresh sign-in may reach the home before the access token has finished
    // persisting to secure storage — read it with a few retries rather than
    // silently skipping the socket connection (which left a just-signed-in
    // driver never receiving offers). init() is idempotent and self-retries the
    // socket internally, so one successful call is enough.
    for (var attempt = 0; attempt < 6 && mounted; attempt++) {
      try {
        final token = await sl<TokenStorage>().readAccessToken();
        if (token != null && token.isNotEmpty) {
          if (!mounted) return;
          await context.read<DriverCubit>().init(
            token,
            tokenProvider: sl<DioClient>().freshAccessToken,
          );
          return;
        }
      } catch (_) {
        // Read/connect can fail transiently; retry with backoff below.
      }
      await Future<void>.delayed(Duration(milliseconds: 400 * (attempt + 1)));
    }
  }

  Future<void> _resumeSocket() async {
    final token = await sl<TokenStorage>().readAccessToken();
    if (token != null && mounted) {
      await context.read<DriverCubit>().resumeFromBackground(token);
    }
  }

  Future<void> _startStreamingLocation() async {
    if (_posSub != null) return;
    // Browser geolocation needs HTTPS and isn't available in the web preview;
    // skip GPS streaming there so going online still works for UI testing.
    if (kIsWeb) return;
    if (!await ensureLocationPermission()) return;

    // Push ONE fix immediately so a stationary driver (parked, waiting for
    // rides — the normal case) enters the dispatch pool right away. The position
    // stream below uses a distanceFilter, so it only emits AFTER the driver
    // moves — without this initial fix a still driver is never indexed and never
    // receives offers. (Skipped in mock mode: that stream emits immediately.)
    if (!_isMockLocation) await _sendCurrentFix();

    _posSub = driverPositionStream().listen((pos) {
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      context.read<DriverCubit>().sendLocation(
            pos.latitude,
            pos.longitude,
            heading: pos.heading,
            speed: pos.speed,
            accuracy: pos.accuracy,
            at: pos.timestamp,
          );
      // Keep the drawn line on the road actually being driven.
      unawaited(_maybeReroute(context.read<DriverCubit>().state));
    });
    // Keep presence fresh while parked — well under the backend's stale window.
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted) return;
      final loc = _myLocation;
      if (loc != null) {
        context.read<DriverCubit>().sendLocation(loc.latitude, loc.longitude);
      } else if (!_isMockLocation) {
        // Still no stream fix (stationary) — actively fetch one so presence
        // never lapses and the driver stays in the pool.
        unawaited(_sendCurrentFix());
      }
    });
  }

  static const bool _isMockLocation =
      String.fromEnvironment('MOCK_LOCATION') != '';

  /// Fetch the current position once and push it — so presence exists even
  /// before the movement-triggered stream emits (the parked-driver case).
  Future<void> _sendCurrentFix() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;
      setState(() => _myLocation = LatLng(pos.latitude, pos.longitude));
      context.read<DriverCubit>().sendLocation(
            pos.latitude,
            pos.longitude,
            heading: pos.heading,
            speed: pos.speed,
          );
    } catch (_) {
      // A fresh fix can time out indoors — fall back to the last known one so
      // the driver still enters the pool rather than staying invisible.
      try {
        final last = await Geolocator.getLastKnownPosition();
        if (last != null && mounted) {
          setState(() => _myLocation = LatLng(last.latitude, last.longitude));
          context
              .read<DriverCubit>()
              .sendLocation(last.latitude, last.longitude);
        }
      } catch (_) {}
    }
  }

  void _stopStreamingLocation() {
    _posSub?.cancel();
    _posSub = null;
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _demandTick?.cancel();
    _stopStreamingLocation();
    super.dispose();
  }

  static List<MapHeatSpot> _heatSpots(DriverState state) {
    if (state.trip != null || state.offer != null) return const [];
    return [
      for (final c in state.demand)
        MapHeatSpot(point: LatLng(c.lat, c.lng), intensity: c.intensity),
    ];
  }

  List<AppMapMarker> _markers(DriverState state) {
    final markers = <AppMapMarker>[];
    // The driver's own car — shown whenever we have a live fix and they're
    // online (so they can see themselves heading to the pickup).
    if (_myLocation != null) {
      markers.add(AppMapMarker(
        point: _myLocation!,
        kind: MapMarkerKind.driver,
        label: 'You',
      ));
    }
    // An open offer: show its pickup so the driver can see where it is
    // above the offer card (audit 2026-09-25 #29).
    final offer = state.offer;
    if (offer != null && state.trip == null) {
      markers.add(AppMapMarker(
        point: LatLng(offer.pickup.point.lat, offer.pickup.point.lng),
        kind: MapMarkerKind.pickup,
        label: 'Pickup',
      ));
    }
    final trip = state.trip;
    if (trip != null) {
      markers.add(AppMapMarker(
        point: LatLng(trip.pickup.point.lat, trip.pickup.point.lng),
        kind: MapMarkerKind.pickup,
        label: 'Pickup',
      ));
      markers.add(AppMapMarker(
        point: LatLng(trip.dropoff.point.lat, trip.dropoff.point.lng),
        kind: MapMarkerKind.dropoff,
        label: 'Dropoff',
      ));
    }
    return markers;
  }

  /// The route to draw. While heading to the pickup we show the *approach* leg
  /// (driver → pickup); once on the trip we show the trip route.
  ///
  /// When the car is being simulated we draw only the *remaining* path from its
  /// current position, so the line shrinks behind it as it drives (and vanishes
  /// on arrival) — matching how Uber/Ola render an active route.
  /// The active leg for re-routing: 'approach' (→pickup) while heading to the
  /// rider, 'trip' (→dropoff) once on the trip, else null.
  String? _legKey(DriverState state) {
    if (state.trip == null) return null;
    if (state.phase == DriverPhase.enRoute ||
        state.phase == DriverPhase.arrived) {
      return 'approach';
    }
    if (state.phase == DriverPhase.onTrip) return 'trip';
    return null;
  }

  List<LatLng> _route(DriverState state) {
    // No live leg → no line. Without this the simulated car's leftover path
    // kept the previous trip's route on the map after "Done" (seen on iOS).
    final active = state.phase == DriverPhase.enRoute ||
        state.phase == DriverPhase.arrived ||
        state.phase == DriverPhase.onTrip;
    if (!active) return const [];
    final remaining = simulatedRemainingPath();
    if (remaining.length >= 2) {
      return [for (final p in remaining) LatLng(p.lat, p.lng)];
    }
    if (simulatedArrived) return const []; // reached it — no line left

    final leg = _legKey(state);
    // Prefer a freshly re-routed line for the current leg — the road actually
    // driven — over the route planned at accept (real-GPS re-routing).
    if (leg != null && _liveRoutePolyline != null && _liveRouteLeg == leg) {
      final live = decodePolyline(_liveRoutePolyline!);
      if (live.length >= 2) return live;
    }
    final approaching = leg == 'approach';
    final encoded = approaching
        ? (state.approachPolyline ?? state.trip?.routePolyline)
        : state.trip?.routePolyline;
    if (encoded == null || encoded.isEmpty) return const [];
    return decodePolyline(encoded);
  }

  /// If the driver has left the drawn route, re-fetch the optimal road route
  /// from their live position to the current target (pickup, then dropoff).
  /// Throttled by [_rerouteGate]; best-effort (a failure keeps the current line).
  Future<void> _maybeReroute(DriverState state) async {
    final me = _myLocation;
    final leg = _legKey(state);
    final trip = state.trip;
    if (me == null || leg == null || trip == null) return;
    final target = leg == 'approach'
        ? LatLng(trip.pickup.point.lat, trip.pickup.point.lng)
        : LatLng(trip.dropoff.point.lat, trip.dropoff.point.lng);

    final route = _route(state);
    if (route.length < 2) return;
    final split = splitRouteAtPoint(route, me);
    if (!_rerouteGate.shouldReroute(
      from: me,
      offRouteMeters: split.offRouteMeters,
      leg: leg,
    )) {
      return;
    }
    _rerouteGate.begin();
    String? poly;
    try {
      poly = await sl<TripRepository>().route(
        fromLat: me.latitude,
        fromLng: me.longitude,
        toLat: target.latitude,
        toLng: target.longitude,
      );
    } finally {
      _rerouteGate.end(me);
    }
    if (!mounted || poly == null) return;
    setState(() {
      _liveRoutePolyline = poly;
      _liveRouteLeg = leg;
    });
  }

  /// Decode a road polyline and pin its tail to the exact destination, so the
  /// car finishes precisely ON the pickup/dropoff pin rather than wherever the
  /// route geometry happens to end (which can be a few metres off).
  List<({double lat, double lng})> _pathTo(
    String? encoded,
    double endLat,
    double endLng,
  ) {
    final pts = decodePolyline(encoded ?? '');
    final path = [for (final p in pts) (lat: p.latitude, lng: p.longitude)];
    const eps = 0.00001; // ~1m
    if (path.isEmpty ||
        (path.last.lat - endLat).abs() > eps ||
        (path.last.lng - endLng).abs() > eps) {
      path.add((lat: endLat, lng: endLng));
    }
    return path;
  }

  /// Frame the map for the current phase: heading to pickup → the approach leg
  /// (its polyline endpoints, which stay fixed for the whole approach, so the
  /// camera frames it ONCE instead of re-animating on every GPS tick and
  /// fighting the driver's pans); on a trip → the whole route.
  ///
  /// Once the driver is at the pickup the leg is a point; fitting zero-area
  /// bounds zooms the map to max, so anything under ~50 m falls back to a fixed
  /// ~250 m box around the pickup (a street-level zoom via the same fitBounds
  /// API — AppMap has no explicit zoom setter).
  List<LatLng>? _fitBounds(DriverState state) {
    // An open offer frames the driver and the offer's pickup in the map
    // area left above the offer card (see [_boundsPadding]).
    final offer = state.offer;
    if (offer != null && state.trip == null) {
      final pickup = LatLng(offer.pickup.point.lat, offer.pickup.point.lng);
      final me = _myLocation;
      final pts = me == null ? [pickup, pickup] : [me, pickup];
      return _spanMeters(pts) < 50 ? _boxAround(pickup, 125) : pts;
    }
    // While online we follow the driver's position at a close navigation zoom
    // (see the AppMap above), so don't fight it with bounds-framing — the map
    // stays zoomed in on the car and the route ahead.
    if (state.isOnline && _myLocation != null) return null;
    final trip = state.trip;
    if (trip == null) return null;
    final approaching = state.phase == DriverPhase.enRoute ||
        state.phase == DriverPhase.arrived;
    final key = '${trip.id}|${state.phase}|'
        '${approaching ? state.approachPolyline : ''}';
    if (key == _fitKey) return _fitCache;
    final pickup = LatLng(trip.pickup.point.lat, trip.pickup.point.lng);
    final dropoff = LatLng(trip.dropoff.point.lat, trip.dropoff.point.lng);
    List<LatLng> bounds;
    if (approaching) {
      final encoded = state.approachPolyline;
      final pts = (encoded == null || encoded.isEmpty)
          ? const <LatLng>[]
          : decodePolyline(encoded);
      bounds = pts.length >= 2 ? [pts.first, pts.last] : [pickup, pickup];
      if (_spanMeters(bounds) < 50) bounds = _boxAround(pickup, 125);
    } else {
      bounds = [pickup, dropoff];
      if (_spanMeters(bounds) < 50) bounds = _boxAround(pickup, 125);
    }
    _fitKey = key;
    _fitCache = bounds;
    return bounds;
  }

  /// Diagonal of the bounding box of [pts], in metres (equirectangular; fine
  /// at city scale).
  static double _spanMeters(List<LatLng> pts) {
    var minLat = pts.first.latitude, maxLat = pts.first.latitude;
    var minLng = pts.first.longitude, maxLng = pts.first.longitude;
    for (final p in pts) {
      minLat = math.min(minLat, p.latitude);
      maxLat = math.max(maxLat, p.latitude);
      minLng = math.min(minLng, p.longitude);
      maxLng = math.max(maxLng, p.longitude);
    }
    const mPerDegLat = 111320.0;
    final midLat = (minLat + maxLat) / 2 * math.pi / 180;
    final dy = (maxLat - minLat) * mPerDegLat;
    final dx = (maxLng - minLng) * mPerDegLat * math.cos(midLat);
    return math.sqrt(dx * dx + dy * dy);
  }

  /// A square [halfSpanM] metres either side of [c] — a fixed street-level
  /// frame around a single point.
  static List<LatLng> _boxAround(LatLng c, double halfSpanM) {
    const mPerDegLat = 111320.0;
    final dLat = halfSpanM / mPerDegLat;
    final dLng =
        halfSpanM / (mPerDegLat * math.cos(c.latitude * math.pi / 180));
    return [
      LatLng(c.latitude - dLat, c.longitude - dLng),
      LatLng(c.latitude + dLat, c.longitude + dLng),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<DriverCubit, DriverState>(
      listenWhen: (p, c) =>
          p.phase != c.phase ||
          p.error != c.error ||
          p.needsOnboarding != c.needsOnboarding,
      listener: (context, state) {
        // Drop a stale re-routed line when the leg changes (approach → trip).
        final leg = _legKey(state);
        if (leg != _liveRouteLeg && _liveRoutePolyline != null) {
          _liveRoutePolyline = null;
        }
        if (state.isOnline) {
          _startStreamingLocation();
        } else {
          _stopStreamingLocation();
        }
        // Demo/QA: with a mocked location, drive the car ALONG THE ROAD ROUTE —
        // the approach leg to the pickup, then the trip route to the dropoff —
        // so it tracks streets like a real driver instead of sliding straight
        // across the map.
        // Only (re)start the drive when the leg actually changes — this
        // listener also fires for error/onboarding changes, and restarting
        // then reset the car to the start of the route mid-drive.
        final trip = state.trip;
        if (trip != null) {
          String? polyline;
          double? endLat, endLng;
          if (state.phase == DriverPhase.enRoute) {
            polyline = state.approachPolyline;
            endLat = trip.pickup.point.lat;
            endLng = trip.pickup.point.lng;
          } else if (state.phase == DriverPhase.onTrip) {
            polyline = trip.routePolyline;
            endLat = trip.dropoff.point.lat;
            endLng = trip.dropoff.point.lng;
          }
          if (endLat != null && endLng != null) {
            final key = '${trip.id}|${state.phase}|${polyline ?? ''}';
            if (key != _simKey) {
              _simKey = key;
              driveSimulatedPath(_pathTo(polyline, endLat, endLng));
            }
          }
        } else {
          _simKey = null;
        }
        if (state.needsOnboarding) {
          _showOnboarding(context);
        } else if (state.error != null && state.locationIssue == null) {
          // A location refusal is shown by the sheet's banner instead, with
          // its Open Settings button, and stays until it is fixed.
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              // Float above the bottom sheet instead of covering its CTA.
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 300),
              content: Text(state.error!),
            ));
        }
      },
      builder: (context, state) {
        return Scaffold(
          body: Stack(
            children: [
              // Google Maps basemap (key from the gitignored native secrets).
              AppMap(
                initialCenter: _markers(state).isNotEmpty
                    ? _markers(state).first.point
                    : (_myLocation ?? _fallback),
                // Street level: recentring on the driver used to fall back
                // to the widget's city-wide default and "zoom out" whenever
                // presence changed.
                initialZoom: 16,
                // Follow the driver's own GPS while idle (online, no trip) so the
                // map tracks them instead of freezing on the opening centre. On a
                // trip, fitBounds frames pickup/route instead.
                recenter: (state.trip == null && state.offer == null)
                    ? _myLocation
                    : null,
                markers: _markers(state),
                // The driver's own car: the 3D top-down render of their tier
                // (the live trip's tier wins, it is what they're driving).
                driverCarAsset:
                    driverCarAssetFor(state.trip?.tier ?? _vehicleTier),
                route: _route(state),
                // Busy areas while the driver is free to take a trip.
                heatSpots: _heatSpots(state),
                fitBounds: _fitBounds(state),
                // The offer card covers the lower part of the screen; frame
                // the pickup in the strip above it.
                boundsPadding: state.offer != null && state.trip == null
                    ? EdgeInsets.fromLTRB(
                        64,
                        120,
                        64,
                        MediaQuery.sizeOf(context).height * 0.6,
                      )
                    : const EdgeInsets.all(64),
                // Navigation view while driving: heading-up, centred on the
                // car, until the driver pans (recenter resumes it).
                cameraMode: state.phase == DriverPhase.enRoute ||
                        state.phase == DriverPhase.onTrip
                    ? MapCameraMode.followDriver
                    : MapCameraMode.fit,
              ),
              // Banner and the top controls share one column so the
              // "Reconnecting…" bar pushes the status pill / menu button down
              // instead of being drawn underneath them (seen on iOS). The
              // banner already pads for the status bar, so the controls only
              // take the top inset while it is hidden.
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConnectionBanner(connected: state.connected),
                    SafeArea(
                      top: state.connected,
                      bottom: false,
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        // Menu top-left, as on the rider app (audit
                        // 2026-09-25 #7); the status pill sits beside it.
                        child: Row(
                          children: [
                            AppCircleButton(
                              icon: PhosphorIconsRegular.list,
                              tooltip: 'Account menu',
                              onPressed: () {
                                final cubit = context.read<DriverCubit>();
                                Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (menuCtx) => AccountMenuPage(
                                      isDriver: true,
                                      profileDetails: _profileStats(context),
                                      onVehicle: () => _editVehicle(menuCtx, cubit),
                                      // A live trip must be finished first;
                                      // the backend refuses offline mid-trip.
                                      signOutBlocker: () =>
                                          cubit.state.trip != null
                                              ? 'Finish your current trip '
                                                  'before signing out.'
                                              : null,
                                      onBeforeSignOut: () async {
                                        if (cubit.state.isOnline) {
                                          await cubit.goOffline();
                                        }
                                      },
                                    ),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            _StatusPill(online: state.isOnline),
                            const Spacer(),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Positioned.fill(
                child: DriverSheetLayer(
                  state: state,
                  myLocation: _myLocation,
                  route: _route(state),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Rating, trips and plate for the Account profile card.
  Widget _profileStats(BuildContext context) {
    final user = context.read<AuthBloc>().state.user;
    final driver = sl<DriverRemoteDataSource>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DriverProfileStats(
          ratingAvg: user?.ratingAvg ?? 0,
          ratingCount: user?.ratingCount ?? 0,
          loadProfile: driver.me,
          loadWeek: () => driver.earnings(range: 'week'),
        ),
        const Divider(height: AppSpacing.xl),
        // Acceptance / cancellation rates, last 7 days.
        DriverRates(load: sl<IncentivesRemoteDataSource>().stats),
      ],
    );
  }

  Future<void> _showOnboarding(BuildContext context) async {
    if (_onboardingShowing) return; // never stack a second copy
    _onboardingShowing = true;
    final cubit = context.read<DriverCubit>();
    try {
      await showDialog<bool>(
        context: context,
        builder: (_) => VehicleSetupDialog(cubit: cubit),
      );
    } finally {
      _onboardingShowing = false;
      unawaited(_loadVehicleTier());
    }
  }

  /// "Vehicle" from the account menu: the same dialog, prefilled from the
  /// server, saving without touching presence.
  ///
  /// [cubit] is passed in explicitly: the menu is a pushed route, so its
  /// context sits outside this page's BlocProvider.
  Future<void> _editVehicle(BuildContext context, DriverCubit cubit) async {
    final messenger = ScaffoldMessenger.of(context);
    DriverProfile profile;
    try {
      profile = await sl<DriverRemoteDataSource>().me();
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (!context.mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => VehicleSetupDialog(
        cubit: cubit,
        initial: profile,
        goOnlineAfter: false,
      ),
    );
    if (saved == true) {
      unawaited(_loadVehicleTier());
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Vehicle updated.')));
    }
  }
}

/// "Go online": when the OS would show its location dialog, RideVela's
/// priming screen goes first; the cubit's own check then finds access
/// already decided. Anything else goes straight to [DriverCubit.goOnline].
Future<void> _goOnline(BuildContext context, DriverCubit cubit) async {
  if (await locationPromptPending()) {
    if (!context.mounted) return;
    final access =
        await Navigator.of(context).push(LocationPrimingPage.route());
    if (access != LocationAccess.granted) {
      if (access != null) cubit.setLocationIssue(access);
      return;
    }
  }
  await cubit.goOnline();
}

/// The layer over the map: the phase's bottom sheet and, when an offer is
/// live, the offer card drawn above it — including above the trip-complete /
/// rate-rider sheet, which stays underneath (see [DriverCubit] `_onOffer`).
class DriverSheetLayer extends StatelessWidget {
  const DriverSheetLayer({
    super.key,
    required this.state,
    this.myLocation,
    this.route = const [],
  });

  final DriverState state;
  final LatLng? myLocation;
  final List<LatLng> route;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Align(
          alignment: Alignment.bottomCenter,
          child: _BottomSheet(
            state: state,
            myLocation: myLocation,
            route: route,
          ),
        ),
        if (state.phase == DriverPhase.offered && state.offer != null)
          OfferOverlay(offer: state.offer!),
      ],
    );
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet({
    required this.state,
    this.myLocation,
    this.route = const [],
  });

  /// The leg being driven (approach or trip), for a road distance readout.
  final List<LatLng> route;
  final DriverState state;

  /// Driver's own last fix, for the live distance-to-pickup/dropoff line.
  final LatLng? myLocation;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<DriverCubit>();
    final theme = Theme.of(context);
    final Widget child;
    switch (state.phase) {
      case DriverPhase.offline:
        child = DriverOfflineSheet(
          lastEarned: state.lastEarned,
          locationIssue: state.locationIssue,
          busy: state.busy,
          onGoOnline: () => _goOnline(context, cubit),
          onEarnings: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) =>
                DriverEarningsPage(driver: sl<DriverRemoteDataSource>()),
          )),
          quests: const _SheetQuests(),
          fatigue: const _SheetFatigue(),
        );
      // An offer that arrived on the trip-complete sheet is drawn OVER that
      // sheet (OfferOverlay); keep the sheet underneath so declining it or
      // letting it expire lands the driver back where they were.
      case DriverPhase.offered when state.lastTripId != null:
        child = _CompletedSheet(state: state, cubit: cubit);
      case DriverPhase.online:
      case DriverPhase.offered:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // A radar sweeping round the driver's pin while requests are
                // looked for (the same art as the rider's "Finding your
                // driver"). Fixed 48px box; a still frame under Reduce
                // Motion. It replaces the badge + spinner pair.
                const LottieMoment.searching(size: 48),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        liveRegion: true,
                        header: true,
                        child: Text("You're online",
                            style: theme.textTheme.titleLarge),
                      ),
                      const SizedBox(height: 2),
                      Text(
                          state.demand.isNotEmpty
                              ? 'Looking for trips · busy areas are shaded'
                              : 'Looking for trips nearby…',
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
              ],
            ),
            const _SheetFatigue(),
            const _SheetQuests(),
            // Destination ("go home") mode: a button, or the active chip.
            if (sl.isRegistered<DestinationModeRemoteDataSource>()) ...[
              const SizedBox(height: AppSpacing.lg),
              DestinationModeBar(
                api: sl<DestinationModeRemoteDataSource>(),
                onPick: (s) => Navigator.of(context).push<DestinationPick>(
                  MaterialPageRoute(
                    builder: (_) => DestinationPickerPage(
                      places: sl<PlacesRemoteDataSource>(),
                      home: s.home,
                      near: myLocation == null
                          ? null
                          : GeoPoint(
                              myLocation!.latitude, myLocation!.longitude),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.lg),
            SecondaryButton(
              label: 'Go offline',
              onPressed: () => cubit.goOffline(),
            ),
          ],
        );
      case DriverPhase.enRoute:
        final pickup = state.trip == null
            ? null
            : LatLng(state.trip!.pickup.point.lat, state.trip!.pickup.point.lng);
        child = _LifecycleSheet(
          title: 'Head to pickup',
          subtitle: state.trip?.pickup.address ?? 'Pickup location',
          actionLabel: 'Arrived',
          busy: state.busy,
          onAction: () => cubit.markArrived(),
          tripId: state.trip?.id,
          navigateTo: pickup,
          distanceLabel: _distanceLabel(myLocation, pickup, 'pickup', route),
          note: state.trip?.pickupNote,
          passenger: state.trip?.passenger,
          riderPhone: state.trip?.riderPhone,
          stopsAhead: state.trip?.stops ?? const [],
          stopsInfoOnly: true,
          stopAdded: _recently(state.stopsChangedAt),
        );
      case DriverPhase.arrived:
        child = _StartTripSheet(
          cubit: cubit,
          busy: state.busy,
          tripId: state.trip?.id,
          riderPhone: state.trip?.riderPhone,
          arrivedAt: state.arrivedAt ?? state.trip?.arrivedAt,
          noShowWaitSec: state.trip?.noShowWaitSec,
          noShowFee: state.trip?.cancellationFee,
        );
      case DriverPhase.onTrip:
        final dropoff = state.trip == null
            ? null
            : LatLng(
                state.trip!.dropoff.point.lat, state.trip!.dropoff.point.lng);
        child = _LifecycleSheet(
          title: 'On trip',
          subtitle: state.trip?.dropoff.address ?? 'Dropoff location',
          actionLabel: 'Complete trip',
          busy: state.busy,
          onAction: () => cubit.completeTrip(),
          tripId: state.trip?.id,
          navigateTo: dropoff,
          distanceLabel: _distanceLabel(myLocation, dropoff, 'dropoff', route),
          stopsAhead: state.stopsAhead,
          stopAdded: _recently(state.stopsChangedAt),
        );
      case DriverPhase.completed:
        child = _CompletedSheet(state: state, cubit: cubit);
    }
    final coming = state.riderComingAt != null &&
        (state.phase == DriverPhase.enRoute ||
            state.phase == DriverPhase.arrived);
    // Waiting phases (offline / online): pull the sheet up for today's
    // figures, busy areas, rates and driver tips (real data only).
    if (state.phase == DriverPhase.offline ||
        (state.phase == DriverPhase.online)) {
      return DriverExpandableSheet(
        key: ValueKey('drv-sheet-${state.phase.name}'),
        extras: driverWaitingExtras(context, state, myLocation),
        child: child,
      );
    }
    // In-trip phases: pull the sheet up for the rider, route, fare/payment,
    // progress, safety tools and a driver tip; after the trip, this trip's
    // fare, today's total and quests. Collapsed, the sheet is unchanged.
    if (_tripExtras(context, state, cubit) case final extras?) {
      return TripPullUpSheet(
        stageKey: state.phase,
        extras: extras,
        child: coming
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _RiderComingBanner(name: state.riderName),
                  const SizedBox(height: AppSpacing.md),
                  child,
                ],
              )
            : child,
      );
    }
    return AppSheet(
      child: coming
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _RiderComingBanner(name: state.riderName),
                const SizedBox(height: AppSpacing.md),
                child,
              ],
            )
          : child,
    );
  }

  /// The pull-up content for the in-trip and trip-complete phases; null for
  /// every other phase (or when there is no trip to describe).
  Widget? _tripExtras(
      BuildContext context, DriverState state, DriverCubit cubit) {
    if (state.phase == DriverPhase.completed) {
      final id = state.lastTripId;
      final api = sl.isRegistered<DriverRemoteDataSource>()
          ? sl<DriverRemoteDataSource>()
          : null;
      return DriverCompletedExtras(
        key: ValueKey('completed-extras-$id'),
        loadTrip: id == null || api == null ? null : () => api.getTrip(id),
        todayTotal: state.lastEarned,
        quests: const _SheetQuests(),
      );
    }
    final trip = state.trip;
    if (trip == null) return null;
    final stage = switch (state.phase) {
      DriverPhase.enRoute => TripExtrasStage.toPickup,
      DriverPhase.arrived => TripExtrasStage.waiting,
      DriverPhase.onTrip => TripExtrasStage.onTrip,
      _ => null,
    };
    if (stage == null) return null;
    final target = stage == TripExtrasStage.onTrip
        ? LatLng(trip.dropoff.point.lat, trip.dropoff.point.lng)
        : LatLng(trip.pickup.point.lat, trip.pickup.point.lng);
    final me = myLocation;
    final remaining = me == null || stage == TripExtrasStage.waiting
        ? null
        : route.length >= 2
            ? routeRemainingMeters(route, me)
            : distanceMeters(me, target);
    return DriverTripExtras(
      stage: stage,
      trip: trip,
      riderName: state.riderName,
      remainingMeters: remaining,
      onNavigate: () async {
        final ok = await openTurnByTurn(
            lat: target.latitude, lng: target.longitude);
        if (!ok && context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('No navigation app could be opened')));
        }
      },
      onSafety: () => openDriverSafety(context, trip.id),
      onShare: () => shareTripText(
        context,
        "I'm driving a ${AppBrand.name} trip"
        '${trip.dropoff.address != null ? ' to ${trip.dropoff.address}' : ''}.',
      ),
      onMessage: () => openDriverChat(context, trip.id),
    );
  }
}

/// The offline state of the driver's home sheet: what today earned, any
/// location problem, and "Go online". Public so it can be widget-tested
/// (including the accessibility guidelines) without the map.
class DriverOfflineSheet extends StatelessWidget {
  const DriverOfflineSheet({
    super.key,
    this.lastEarned,
    this.locationIssue,
    this.busy = false,
    required this.onGoOnline,
    this.onEarnings,
    this.quests,
    this.fatigue,
  });

  /// Online time vs the fatigue limit / the rest countdown (FatigueStatusBar);
  /// null hides it.
  final Widget? fatigue;

  /// The Quests card (DriverQuestsCard); null hides it.
  final Widget? quests;

  final double? lastEarned;
  final LocationAccess? locationIssue;
  final bool busy;
  final VoidCallback onGoOnline;

  /// Opens the earnings dashboard; null hides the shortcut.
  final VoidCallback? onEarnings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const AppIconBadge(
                icon: PhosphorIconsRegular.moonStars,
                tone: AppIconBadgeTone.neutral),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Announced when the driver goes offline (audit 4.3).
                  Semantics(
                    liveRegion: true,
                    header: true,
                    child: Text("You're offline",
                        style: theme.textTheme.titleLarge),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    lastEarned != null
                        ? 'Earned today · ${Fmt.money(lastEarned!)}'
                        : 'Go online to start earning',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            if (onEarnings != null)
              TextButton(
                onPressed: onEarnings,
                child: const Text('Earnings'),
              ),
          ],
        ),
        if (locationIssue case final issue?) ...[
          const SizedBox(height: AppSpacing.md),
          LocationAccessBanner(
            access: issue,
            onOpenSettings: () => unawaited(openLocationFix(issue)),
          ),
        ],
        ?fatigue,
        ?quests,
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Go online',
          loading: busy,
          onPressed: busy ? null : onGoOnline,
        ),
      ],
    );
  }
}

/// The rider tapped "I'm on my way": they are coming out — no need to call.
class _RiderComingBanner extends StatelessWidget {
  const _RiderComingBanner({this.name});

  final String? name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final who = (name == null || name!.trim().isEmpty)
        ? 'Your rider'
        : name!.trim().split(RegExp(r'\s+')).first;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          children: [
            Icon(PhosphorIconsRegular.personSimpleWalk,
                size: 20, color: AppColors.accentInk),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '$who is on the way out',
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: AppColors.accentInk),
              ),
            ),
          ],
        ),
      ),
    ).motion((w) =>
        w.animate().fadeIn(duration: AppMotion.normal).slideY(begin: -0.2));
  }
}

class _CompletedSheet extends StatelessWidget {
  const _CompletedSheet({required this.state, required this.cubit});
  final DriverState state;
  final DriverCubit cubit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          // Hero medallion: 64 disc, 32 glyph — same as the rider's.
          child: Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIconsRegular.check,
                color: AppColors.accent, size: 32),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Semantics(
            liveRegion: true,
            header: true,
            child: Text('Trip complete',
                style: theme.textTheme.headlineSmall),
          ),
        ),
        if (state.lastEarned != null) ...[
          const SizedBox(height: AppSpacing.xs),
          // Banknotes flutter once over the earnings (not under Reduce
          // Motion).
          const Center(child: LottieMoment.money(size: 56)),
          Center(
            child: Text(
                "Today's earnings · ${Fmt.money(state.lastEarned!)}",
                style: theme.textTheme.bodyMedium),
          ),
        ],
        // Ended short of the drop-off: say how it was charged (non-blocking).
        if (state.endNote case final note?) ...[
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text(note,
                key: const ValueKey('trip-end-note'),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall),
          ),
        ],
        if (state.cashToCollect != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              color: AppColors.warning.withValues(alpha: 0.12),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.money,
                    size: 20, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Collect ${Fmt.money(state.cashToCollect!)} in cash from the rider',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Center(
          child: Text('Rate your rider', style: theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: StarRating(
            value: state.riderRating ?? 0,
            // Always tappable — re-rating corrects the first tap rather than
            // adding a second vote (see DriverCubit.rateRider).
            onRate: (v) => cubit.rateRider(v),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Done',
          onPressed: () => cubit.dismissCompleted(),
        ),
      ],
    );
  }
}

/// A rider-added stop is announced for a minute after it happens.
bool _recently(DateTime? at) =>
    at != null && DateTime.now().difference(at) < const Duration(minutes: 1);

class _LifecycleSheet extends StatelessWidget {
  const _LifecycleSheet({
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.onAction,
    required this.busy,
    this.tripId,
    this.navigateTo,
    this.distanceLabel,
    this.note,
    this.passenger,
    this.riderPhone,
    this.stopsAhead = const [],
    this.stopsInfoOnly = false,
    this.stopAdded = false,
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final bool busy;
  final String? tripId;

  /// Destination for the "Navigate" hand-off (Google Maps / Waze / Apple Maps).
  final LatLng? navigateTo;

  /// Live "0.3 mi to pickup" style readout from the driver's own position.
  final String? distanceLabel;

  /// A pickup note from the rider, shown while heading to the pickup.
  final String? note;

  /// Set when the person who booked is not the person travelling. The driver
  /// is collecting them, not the booker, so their name and number are what
  /// matters at the kerb.
  final TripPassenger? passenger;

  /// The rider's number for "Call rider" (heading to the pickup only — once
  /// on the trip they are in the car). Null hides the button.
  final String? riderPhone;

  /// Stops still ahead on this leg, in order.
  final List<TripStop> stopsAhead;

  /// Heading to the pickup: the stops come later, so only mention them.
  final bool stopsInfoOnly;

  /// The rider added a stop a moment ago.
  final bool stopAdded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              // Announced when the trip moves on (Head to pickup → On trip).
              child: Semantics(
                liveRegion: true,
                header: true,
                child: Text(title, style: theme.textTheme.headlineSmall),
              ),
            ),
            if (riderPhone != null) CallRiderButton(phone: riderPhone!),
            if (tripId != null) ...[
              IconButton(
                tooltip: 'Safety',
                // Neutral at rest like the rider's Safety pill; the sheet it
                // opens carries the red (audit 2026-09-25 #10).
                icon: Icon(PhosphorIconsRegular.shieldCheck,
                    color: AppColors.iconNeutralFor(
                        Theme.of(context).brightness == Brightness.dark)),
                onPressed: () => openDriverSafety(context, tripId!),
              ),
              IconButton(
                tooltip: 'Message rider',
                icon: _ChatBadgeIcon(
                    unread: context.watch<DriverCubit>().state.unreadMessages),
                onPressed: () => openDriverChat(context, tripId!),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: theme.textTheme.bodyMedium),
        if (distanceLabel != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Icon(PhosphorIconsRegular.navigationArrow,
                  size: 20,
                  color: AppColors.iconNeutralFor(
                      theme.brightness == Brightness.dark)),
              const SizedBox(width: AppSpacing.xs),
              Text(distanceLabel!, style: theme.textTheme.titleSmall),
            ],
          ),
        ],
        if (stopAdded) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(
              children: [
                const Icon(PhosphorIconsRegular.mapPinPlus,
                    size: 20, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('The rider added a stop',
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
          ),
        ],
        if (stopsAhead.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          if (stopsInfoOnly)
            Text(
              stopsAhead.length == 1
                  ? '1 stop on this ride'
                  : '${stopsAhead.length} stops on this ride',
              style: theme.textTheme.bodySmall,
            )
          else
            for (var i = 0; i < stopsAhead.length; i++)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(PhosphorIconsRegular.flag,
                        size: 20,
                        color: i == 0
                            ? AppColors.warning
                            : AppColors.iconNeutralFor(
                                theme.brightness == Brightness.dark)),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        '${i == 0 ? 'Next stop' : 'Then'} · '
                        '${stopsAhead[i].address ?? 'Pinned location'}',
                        style: i == 0
                            ? theme.textTheme.titleSmall
                            : theme.textTheme.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
        ],
        if (passenger != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _PassengerBanner(passenger: passenger!),
        ],
        if (note != null && note!.trim().isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          _PickupNoteBanner(
            note: note!,
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            if (navigateTo != null) ...[
              Expanded(
                child: SecondaryButton(
                  label: 'Navigate',
                  icon: PhosphorIconsRegular.navigationArrow,
                  onPressed: () => _navigate(context, navigateTo!),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
            ],
            Expanded(
              flex: navigateTo != null ? 2 : 1,
              child: PrimaryButton(
                label: actionLabel,
                loading: busy,
                onPressed: busy ? null : onAction,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _navigate(BuildContext context, LatLng to) async {
    final ok = await openTurnByTurn(
      lat: to.latitude,
      lng: to.longitude,
      // Through the stops still ahead — never straight past them.
      via: stopsInfoOnly
          ? const []
          : [for (final s in stopsAhead) (lat: s.point.lat, lng: s.point.lng)],
    );
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation app could be opened')),
      );
    }
  }
}

/// "45 m to pickup" / "2.4 km to dropoff" from the driver's own fix — along
/// the road when the leg's polyline is known, straight-line otherwise.
String? _distanceLabel(
  LatLng? from,
  LatLng? to,
  String what, [
  List<LatLng> route = const [],
]) {
  if (from == null || to == null) return null;
  final m = route.length >= 2
      ? routeRemainingMeters(route, from)
      : distanceMeters(from, to);
  // Metres up close in every market (a driver reads "45 m" at a glance);
  // beyond that the market's unit.
  if (m < 200) return '${m.round()} m to $what';
  return '${Market.current.legDistance(m.round())} to $what';
}

/// Who to collect, when the booker is not the one travelling. Carries a call
/// button because the driver's usual "message rider" reaches the booker, who
/// may be in another city — the passenger is the one standing at the kerb.
class _PassengerBanner extends StatelessWidget {
  const _PassengerBanner({required this.passenger});
  final TripPassenger passenger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.userCircle,
              size: 20, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Picking up',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.accentPressed)),
                const SizedBox(height: 2),
                Text(passenger.displayName,
                    style: theme.textTheme.bodyMedium),
                Text('Booked by someone else',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Call passenger',
            // Icons are neutral unless the colour means something (#10).
            icon: Icon(PhosphorIconsRegular.phone,
                color: AppColors.iconNeutralFor(
                    Theme.of(context).brightness == Brightness.dark)),
            onPressed: () async {
              final ok = await dialPhone(passenger.phone);
              if (!ok && context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Could not dial ${passenger.phone}'),
                  ),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}

/// A highlighted banner showing the rider's pickup note to the driver.
class _PickupNoteBanner extends StatelessWidget {
  const _PickupNoteBanner({required this.note});
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: AppColors.accentSoft,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.note,
              size: 20, color: AppColors.accent),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Note from rider',
                    style: theme.textTheme.labelMedium
                        ?.copyWith(color: AppColors.accentPressed)),
                const SizedBox(height: 2),
                Text(note, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Opens the safety toolkit (SOS) for the driver's active trip. Drivers get the
/// same safety affordance riders have. Location is best-effort so an alert still
/// fires if GPS is momentarily unavailable.
Future<void> openDriverSafety(BuildContext context, String tripId) async {
  await showSafetySheet(
    context,
    tripId: tripId,
    safety: sl<SafetyRemoteDataSource>(),
    shareText: "I'm driving a ${AppBrand.name} trip and may need help.",
    locate: () async {
      final pos = await Geolocator.getLastKnownPosition() ??
          await Geolocator.getCurrentPosition();
      return (lat: pos.latitude, lng: pos.longitude);
    },
  );
}

/// Opens the in-trip chat with the rider.
void openDriverChat(BuildContext context, String tripId) {
  final userId = context.read<AuthBloc>().state.user?.id;
  if (userId == null) return;
  final cubit = context.read<DriverCubit>();
  final riderName = cubit.state.riderName;
  cubit.setChatOpen(true);
  unawaited(Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatPage(
        tripId: tripId,
        currentUserId: userId,
        title: riderName ?? 'Rider',
        peerRole: 'rider',
        chat: sl<ChatRemoteDataSource>(),
        realtime: sl<RealtimeClient>(),
      ),
    ),
  ).then((_) => cubit.setChatOpen(false)));
}

class _StartTripSheet extends StatefulWidget {
  const _StartTripSheet({
    required this.cubit,
    required this.busy,
    this.tripId,
    this.riderPhone,
    this.arrivedAt,
    this.noShowWaitSec,
    this.noShowFee,
  });
  final DriverCubit cubit;
  final bool busy;
  final String? tripId;

  /// Rider no-show wait (see [NoShowTimer]); hidden when the backend doesn't
  /// report the wait (older server) or the arrival time is unknown.
  final DateTime? arrivedAt;
  final int? noShowWaitSec;
  final double? noShowFee;

  /// Waiting at the pickup: "Call rider" when they have not come out.
  final String? riderPhone;

  @override
  State<_StartTripSheet> createState() => _StartTripSheetState();
}

class _StartTripSheetState extends State<_StartTripSheet> {
  // Must match the backend's start-OTP length (trips.service generateOtp = 4).
  // A mismatch leaves "Start trip" permanently disabled — the driver could
  // never start a ride.
  static const int _startCodeLength = 4;
  String _otp = '';
  // Bumped to rebuild OtpInput (clearing the boxes) after a wrong code.
  int _resetSeq = 0;
  String? _inlineError;
  StreamSubscription<DriverState>? _sub;

  @override
  void initState() {
    super.initState();
    _sub = widget.cubit.stream.listen((s) {
      if (s.phase != DriverPhase.arrived || s.error == null) return;
      if (!mounted) return;
      setState(() {
        _inlineError = s.error;
        _otp = '';
        _resetSeq++;
      });
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                liveRegion: true,
                header: true,
                child: Text('Confirm rider',
                    style: theme.textTheme.headlineSmall),
              ),
            ),
            if (widget.riderPhone != null)
              CallRiderButton(phone: widget.riderPhone!),
            if (widget.tripId != null) ...[
              IconButton(
                tooltip: 'Safety',
                // Neutral at rest like the rider's Safety pill; the sheet it
                // opens carries the red (audit 2026-09-25 #10).
                icon: Icon(PhosphorIconsRegular.shieldCheck,
                    color: AppColors.iconNeutralFor(
                        Theme.of(context).brightness == Brightness.dark)),
                onPressed: () => openDriverSafety(context, widget.tripId!),
              ),
              IconButton(
                tooltip: 'Message rider',
                icon: _ChatBadgeIcon(
                    unread: context.watch<DriverCubit>().state.unreadMessages),
                onPressed: () => openDriverChat(context, widget.tripId!),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('Ask the rider for their $_startCodeLength-digit start code',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        OtpInput(
            key: ValueKey('start-code-$_resetSeq'),
            length: _startCodeLength,
            onChanged: (v) => setState(() {
                  _otp = v;
                  if (v.isNotEmpty) _inlineError = null;
                })),
        if (_inlineError != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(PhosphorIconsRegular.warningCircle,
                  size: 16, color: AppColors.error),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(_inlineError!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.error)),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(
          label: 'Start trip',
          loading: widget.busy,
          onPressed: _otp.length == _startCodeLength && !widget.busy
              ? () => widget.cubit.startTrip(_otp)
              : null,
        ),
        if (widget.arrivedAt != null && widget.noShowWaitSec != null) ...[
          const SizedBox(height: AppSpacing.lg),
          NoShowTimer(
            arrivedAt: widget.arrivedAt!,
            waitSec: widget.noShowWaitSec!,
            fee: widget.noShowFee,
            busy: widget.busy,
            onNoShow: () async {
              final messenger = ScaffoldMessenger.maybeOf(context);
              final fee = await widget.cubit.cancelNoShow();
              if (fee == null) return;
              messenger?.showSnackBar(SnackBar(
                content: Text(fee > 0
                    ? 'Trip cancelled · ${Fmt.money(fee)} no-show fee charged'
                    : 'Trip cancelled'),
              ));
            },
          ),
        ],
      ],
    );
  }
}

/// The interrupting ride-offer card with its accept/decline countdown. Public
/// so its content can be widget-tested; only the home page mounts it.
class OfferOverlay extends StatefulWidget {
  const OfferOverlay({super.key, required this.offer});
  final RideOffer offer;

  @override
  State<OfferOverlay> createState() => _OfferOverlayState();
}

class _OfferOverlayState extends State<OfferOverlay> {
  late int _remaining;
  late final int _total;
  Timer? _timer;
  // Set once the driver taps Accept. Stops the countdown from auto-declining a
  // ride they already accepted (if trip:assigned is slower than the timer), and
  // guards the buttons against a double-tap.
  bool _accepted = false;

  @override
  void initState() {
    super.initState();
    _total = widget.offer.expiresInSec;
    _remaining = _total;
    // An incoming offer is urgent and interrupting — announce it firmly, then
    // keep a repeating buzz going for the whole window so it's hard to miss when
    // the phone is in a mount/pocket (a persistent alert, like Uber's ping).
    AppHaptics.heavy();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining -= 1);
      if (_remaining <= 0) {
        t.cancel();
        // Never auto-decline a ride the driver has already accepted.
        if (!_accepted) context.read<DriverCubit>().declineOffer();
        return;
      }
      // Escalating alert: a strong pulse every 2s, then every second in the
      // final 3s as the window closes.
      if (_remaining <= 3) {
        AppHaptics.heavy();
      } else if (_remaining.isEven) {
        AppHaptics.medium();
      }
    });
  }

  void _onAccept() {
    if (_accepted) return;
    setState(() => _accepted = true);
    _timer?.cancel(); // no more countdown once accepted
    context.read<DriverCubit>().acceptOffer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final offer = widget.offer;
    final low = _remaining <= 5;
    return Positioned.fill(
      child: Stack(
        children: [
          // A light, unblurred scrim: the map (and the pickup on it) stays
          // readable behind the card. The whole-screen blur hid exactly what
          // the driver needs to judge the offer (audit 2026-09-25 #29).
          Positioned.fill(
            child: IgnorePointer(
              child: ColoredBox(
                color: AppColors.scrim.withValues(alpha: 0.12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              top: false,
              child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Material(
                borderRadius: BorderRadius.circular(AppSpacing.radiusXl),
                color: theme.colorScheme.surface,
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('New ride request',
                          style: theme.textTheme.titleLarge),
                    ),
                    Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox(
                          height: 44,
                          width: 44,
                          child: TweenAnimationBuilder<double>(
                            tween: Tween(
                              begin: 1,
                              end: _total == 0 ? 0 : _remaining / _total,
                            ),
                            duration: AppMotion.slow,
                            builder: (context, v, _) =>
                                CircularProgressIndicator(
                              value: v,
                              strokeWidth: 4,
                              backgroundColor:
                                  theme.brightness == Brightness.dark
                                      ? AppColors.borderDark
                                      : AppColors.borderLight,
                              valueColor: AlwaysStoppedAnimation(
                                  low ? AppColors.error : AppColors.accent),
                            ),
                          ),
                        ),
                        Text('$_remaining',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: low ? AppColors.error : null,
                            )),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(Fmt.money(offer.fare),
                        style: theme.textTheme.displaySmall),
                    // Surge premium is baked into the fare; call it out so
                    // the driver knows why this one pays more.
                    if (offer.surgeLabel != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(alpha: 0.16),
                          borderRadius:
                              BorderRadius.circular(AppSpacing.radius),
                        ),
                        child: Text(offer.surgeLabel!,
                            style: theme.textTheme.labelMedium
                                ?.copyWith(color: AppColors.warning)),
                      ),
                    ],
                  ],
                ),
                // The trip leg (pickup → dropoff): "4.3 mi · 14 min trip".
                Text('Est. fare · ${offer.tripLabel} trip',
                    style: theme.textTheme.bodyMedium),
                // Who you're collecting + how far to reach them, so the driver
                // isn't accepting blind. Both omitted gracefully on old payloads.
                if (offer.riderName != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(PhosphorIconsRegular.user,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(offer.riderName!,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (offer.riderRating != null) ...[
                        const SizedBox(width: 6),
                        const Icon(PhosphorIconsFill.star,
                            size: 16, color: AppColors.star),
                        const SizedBox(width: 2),
                        Text(offer.riderRating!.toStringAsFixed(1),
                            style: theme.textTheme.labelLarge),
                      ],
                    ],
                  ),
                ],
                // How far/long to reach the rider — road ETA when the server
                // has one ("6 min · 1.4 mi to pickup"), else straight-line.
                if (offer.approachEtaLabel != null)
                  Text(offer.approachEtaLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OfferStop(
                        icon: PhosphorIconsRegular.record,
                        label: 'Pickup',
                        address: offer.pickup.address ?? 'Pickup location',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      // Where the trip ends, so the driver can judge the
                      // whole job before accepting; its own icon, not an
                      // arrow in the text (audit 2026-09-25 #29).
                      _OfferStop(
                        icon: PhosphorIconsRegular.mapPin,
                        label: 'Drop-off',
                        address: offer.dropoff.address ?? 'Drop-off location',
                      ),
                    ],
                  ),
                ),
                if (offer.pickupNote != null &&
                    offer.pickupNote!.trim().isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  _PickupNoteBanner(note: offer.pickupNote!),
                ],
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: SecondaryButton(
                        label: 'Decline',
                        onPressed: _accepted
                            ? null
                            : () => context.read<DriverCubit>().declineOffer(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Accept',
                        loading: _accepted,
                        onPressed: _accepted ? null : _onAccept,
                      ),
                    ),
                      ],
                    ),
                  ],
                ),
              ),
            ).motion(
              (w) => w.animate().fadeIn(duration: AppMotion.fast).scaleXY(
                    begin: 0.9,
                    end: 1,
                    duration: AppMotion.normal,
                    curve: AppMotion.enter,
                  ),
            ),
          ),
          ),
          ),
        ],
      ),
    );
  }
}

/// One stop on the offer card: icon badge, a small label, the address.
class _OfferStop extends StatelessWidget {
  const _OfferStop({
    required this.icon,
    required this.label,
    required this.address,
  });

  final IconData icon;
  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MergeSemantics(
      child: Row(
        children: [
          AppIconBadge(icon: icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(address,
                    style: theme.textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = online ? AppColors.success : AppColors.textTertiaryLight;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.pill),
        boxShadow: AppElevation.float,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(online ? 'Online' : 'Offline',
              style: theme.textTheme.labelLarge?.copyWith(color: color)),
        ],
      ),
    );
  }
}

/// Chat bubble with an unread-count badge for the sheet buttons.
class _ChatBadgeIcon extends StatelessWidget {
  const _ChatBadgeIcon({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(
      PhosphorIconsRegular.chatCircle,
      color: AppColors.iconNeutralFor(
        Theme.of(context).brightness == Brightness.dark,
      ),
    );
    if (unread <= 0) return icon;
    return Badge.count(count: unread, child: icon);
  }
}

/// The Quests card wired to the real API and the `quest:completed` push.
class _SheetQuests extends StatelessWidget {
  const _SheetQuests();

  @override
  Widget build(BuildContext context) {
    // Extra, not core: absent (e.g. in a widget test's slim DI) → no card.
    if (!sl.isRegistered<IncentivesRemoteDataSource>()) {
      return const SizedBox.shrink();
    }
    return DriverQuestsCard(
      load: sl<IncentivesRemoteDataSource>().quests,
      completions: sl.isRegistered<RealtimeClient>()
          ? sl<RealtimeClient>().on('quest:completed')
          : null,
    );
  }
}

/// Online time vs the fatigue limit, wired to the real API and the server's
/// fatigue socket events; opens the rest screen when the driver is locked out.
class _SheetFatigue extends StatelessWidget {
  const _SheetFatigue();

  @override
  Widget build(BuildContext context) {
    // Absent in a widget test's slim DI → nothing.
    if (!sl.isRegistered<FatigueRemoteDataSource>()) {
      return const SizedBox.shrink();
    }
    final rt = sl.isRegistered<RealtimeClient>() ? sl<RealtimeClient>() : null;
    return FatigueStatusBar(
      load: sl<FatigueRemoteDataSource>().get,
      events: [
        if (rt != null) ...[
          rt.on('driver:fatigue_warning'),
          rt.on('driver:fatigue_locked'),
          rt.on('driver:status_changed'),
        ],
      ],
      reminders: rt?.on('driver:break_reminder'),
      onLocked: (s) => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => DriverRestPage(status: s),
      )),
    );
  }
}
