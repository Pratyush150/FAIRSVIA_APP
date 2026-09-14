import 'dart:async';
import 'dart:math' as math;

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_models/shared_models.dart';

import 'features/driver/driver_cubit.dart';
import 'features/driver/location_stream.dart';

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
  // --dart-define=FALLBACK_LOCATION=<lat>,<lng> (matches the rider app); defaults
  // to Miami when unset. Previously hardcoded to Miami, which left the driver map
  // stranded there in other markets until a trip framed the camera.
  static final LatLng _fallback = _parseFallback();
  static LatLng _parseFallback() {
    const raw = String.fromEnvironment('FALLBACK_LOCATION');
    final parts = raw.split(',');
    if (parts.length == 2) {
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat != null && lng != null) return LatLng(lat, lng);
    }
    return const LatLng(25.7743, -80.1937); // Miami, FL
  }
  StreamSubscription<Position>? _posSub;
  // Presence heartbeat: geolocator only emits when the driver MOVES
  // (distanceFilter), so a driver parked waiting for rides stops pinging and
  // gets evicted from the dispatch pool — the app still says "Online" but new
  // requests find "no drivers" until they toggle offline/online. Re-send the
  // last known position on this timer so presence stays fresh while stationary.
  Timer? _heartbeat;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _connect();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS kills the WebSocket while the app is suspended; without this a driver
    // returning from another app still reads "Online" but never gets an offer.
    if (state == AppLifecycleState.resumed) _resumeSocket();
  }

  Future<void> _connect() async {
    try {
      final token = await sl<TokenStorage>().readAccessToken();
      if (token != null && mounted) {
        await context.read<DriverCubit>().init(
          token,
          tokenProvider: sl<DioClient>().freshAccessToken,
        );
      }
    } catch (_) {
      // Connect can time out; the realtime client retries with backoff and the
      // connection banner reflects status. Swallow so a slow/failed initial
      // connect isn't an unhandled async error.
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
    });
    // Keep presence fresh while parked — well under the backend's stale window.
    _heartbeat?.cancel();
    _heartbeat = Timer.periodic(const Duration(seconds: 15), (_) {
      final loc = _myLocation;
      if (loc == null || !mounted) return;
      context.read<DriverCubit>().sendLocation(loc.latitude, loc.longitude);
    });
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
    _stopStreamingLocation();
    super.dispose();
  }

  List<AppMapMarker> _markers(DriverState state) {
    final markers = <AppMapMarker>[];
    // The driver's own car — shown whenever we have a live fix and they're
    // online (so they can see themselves heading to the pickup).
    if (_myLocation != null && state.isOnline) {
      markers.add(AppMapMarker(
        point: _myLocation!,
        kind: MapMarkerKind.driver,
        label: 'You',
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
    final approaching = state.phase == DriverPhase.enRoute ||
        state.phase == DriverPhase.arrived;
    final encoded = approaching
        ? (state.approachPolyline ?? state.trip?.routePolyline)
        : state.trip?.routePolyline;
    if (encoded == null || encoded.isEmpty) return const [];
    return decodePolyline(encoded);
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
        } else if (state.error != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              // Float above the bottom sheet instead of covering its CTA.
              behavior: SnackBarBehavior.floating,
              margin: const EdgeInsets.fromLTRB(16, 0, 16, 300),
              content: Text(state.error!),
              // Route the driver straight to the fix when we refused to go
              // online for lack of location access.
              action: _locationFixAction(state.locationIssue),
              duration: state.locationIssue != null
                  ? const Duration(seconds: 8)
                  : const Duration(seconds: 4),
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
                // Follow the driver's own GPS while idle (online, no trip) so the
                // map tracks them instead of freezing on the opening centre. On a
                // trip, fitBounds frames pickup/route instead.
                recenter: (state.isOnline && state.trip == null)
                    ? _myLocation
                    : null,
                markers: _markers(state),
                route: _route(state),
                fitBounds: _fitBounds(state),
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
                        child: Row(
                          children: [
                            _StatusPill(online: state.isOnline),
                            const Spacer(),
                            AppCircleButton(
                              icon: Icons.menu_rounded,
                              tooltip: 'Account menu',
                              onPressed: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const AccountMenuPage(isDriver: true),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: _BottomSheet(state: state, myLocation: _myLocation),
              ),
              if (state.phase == DriverPhase.offered && state.offer != null)
                _OfferOverlay(offer: state.offer!),
            ],
          ),
        );
      },
    );
  }

  /// "Settings" for a permanent permission denial, "Turn on" when device
  /// location services are off; nothing for a plain (re-askable) denial.
  SnackBarAction? _locationFixAction(LocationAccess? issue) {
    switch (issue) {
      case LocationAccess.deniedForever:
      case LocationAccess.reduced:
        return SnackBarAction(
          label: 'Settings',
          onPressed: () => unawaited(Geolocator.openAppSettings()),
        );
      case LocationAccess.servicesOff:
        return SnackBarAction(
          label: 'Turn on',
          onPressed: () => unawaited(Geolocator.openLocationSettings()),
        );
      case LocationAccess.denied:
      case LocationAccess.granted:
      case null:
        return null;
    }
  }

  Future<void> _showOnboarding(BuildContext context) async {
    if (_onboardingShowing) return; // never stack a second copy
    _onboardingShowing = true;
    final cubit = context.read<DriverCubit>();
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => _OnboardingDialog(cubit: cubit),
      );
    } finally {
      _onboardingShowing = false;
    }
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet({required this.state, this.myLocation});
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
        child = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? AppColors.surfaceMutedDark
                        : AppColors.surfaceMutedLight,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bedtime_rounded,
                      color: theme.brightness == Brightness.dark
                          ? AppColors.textTertiaryDark
                          : AppColors.textTertiaryLight,
                      size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("You're offline",
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text(
                        state.lastEarned != null
                            ? 'Earned today · ${Fmt.money(state.lastEarned!)}'
                            : 'Go online to start earning',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            PrimaryButton(
              label: 'Go online',
              loading: state.busy,
              onPressed: state.busy ? null : () => cubit.goOnline(),
            ),
          ],
        );
      case DriverPhase.online:
      case DriverPhase.offered:
        child = Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  height: 46,
                  width: 46,
                  decoration: const BoxDecoration(
                    color: AppColors.accentSoft,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.wifi_tethering_rounded,
                      color: AppColors.accent, size: 24),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("You're online",
                          style: theme.textTheme.titleLarge),
                      const SizedBox(height: 2),
                      Text('Looking for trips nearby…',
                          style: theme.textTheme.bodyMedium),
                    ],
                  ),
                ),
                const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ],
            ),
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
          distanceLabel: _distanceLabel(myLocation, pickup, 'pickup'),
        );
      case DriverPhase.arrived:
        child = _StartTripSheet(
          cubit: cubit,
          busy: state.busy,
          tripId: state.trip?.id,
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
          distanceLabel: _distanceLabel(myLocation, dropoff, 'dropoff'),
        );
      case DriverPhase.completed:
        child = _CompletedSheet(state: state, cubit: cubit);
    }
    return AppSheet(child: child);
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
          child: Container(
            width: 60,
            height: 60,
            decoration: const BoxDecoration(
              color: AppColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
                color: AppColors.accent, size: 34),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Text('Trip complete', style: theme.textTheme.headlineSmall),
        ),
        if (state.lastEarned != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Center(
            child: Text(
                "Today's earnings · ${Fmt.money(state.lastEarned!)}",
                style: theme.textTheme.bodyMedium),
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
                const Icon(Icons.payments_rounded, color: AppColors.warning),
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
            onRate: state.riderRating == null
                ? (v) => cubit.rateRider(v)
                : null,
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
              child: Text(title, style: theme.textTheme.headlineSmall),
            ),
            if (tripId != null) ...[
              IconButton(
                tooltip: 'Safety',
                icon: const Icon(Icons.shield_outlined, color: AppColors.error),
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
              const Icon(Icons.near_me_rounded,
                  size: 16, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Text(distanceLabel!, style: theme.textTheme.titleSmall),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            if (navigateTo != null) ...[
              Expanded(
                child: SecondaryButton(
                  label: 'Navigate',
                  icon: Icons.navigation_rounded,
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
    final ok = await openTurnByTurn(lat: to.latitude, lng: to.longitude);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No navigation app could be opened')),
      );
    }
  }
}

/// "45 m to pickup" / "0.3 mi to dropoff" from the driver's own fix.
String? _distanceLabel(LatLng? from, LatLng? to, String what) {
  if (from == null || to == null) return null;
  final m = distanceMeters(from, to);
  if (m < 200) return '${m.round()} m to $what';
  return '${(m / 1609.344).toStringAsFixed(1)} mi to $what';
}

/// Opens the safety toolkit (SOS) for the driver's active trip. Drivers get the
/// same safety affordance riders have. Location is best-effort so an alert still
/// fires if GPS is momentarily unavailable.
Future<void> openDriverSafety(BuildContext context, String tripId) async {
  double? lat;
  double? lng;
  try {
    final pos = await Geolocator.getLastKnownPosition() ??
        await Geolocator.getCurrentPosition();
    lat = pos.latitude;
    lng = pos.longitude;
  } catch (_) {
    // best-effort — send the alert without coordinates
  }
  if (!context.mounted) return;
  await showSafetySheet(
    context,
    tripId: tripId,
    safety: sl<SafetyRemoteDataSource>(),
    shareText: 'I am driving a FairsVia trip and may need help. Trip $tripId.',
    lat: lat,
    lng: lng,
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
        chat: sl<ChatRemoteDataSource>(),
        realtime: sl<RealtimeClient>(),
      ),
    ),
  ).then((_) => cubit.setChatOpen(false)));
}

class _StartTripSheet extends StatefulWidget {
  const _StartTripSheet({required this.cubit, required this.busy, this.tripId});
  final DriverCubit cubit;
  final bool busy;
  final String? tripId;

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
              child: Text('Confirm rider', style: theme.textTheme.headlineSmall),
            ),
            if (widget.tripId != null) ...[
              IconButton(
                tooltip: 'Safety',
                icon: const Icon(Icons.shield_outlined, color: AppColors.error),
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
              const Icon(Icons.error_outline_rounded,
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
      ],
    );
  }
}

class _OfferOverlay extends StatefulWidget {
  const _OfferOverlay({required this.offer});
  final RideOffer offer;

  @override
  State<_OfferOverlay> createState() => _OfferOverlayState();
}

class _OfferOverlayState extends State<_OfferOverlay> {
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
    // An incoming offer is urgent and interrupting — announce it firmly.
    AppHaptics.heavy();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining -= 1);
      // A tick of warning as the window closes.
      if (_remaining > 0 && _remaining <= 3) AppHaptics.light();
      if (_remaining <= 0) {
        t.cancel();
        // Never auto-decline a ride the driver has already accepted.
        if (!_accepted) context.read<DriverCubit>().declineOffer();
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
    final miles = (offer.distanceM / 1609.34).toStringAsFixed(1);
    final low = _remaining <= 5;
    return Positioned.fill(
      child: Stack(
        children: [
          // Frosted, dimmed backdrop lifts the offer off the live map.
          const BlurredScrim(sigma: 8),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
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
                Text('\$${offer.fare.toStringAsFixed(2)}',
                    style: theme.textTheme.displaySmall),
                Text('Est. fare · $miles mi trip',
                    style: theme.textTheme.bodyMedium),
                // Who you're collecting + how far to reach them, so the driver
                // isn't accepting blind. Both omitted gracefully on old payloads.
                if (offer.riderName != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: [
                      Icon(Icons.person_rounded,
                          size: 16, color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(offer.riderName!,
                            style: theme.textTheme.bodyMedium,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (offer.riderRating != null) ...[
                        const SizedBox(width: 6),
                        const Icon(Icons.star_rounded,
                            size: 14, color: AppColors.star),
                        const SizedBox(width: 2),
                        Text(offer.riderRating!.toStringAsFixed(1),
                            style: theme.textTheme.labelLarge),
                      ],
                    ],
                  ),
                ],
                if (offer.approachLabel != null)
                  Text(offer.approachLabel!,
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: AppSpacing.lg),
                AppCard(
                  child: Row(
                    children: [
                      Container(
                        height: 36,
                        width: 36,
                        decoration: const BoxDecoration(
                          color: AppColors.accentSoft,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.trip_origin_rounded,
                            size: 18, color: AppColors.accent),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Pickup',
                                style: theme.textTheme.labelMedium),
                            const SizedBox(height: 2),
                            Text(offer.pickup.address ?? 'Pickup location',
                                style: theme.textTheme.titleSmall,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
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
            )
                .animate()
                .fadeIn(duration: AppMotion.fast)
                .scaleXY(
                  begin: 0.9,
                  end: 1,
                  duration: AppMotion.normal,
                  curve: AppMotion.emphasized,
                ),
          ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingDialog extends StatefulWidget {
  const _OnboardingDialog({required this.cubit});
  final DriverCubit cubit;

  @override
  State<_OnboardingDialog> createState() => _OnboardingDialogState();
}

class _OnboardingDialogState extends State<_OnboardingDialog> {
  final _make = TextEditingController(text: 'Toyota');
  final _model = TextEditingController(text: 'Camry');
  final _plate = TextEditingController(text: 'FLA 1234');
  String _tier = 'economy';

  @override
  void dispose() {
    _make.dispose();
    _model.dispose();
    _plate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Set up your vehicle'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: _make, decoration: const InputDecoration(labelText: 'Make')),
          const SizedBox(height: AppSpacing.sm),
          TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model')),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: _plate,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(labelText: 'Plate number'),
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _tier,
            decoration: const InputDecoration(labelText: 'Tier'),
            items: const [
              DropdownMenuItem(value: 'economy', child: Text('Economy')),
              DropdownMenuItem(value: 'comfort', child: Text('Comfort')),
              DropdownMenuItem(value: 'xl', child: Text('XL')),
              DropdownMenuItem(value: 'premium', child: Text('Premium')),
            ],
            onChanged: (v) => setState(() => _tier = v ?? 'economy'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            widget.cubit.onboard(
              make: _make.text,
              model: _model.text,
              plate: _plate.text,
              tier: _tier,
            );
            Navigator.of(context).pop();
          },
          child: const Text('Save & go online'),
        ),
      ],
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
    const icon = Icon(Icons.chat_bubble_rounded);
    if (unread <= 0) return icon;
    return Badge.count(count: unread, child: icon);
  }
}
