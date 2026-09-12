import 'dart:async';

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

class _DriverHomeViewState extends State<_DriverHomeView> {
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

  // --- Live re-routing ---
  // When the driver leaves the drawn route (takes a different/shorter road), we
  // re-fetch the optimal road route from where they actually are, so the line
  // relocates onto the road taken. [_rerouteGate] rate-limits it.
  final RerouteGate _rerouteGate = RerouteGate();
  String? _liveRoutePolyline;
  String? _liveRouteLeg;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    try {
      final token = await sl<TokenStorage>().readAccessToken();
      if (token != null && mounted) {
        await context.read<DriverCubit>().init(token);
      }
    } catch (_) {
      // Connect can time out; the realtime client retries with backoff and the
      // connection banner reflects status. Swallow so a slow/failed initial
      // connect isn't an unhandled async error.
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
          );
      // Keep the drawn line on the road actually being driven.
      unawaited(_maybeReroute(context.read<DriverCubit>().state));
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
    // Simulated driving already yields the shrinking remaining path.
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

  /// Frame the map for the current phase: heading to pickup → show the driver +
  /// the pickup; on a trip → show the whole route.
  List<LatLng>? _fitBounds(DriverState state) {
    final trip = state.trip;
    if (trip == null) return null;
    final pickup = LatLng(trip.pickup.point.lat, trip.pickup.point.lng);
    final dropoff = LatLng(trip.dropoff.point.lat, trip.dropoff.point.lng);
    if ((state.phase == DriverPhase.enRoute ||
            state.phase == DriverPhase.arrived) &&
        _myLocation != null) {
      return [_myLocation!, pickup];
    }
    return [pickup, dropoff];
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
        final trip = state.trip;
        if (trip != null) {
          if (state.phase == DriverPhase.enRoute) {
            driveSimulatedPath(_pathTo(
              state.approachPolyline,
              trip.pickup.point.lat,
              trip.pickup.point.lng,
            ));
          } else if (state.phase == DriverPhase.onTrip) {
            driveSimulatedPath(_pathTo(
              trip.routePolyline,
              trip.dropoff.point.lat,
              trip.dropoff.point.lng,
            ));
          }
        }
        if (state.needsOnboarding) {
          _showOnboarding(context);
        } else if (state.error != null) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(state.error!)));
        }
      },
      builder: (context, state) {
        return Scaffold(
          body: Stack(
            children: [
              // Real OpenStreetMap tiles (no API key) — renders on mobile + web.
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
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ConnectionBanner(connected: state.connected),
              ),
              SafeArea(
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
              Align(
                alignment: Alignment.bottomCenter,
                child: _BottomSheet(state: state),
              ),
              if (state.phase == DriverPhase.offered && state.offer != null)
                _OfferOverlay(offer: state.offer!),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showOnboarding(BuildContext context) async {
    final cubit = context.read<DriverCubit>();
    await showDialog<void>(
      context: context,
      builder: (_) => _OnboardingDialog(cubit: cubit),
    );
  }
}

class _BottomSheet extends StatelessWidget {
  const _BottomSheet({required this.state});
  final DriverState state;

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
                  decoration: const BoxDecoration(
                    color: AppColors.surfaceMutedLight,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.bedtime_rounded,
                      color: AppColors.textTertiaryLight, size: 24),
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
                            ? 'Earned today · \$${state.lastEarned!.toStringAsFixed(0)}'
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
        child = _LifecycleSheet(
          title: 'Head to pickup',
          subtitle: state.trip?.pickup.address ?? 'Pickup location',
          actionLabel: 'Arrived',
          busy: state.busy,
          onAction: () => cubit.markArrived(),
          tripId: state.trip?.id,
        );
      case DriverPhase.arrived:
        child = _StartTripSheet(
          cubit: cubit,
          busy: state.busy,
          tripId: state.trip?.id,
        );
      case DriverPhase.onTrip:
        child = _LifecycleSheet(
          title: 'On trip',
          subtitle: state.trip?.dropoff.address ?? 'Dropoff location',
          actionLabel: 'Complete trip',
          busy: state.busy,
          onAction: () => cubit.completeTrip(),
          tripId: state.trip?.id,
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
                "Today's earnings · \$${state.lastEarned!.toStringAsFixed(0)}",
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
                    'Collect \$${state.cashToCollect!.toStringAsFixed(0)} in cash from the rider',
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
  });

  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onAction;
  final bool busy;
  final String? tripId;

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
                icon: const Icon(Icons.chat_bubble_rounded),
                onPressed: () => openDriverChat(context, tripId!),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: actionLabel,
          loading: busy,
          onPressed: busy ? null : onAction,
        ),
      ],
    );
  }
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
    shareText: 'I am driving a Ride App trip and may need help. Trip $tripId.',
    lat: lat,
    lng: lng,
  );
}

/// Opens the in-trip chat with the rider.
void openDriverChat(BuildContext context, String tripId) {
  final userId = context.read<AuthBloc>().state.user?.id;
  if (userId == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatPage(
        tripId: tripId,
        currentUserId: userId,
        title: 'Rider',
        chat: sl<ChatRemoteDataSource>(),
        realtime: sl<RealtimeClient>(),
      ),
    ),
  );
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
                icon: const Icon(Icons.chat_bubble_rounded),
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
            length: _startCodeLength,
            onChanged: (v) => setState(() => _otp = v)),
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
                              backgroundColor: AppColors.borderLight,
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
          TextField(controller: _model, decoration: const InputDecoration(labelText: 'Model')),
          TextField(controller: _plate, decoration: const InputDecoration(labelText: 'Plate number')),
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
