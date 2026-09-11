import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_models/shared_models.dart';

import 'features/trip/destination_search_page.dart';
import 'features/trip/location_service.dart';
import 'features/trip/map_utils.dart';
import 'features/trip/price_comparison_card.dart';
import 'features/trip/trip_cubit.dart';

/// Rider home: full-screen map with a bottom sheet that changes with the
/// request phase (where-to → choose ride → finding driver).
/// Share of the screen the ride-options sheet may take, so the route stays
/// visible above it (also drives the map's bottom fit padding).
const double kRideOptionsSheetFraction = 0.58;

class RiderHomePage extends StatelessWidget {
  const RiderHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => TripCubit(
        sl<TripRepository>(),
        sl<RealtimeClient>(),
        sl<PaymentsRemoteDataSource>(),
        sl<RatingsRemoteDataSource>(),
      ),
      child: const _RiderHomeView(),
    );
  }
}

class _RiderHomeView extends StatefulWidget {
  const _RiderHomeView();

  @override
  State<_RiderHomeView> createState() => _RiderHomeViewState();
}

class _RiderHomeViewState extends State<_RiderHomeView>
    with WidgetsBindingObserver {
  final _location = LocationService();
  GeoPoint _myLocation = LocationService.fallback;
  String _myLocationAddr = 'Current location';
  List<SavedPlace> _savedPlaces = const [];
  // Set when the rider taps "recenter": AppMap follows this to snap back to the
  // rider's live position after they've panned the map away. `_recenterSeq` is
  // bumped with every request because LatLng has value equality — re-storing
  // the same point (GPS hasn't moved, or MOCK_LOCATION) would otherwise be a
  // no-op and the button would feel dead.
  LatLng? _recenter;
  int _recenterSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadLocation();
    _loadSavedPlaces();
    _connectSocket();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // iOS kills the WebSocket while the app is suspended; re-establish it on
    // resume so live trip updates don't stay dead until a manual restart.
    if (state == AppLifecycleState.resumed) _resumeSocket();
  }

  Future<void> _resumeSocket() async {
    final token = await sl<TokenStorage>().readAccessToken();
    if (token != null && mounted) {
      await context.read<TripCubit>().resumeFromBackground(token);
    }
  }

  Future<void> _loadLocation() async {
    final loc = await _location.currentOrFallback();
    if (mounted) {
      setState(() {
        _myLocation = loc;
        // Move the camera to the resolved location. GoogleMap's initialCenter is
        // one-shot, so without this the map stays on the fallback until the rider
        // taps recenter (seen when GPS/permission resolves after the first frame).
        _recenter = MapUtils.toLatLng(loc);
        _recenterSeq++;
      });
    }
    // Resolve the GPS to a real address so the pickup shows where the rider
    // actually is (e.g. "Bhukum, Pune") instead of a generic label.
    try {
      final place = await sl<TripRepository>().reverseGeocode(loc.lat, loc.lng);
      if (mounted && place.address.isNotEmpty) {
        setState(() => _myLocationAddr = place.address);
      }
    } catch (_) {
      // Non-fatal: keep the generic label if reverse-geocoding fails.
    }
  }

  /// Recenter the map on the rider's current location (refreshes GPS first).
  Future<void> _recenterToMe() async {
    final loc = await _location.currentOrFallback();
    if (!mounted) return;
    setState(() {
      _myLocation = loc;
      _recenter = MapUtils.toLatLng(loc);
      _recenterSeq++;
    });
  }

  Future<void> _loadSavedPlaces() async {
    try {
      final places = await sl<UsersRemoteDataSource>().listPlaces();
      if (mounted) setState(() => _savedPlaces = places);
    } catch (_) {
      // Quick-picks are a convenience; a load failure just hides them.
    }
  }

  /// Start a ride to a saved place directly from the home sheet.
  Future<void> _pickSaved(SavedPlace place) async {
    await context.read<TripCubit>().chooseDestination(
          pickup: _myLocation,
          pickupAddr: _myLocationAddr,
          dropoff: place.point,
          dropoffAddr: place.address ?? place.label,
        );
  }

  Future<void> _connectSocket() async {
    try {
      final token = await sl<TokenStorage>().readAccessToken();
      if (token != null && mounted) {
        await context.read<TripCubit>().init(
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

  Future<void> _openSearch() async {
    final choice = await Navigator.of(context).push<RouteChoice>(
      MaterialPageRoute(
        builder: (_) => DestinationSearchPage(
          initialPickup: _myLocation,
          initialPickupLabel: _myLocationAddr,
        ),
      ),
    );
    if (choice != null && mounted) {
      await context.read<TripCubit>().chooseDestination(
            pickup: choice.pickup,
            pickupAddr: choice.pickupAddr,
            dropoff: choice.dropoff,
            dropoffAddr: choice.dropoffAddr,
          );
    }
  }

  List<AppMapMarker> _markers(TripState state) {
    final markers = <AppMapMarker>[];
    if (state.pickup != null) {
      markers.add(AppMapMarker(
        point: MapUtils.toLatLng(state.pickup!),
        kind: MapMarkerKind.pickup,
        label: 'Pickup',
      ));
    }
    if (state.dropoff != null) {
      markers.add(AppMapMarker(
        point: MapUtils.toLatLng(state.dropoff!),
        kind: MapMarkerKind.dropoff,
        label: 'Destination',
      ));
    }
    if (state.driverLocation != null) {
      markers.add(AppMapMarker(
        point: MapUtils.toLatLng(state.driverLocation!),
        kind: MapMarkerKind.driver,
        label: 'Driver',
      ));
    }
    return markers;
  }

  List<LatLng> _route(TripState state) {
    // While the driver is on the way, draw THEIR route to the pickup (the
    // approach leg) so the line matches where the car is actually going; once
    // the trip starts, fall back to the pickup→destination trip route.
    final approaching = state.phase == TripPhase.driverEnRoute ||
        state.phase == TripPhase.driverArrived;
    final approachRoute = state.driverRoutePolyline;
    // After a cold-start restore there is no estimate; the trip carries its own
    // route polyline, so fall back to that rather than drawing nothing.
    final encoded = (approaching &&
            approachRoute != null &&
            approachRoute.isNotEmpty)
        ? approachRoute
        : (state.estimate?.polyline ?? state.trip?.routePolyline);
    if (encoded == null || encoded.isEmpty) return const [];
    return MapUtils.decodePolyline(encoded);
  }

  /// What the camera frames. During the approach we fit the driver→pickup leg
  /// (using the approach polyline's endpoints, which stay fixed for the whole
  /// approach — so the camera frames the leg once instead of chasing the car
  /// on every GPS tick). Otherwise we fit pickup→dropoff.
  List<LatLng>? _fitBounds(TripState state) {
    // Prefer the estimate's endpoints; after a cold-start restore there is no
    // estimate, so frame the restored trip's pickup/dropoff instead.
    final pickup = state.estimate?.pickup ?? state.pickup;
    final dropoff = state.estimate?.dropoff ?? state.dropoff;
    if (pickup == null || dropoff == null) return null;
    final approaching = state.phase == TripPhase.driverEnRoute ||
        state.phase == TripPhase.driverArrived;
    final approachRoute = state.driverRoutePolyline;
    if (approaching && approachRoute != null && approachRoute.isNotEmpty) {
      final pts = MapUtils.decodePolyline(approachRoute);
      if (pts.length >= 2) return [pts.first, pts.last];
    }
    return [MapUtils.toLatLng(pickup), MapUtils.toLatLng(dropoff)];
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<TripCubit, TripState>(
        listenWhen: (prev, curr) => prev.phase != curr.phase,
        listener: (context, state) {
          // Back to idle (change destination / cancel / done): the camera was
          // fitted to the route bounds — bring it back to the rider instead of
          // leaving it zoomed out over the whole route.
          if (state.phase == TripPhase.idle) _recenterToMe();
          // Tactile punctuation on the moments that matter in the ride flow.
          switch (state.phase) {
            case TripPhase.driverEnRoute:
              AppHaptics.success(); // a driver accepted — you're matched
            case TripPhase.driverArrived:
              AppHaptics.medium(); // your driver is here
            case TripPhase.completed:
              AppHaptics.success(); // trip done
            case TripPhase.error:
              AppHaptics.heavy();
            case _:
              break;
          }
        },
        builder: (context, state) {
          return Scaffold(
            body: Stack(
              children: [
                // Google Maps SDK via the shared AppMap (native on mobile, JS
                // on web) — the basemap is styled per theme inside AppMap.
                AppMap(
                  initialCenter: MapUtils.toLatLng(_myLocation),
                  markers: _markers(state),
                  route: _route(state),
                  fitBounds: _fitBounds(state),
                  recenter: _recenter,
                  recenterSeq: _recenterSeq,
                  // Keep pickup/dropoff/driver markers framed above the bottom
                  // sheet (which covers ~40% of the screen) rather than behind it.
                  boundsPadding: EdgeInsets.fromLTRB(
                    40,
                    96,
                    40,
                    // Match the sheet actually on screen in this phase so the
                    // fitted route lands in the visible strip of map.
                    state.phase == TripPhase.choosingRide
                        ? MediaQuery.sizeOf(context).height *
                                kRideOptionsSheetFraction +
                            24
                        : 300,
                  ),
                ),
                // Banner and top controls share one column so the
                // "Reconnecting…" bar pushes the buttons down instead of being
                // drawn underneath them. The banner pads for the status bar
                // itself, so the controls only take the inset while it's hidden.
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
                          child: Align(
                            alignment: Alignment.topRight,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppCircleButton(
                                  icon: Icons.menu_rounded,
                                  tooltip: 'Account menu',
                                  onPressed: () async {
                                    await Navigator.of(context).push(
                                      MaterialPageRoute(
                                        builder: (_) => const AccountMenuPage(
                                            isDriver: false),
                                      ),
                                    );
                                    // Saved places may have changed in the
                                    // account pages; refresh the quick-picks.
                                    _loadSavedPlaces();
                                  },
                                ),
                                const SizedBox(height: AppSpacing.sm),
                                AppCircleButton(
                                  icon: Icons.my_location_rounded,
                                  tooltip: 'Recenter on my location',
                                  onPressed: _recenterToMe,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Align(
                  alignment: Alignment.bottomCenter,
                  child: _BottomSheetForPhase(
                    state: state,
                    onSearch: _openSearch,
                    savedPlaces: _savedPlaces,
                    onPickSaved: _pickSaved,
                  ),
                ),
              ],
            ),
          );
        },
    );
  }
}

class _BottomSheetForPhase extends StatelessWidget {
  const _BottomSheetForPhase({
    required this.state,
    required this.onSearch,
    this.savedPlaces = const [],
    required this.onPickSaved,
  });

  final TripState state;
  final VoidCallback onSearch;
  final List<SavedPlace> savedPlaces;
  final ValueChanged<SavedPlace> onPickSaved;

  @override
  Widget build(BuildContext context) {
    final child = switch (state.phase) {
      TripPhase.idle => _WhereToCard(
          onTap: onSearch,
          savedPlaces: savedPlaces,
          onPickSaved: onPickSaved,
        ),
      TripPhase.loadingEstimate =>
        const _InfoCard(child: _Busy(label: 'Finding the best route…')),
      TripPhase.choosingRide => _RideOptions(state: state),
      TripPhase.requesting =>
        const _InfoCard(child: _Busy(label: 'Requesting your ride…')),
      TripPhase.scheduled => _ScheduledConfirmation(state: state),
      TripPhase.searching => _FindingDriver(state: state),
      TripPhase.driverEnRoute => _DriverInfoSheet(state: state, arrived: false),
      TripPhase.driverArrived => _DriverInfoSheet(state: state, arrived: true),
      TripPhase.onTrip => _OnTripSheet(state: state),
      TripPhase.completed => _CompletedSheet(state: state),
      TripPhase.error => _ErrorCard(
          message: state.error ?? 'Something went wrong',
          onRetry: onSearch,
        ),
    };
    // Cross-fade + slide between phases, and smoothly resize the sheet as each
    // phase's content changes height — so the flow feels like one continuous
    // surface rather than a stack of hard-swapped cards.
    return AppSheet(
      // Keep the routed map visible while choosing a ride: the options sheet
      // is otherwise tall enough to hide the route and both markers.
      maxHeightFraction:
          state.phase == TripPhase.choosingRide ? kRideOptionsSheetFraction : null,
      footer: state.phase == TripPhase.choosingRide && state.estimate != null
          ? _RideConfirmFooter(state: state)
          : null,
      child: AnimatedSize(
        duration: AppMotion.normal,
        curve: AppMotion.standard,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: AppMotion.normal,
          switchInCurve: AppMotion.emphasized,
          switchOutCurve: AppMotion.exit,
          transitionBuilder: (child, anim) => FadeTransition(
            opacity: anim,
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.06),
                end: Offset.zero,
              ).animate(anim),
              child: child,
            ),
          ),
          layoutBuilder: (currentChild, previousChildren) => Stack(
            alignment: Alignment.bottomCenter,
            children: [
              ...previousChildren,
              ?currentChild,
            ],
          ),
          child: KeyedSubtree(key: ValueKey(state.phase), child: child),
        ),
      ),
    );
  }
}

class _WhereToCard extends StatelessWidget {
  const _WhereToCard({
    required this.onTap,
    this.savedPlaces = const [],
    required this.onPickSaved,
  });

  final VoidCallback onTap;
  final List<SavedPlace> savedPlaces;
  final ValueChanged<SavedPlace> onPickSaved;

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work') return Icons.work_outline;
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Where to?', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.lg),
        // Search pill.
        Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceMutedDark
                  : AppColors.surfaceMutedLight,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: AppColors.accent, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    Text('Enter your destination',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (savedPlaces.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          for (final place in savedPlaces) ...[
            _QuickDestination(
              icon: _iconFor(place.label),
              label: place.label,
              subtitle: place.address,
              onTap: () => onPickSaved(place),
            ),
            if (place != savedPlaces.last)
              Divider(height: 1, color: theme.dividerColor),
          ],
        ],
      ],
    );
  }
}

/// A saved-place row (Home / Work / …) shown under the search pill.
class _QuickDestination extends StatelessWidget {
  const _QuickDestination({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceMutedDark
                    : AppColors.surfaceMutedLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _RideOptions extends StatelessWidget {
  const _RideOptions({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final estimate = state.estimate!;
    final cubit = context.read<TripCubit>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Text('Choose a ride', style: theme.textTheme.headlineSmall),
            const Spacer(),
            Text(
              '${estimate.distanceMi.toStringAsFixed(1)} mi · '
              '${(estimate.durationS / 60).round()} min',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        if (estimate.surge > 1.0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Fares are higher due to demand (${estimate.surge.toStringAsFixed(1)}x)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.warning),
            ),
          ),
        // Surfaced when a request comes back with no drivers (or a create error);
        // the ride is kept so the rider can just re-tap Confirm.
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(state.error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.warning)),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _StopsSection(state: state),
        const SizedBox(height: AppSpacing.sm),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 264),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final (i, tier) in estimate.tiers.indexed)
                _RideTierTile(
                  tier: tier,
                  selected: tier.tier == state.selectedTier,
                  onTap: () {
                    AppHaptics.selection();
                    cubit.selectTier(tier.tier);
                  },
                ).animate().fadeIn(
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                    ).moveY(
                      begin: 8,
                      end: 0,
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                      curve: AppMotion.emphasized,
                    ),
            ],
          ),
        ),
        if (estimate.comparison != null) ...[
          const SizedBox(height: AppSpacing.sm),
          PriceComparisonCard(comparison: estimate.comparison!),
        ],
        const SizedBox(height: AppSpacing.sm),
        _PaymentModeToggle(state: state),
        const SizedBox(height: AppSpacing.sm),
        _ScheduleRow(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PromoField(state: state),
      ],
    );
  }
}

/// Pinned footer for the ride-options sheet: the confirm CTA and the
/// "change destination" escape hatch stay visible even when the options
/// above (surge line, stops, comparison card, promo) overflow and scroll.
class _RideConfirmFooter extends StatelessWidget {
  const _RideConfirmFooter({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripCubit>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PrimaryButton(
          label: _confirmLabel(state),
          onPressed:
              state.selectedTier != null ? () => cubit.confirmRide() : null,
        ),
        TextButton(
          onPressed: () => cubit.reset(),
          child: const Text('Change destination'),
        ),
      ],
    );
  }
}

/// Multi-stop editor: lists current stops with remove buttons and an "Add stop"
/// action (opens the destination search) up to the backend cap.
class _StopsSection extends StatelessWidget {
  const _StopsSection({required this.state});
  final TripState state;

  Future<void> _addStop(BuildContext context) async {
    final cubit = context.read<TripCubit>();
    final details = await Navigator.of(context).push<PlaceDetails>(
      MaterialPageRoute(
        builder: (_) => const DestinationSearchPage(singleDestination: true),
      ),
    );
    if (details != null) {
      await cubit.addStop(
        TripStop(point: details.location, address: details.address),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final canAdd = state.stops.length < TripCubit.maxStops;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < state.stops.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: Row(
              children: [
                const Icon(Icons.trip_origin, size: 16),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    state.stops[i].address ?? 'Stop ${i + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                InkWell(
                  onTap: () => cubit.removeStop(i),
                  child: const Icon(Icons.close, size: 16),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: canAdd ? () => _addStop(context) : null,
            icon: const Icon(Icons.add_location_alt_outlined, size: 18),
            label: Text(canAdd ? 'Add stop' : 'Max 3 stops'),
          ),
        ),
      ],
    );
  }
}

String _confirmLabel(TripState state) {
  final fare = state.selectedFare;
  if (fare == null) return 'Confirm';
  final net = state.discountedFare ?? fare.fare;
  final amount = (state.appliedPromo != null && net != fare.fare)
      ? net
      : fare.fare;
  final verb = state.scheduledAt != null ? 'Schedule' : 'Confirm';
  return '$verb ${fare.label} · \$${_money(amount)}';
}

String _formatSchedule(DateTime when) {
  final local = when.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final min = local.minute.toString().padLeft(2, '0');
  return '${months[local.month - 1]} ${local.day}, $h:$min $ampm';
}

/// "Ride now" vs "Schedule for …" row with a date/time picker.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.state});
  final TripState state;

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<TripCubit>();
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
      initialDate: now.add(const Duration(hours: 1)),
    );
    if (date == null || !context.mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    );
    if (time == null) return;
    final when = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Must be at least 5 minutes ahead (backend rule). Clamp with a minute of
    // slack: clamping to exactly now+5 and sending a few seconds later was
    // rejected by the backend with a 400.
    if (when.isBefore(now.add(const Duration(minutes: 6)))) {
      cubit.setScheduledAt(now.add(const Duration(minutes: 6)));
    } else {
      cubit.setScheduledAt(when);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final when = state.scheduledAt;
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.schedule, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                when == null ? 'Ride now' : 'For ${_formatSchedule(when)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (when != null)
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                tooltip: 'Ride now instead',
                onPressed: () => cubit.setScheduledAt(null),
              )
            else
              Text('Schedule',
                  style: theme.textTheme.labelLarge
                      ?.copyWith(color: AppColors.accent)),
          ],
        ),
      ),
    );
  }
}

/// Shown after a future ride is booked.
class _ScheduledConfirmation extends StatelessWidget {
  const _ScheduledConfirmation({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final when = state.trip?.scheduledAt ?? state.scheduledAt;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Icon(Icons.event_available, color: AppColors.accent, size: 48),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text('Ride scheduled', style: theme.textTheme.headlineSmall),
        ),
        const SizedBox(height: AppSpacing.sm),
        if (when != null)
          Center(
            child: Text(
              'We’ll find you a driver around\n${_formatSchedule(when)}',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: 'Done', onPressed: () => cubit.reset()),
      ],
    );
  }
}

/// Card / Cash selector for the ride-options sheet.
class _PaymentModeToggle extends StatelessWidget {
  const _PaymentModeToggle({required this.state});
  final TripState state;

  /// The saved card currently in effect: the explicitly chosen one, else the
  /// default, else the first. Null when there are no saved cards.
  Map<String, dynamic>? get _activeCard {
    final cards = state.paymentMethods;
    if (cards.isEmpty) return null;
    final id = state.selectedMethodId;
    if (id != null) {
      for (final c in cards) {
        if (c['id'] == id) return c;
      }
    }
    for (final c in cards) {
      if (c['isDefault'] == true) return c;
    }
    return cards.first;
  }

  static String _cardLabel(Map<String, dynamic> c) {
    final brand = (c['brand'] as String?)?.trim();
    final last4 = (c['last4'] as String?)?.trim();
    final b = (brand == null || brand.isEmpty) ? 'Card' : brand;
    return last4 == null || last4.isEmpty ? b : '$b •••• $last4';
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripCubit>();
    final card = _activeCard;
    final cardSelected = state.paymentMode == 'card';
    final cardLabel = card == null ? 'Card' : _cardLabel(card);
    // With >1 saved card, tapping Card opens a picker; otherwise it just
    // selects card mode (backend uses the default / mock method).
    final hasChoice = state.paymentMethods.length > 1;
    return Row(
      children: [
        Expanded(
          child: _PayChip(
            icon: Icons.credit_card,
            label: cardLabel,
            selected: cardSelected,
            trailing: hasChoice ? Icons.expand_more : null,
            onTap: () {
              if (hasChoice) {
                _showCardPicker(context, cubit);
              } else {
                cubit.setPaymentMode('card');
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _PayChip(
            icon: Icons.payments_outlined,
            label: 'Cash',
            selected: state.paymentMode == 'cash',
            onTap: () => cubit.setPaymentMode('cash'),
          ),
        ),
      ],
    );
  }

  Future<void> _showCardPicker(BuildContext context, TripCubit cubit) async {
    final cards = state.paymentMethods;
    final activeId = _activeCard?['id'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: Text('Pay with',
                    style: theme.textTheme.titleMedium),
              ),
              for (final c in cards)
                ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: Text(_cardLabel(c)),
                  trailing: c['id'] == activeId
                      ? const Icon(Icons.check, color: AppColors.accent)
                      : null,
                  onTap: () {
                    AppHaptics.selection();
                    cubit.selectPaymentCard(c['id'] as String);
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? (theme.brightness == Brightness.dark
                  ? AppColors.accentSoftDark
                  : AppColors.accentSoft)
              : null,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: selected ? AppColors.accent : theme.dividerColor,
            width: 2,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? AppColors.accent : null),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: selected ? AppColors.accent : null,
                ),
              ),
            ),
            if (trailing != null)
              Icon(trailing,
                  size: 18, color: selected ? AppColors.accent : null),
          ],
        ),
      ),
    );
  }
}

/// Promo-code entry for the ride-options sheet. Shows an input + Apply button
/// until a code is accepted, then a green applied-chip with a remove action.
class _PromoField extends StatefulWidget {
  const _PromoField({required this.state});
  final TripState state;

  @override
  State<_PromoField> createState() => _PromoFieldState();
}

class _PromoFieldState extends State<_PromoField> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final promo = widget.state.appliedPromo;

    if (promo != null) {
      return Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          color: AppColors.success.withValues(alpha: 0.12),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer, size: 18, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${promo.code} applied · −\$${promo.discount.toStringAsFixed(0)}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.success),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: 'Remove promo',
              onPressed: cubit.removePromo,
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  hintText: 'Promo code',
                  prefixIcon: Icon(Icons.local_offer_outlined),
                  isDense: true,
                ),
                onSubmitted: (v) => cubit.applyPromo(v),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            TextButton(
              onPressed: widget.state.applyingPromo
                  ? null
                  : () => cubit.applyPromo(_controller.text),
              child: widget.state.applyingPromo
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Apply'),
            ),
          ],
        ),
        if (widget.state.promoError != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(
              widget.state.promoError!,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

class _RideTierTile extends StatelessWidget {
  const _RideTierTile({
    required this.tier,
    required this.selected,
    required this.onTap,
  });

  final FareTier tier;
  final bool selected;
  final VoidCallback onTap;

  IconData get _icon {
    switch (tier.tier) {
      case 'comfort':
        return Icons.local_taxi_rounded;
      case 'xl':
        return Icons.airport_shuttle_rounded;
      case 'premium':
        return Icons.auto_awesome_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        selected: selected,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        // Theme-aware selected fill: a light mint in light mode, a dark-green
        // tint in dark mode — otherwise the (light) on-surface text would sit on
        // a light mint fill in dark mode and wash out. Mirrors _PayChip.
        color: selected
            ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
            : null,
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.accent.withValues(alpha: 0.16)
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              ),
              child: Icon(_icon,
                  size: 26,
                  color: selected
                      ? AppColors.accent
                      : theme.colorScheme.onSurface),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tier.label, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 1),
                  Text(
                    '${tier.capacity} seats · ${(tier.etaSeconds / 60).round()} min away',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '\$${tier.fare.toStringAsFixed(0)}',
              style: theme.textTheme.titleLarge?.tabular(),
            ),
          ],
        ),
      ),
    );
  }
}

class _FindingDriver extends StatelessWidget {
  const _FindingDriver({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Animated radar sweeping for a nearby driver — reads as the system
            // actively looking, not a generic spinner.
            const PulseRadar(
              size: 56,
              child: Icon(Icons.local_taxi_rounded,
                  size: 20, color: AppColors.accent),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Finding your driver',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: 2),
                  Text(
                    'Trip to ${state.dropoffAddr ?? 'your destination'}',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        SecondaryButton(
          label: 'Cancel ride',
          onPressed: () => _confirmCancel(context, feeWarning: false),
        ),
      ],
    );
  }
}

/// Confirms a ride cancellation before calling through. When a driver is already
/// on the way ([feeWarning]), warns that a cancellation fee may apply, then — if
/// one was charged — tells the rider the exact amount. Prevents a silent charge.
Future<void> _confirmCancel(BuildContext context, {required bool feeWarning}) async {
  final messenger = ScaffoldMessenger.of(context);
  final cubit = context.read<TripCubit>();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (_) => CancelRideDialog(cubit: cubit, feeWarning: feeWarning),
  );
  if (confirmed != true) return;
  final fee = await cubit.cancelTrip();
  if (fee > 0) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'Ride cancelled. A \$${fee.toStringAsFixed(2)} cancellation fee was charged.',
        ),
      ),
    );
  }
}

/// "Cancel this ride?" prompt. If the trip ends underneath it (driver
/// cancelled, no-drivers timeout, trip completed) it closes itself instead
/// of leaving a stale prompt whose "Cancel ride" would reset a flow that
/// already moved on. The self-close is guarded so it never pops a dialog
/// the user already dismissed (that raced the navigator and crashed the
/// page with `!_debugLocked` when confirming a cancel).
class CancelRideDialog extends StatelessWidget {
  const CancelRideDialog({
    super.key,
    required this.cubit,
    required this.feeWarning,
  });

  final TripCubit cubit;
  final bool feeWarning;

  @override
  Widget build(BuildContext context) {
    return BlocListener<TripCubit, TripState>(
      bloc: cubit,
      listenWhen: (prev, curr) =>
          TripCubit.isCancellable(prev.phase) &&
          !TripCubit.isCancellable(curr.phase),
      listener: (ctx, _) {
        if (!ctx.mounted) return;
        final route = ModalRoute.of(ctx);
        // Already popped (or mid-pop) by a button: nothing to close.
        if (route == null || !route.isCurrent || !route.isActive) return;
        Navigator.of(ctx).pop(false);
      },
      child: AlertDialog(
        title: const Text('Cancel this ride?'),
        content: Text(
          feeWarning
              ? 'Your driver is already on the way. Cancelling now may charge a '
                  'cancellation fee.'
              : 'Are you sure you want to cancel this ride?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
  }
}

class _DriverInfoSheet extends StatelessWidget {
  const _DriverInfoSheet({required this.state, required this.arrived});
  final TripState state;
  final bool arrived;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driver = state.driver;
    final otp = state.trip?.startOtp;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppStatusChip(
                    label: arrived ? 'Arrived' : 'On the way',
                    tone: arrived ? StatusTone.success : StatusTone.accent,
                    icon: arrived
                        ? Icons.check_circle_rounded
                        : Icons.directions_car_rounded,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    arrived
                        ? 'Your driver is here'
                        // Live "Arriving in N min" from the backend approach ETA
                        // when known, else a generic status.
                        : (driver?.etaLabel ?? 'Your driver is on the way'),
                    style: theme.textTheme.headlineSmall,
                  ),
                ],
              ),
            ),
            _sosButton(context, state),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        AppCard(
          child: Row(
            children: [
              AppAvatar(name: driver?.name, size: 52),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(driver?.name ?? 'Your driver',
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 15, color: AppColors.star),
                        const SizedBox(width: 3),
                        // No driver payload yet (e.g. restored after a cold
                        // start) — show "—" rather than inventing a 5.0.
                        Text(
                            driver == null
                                ? '—'
                                : driver.rating.toStringAsFixed(1),
                            style: theme.textTheme.labelLarge),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(driver?.vehicleLabel ?? '',
                      style: theme.textTheme.bodyMedium),
                  if (driver?.plate != null) ...[
                    const SizedBox(height: 2),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm, vertical: 3),
                      decoration: BoxDecoration(
                        color: theme.brightness == Brightness.dark
                            ? AppColors.surfaceMutedDark
                            : AppColors.surfaceMutedLight,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(
                            color: theme.brightness == Brightness.dark
                                ? AppColors.borderDark
                                : AppColors.borderLight),
                      ),
                      child: Text(driver!.plate!,
                          style: theme.textTheme.titleSmall
                              ?.copyWith(letterSpacing: 1)),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
        if (otp != null) ...[
          const SizedBox(height: AppSpacing.md),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg, vertical: AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accentSoft,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(
              children: [
                const Icon(Icons.lock_rounded,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text('Share this start code with your driver',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: AppColors.accentPressed)),
                ),
                Text(otp,
                    style: theme.textTheme.headlineSmall?.copyWith(
                        letterSpacing: 6, color: AppColors.accentPressed)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: 'Message',
                icon: Icons.chat_bubble_rounded,
                onPressed: () => _openTripChat(context, state),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: SecondaryButton(
                label: 'Cancel',
                danger: true,
                onPressed: () => _confirmCancel(context, feeWarning: true),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _OnTripSheet extends StatelessWidget {
  const _OnTripSheet({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.navigation, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text('On the way to your destination',
                  style: theme.textTheme.titleMedium),
            ),
            _sosButton(context, state),
            IconButton(
              tooltip: 'Message driver',
              icon: const Icon(Icons.chat_bubble_outline),
              onPressed: () => _openTripChat(context, state),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(state.dropoffAddr ?? '', style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

/// Opens the safety toolkit (SOS) for the active trip.
void _openSafety(BuildContext context, TripState state) {
  final tripId = state.trip?.id;
  if (tripId == null) return;
  final share = 'FairsVia trip to ${state.dropoffAddr ?? 'my destination'}. '
      'Driver: ${state.driver?.name ?? 'assigned'}. Please track my ride.';
  showSafetySheet(
    context,
    tripId: tripId,
    safety: sl<SafetyRemoteDataSource>(),
    shareText: share,
  );
}

/// A small red SOS button for the active-trip sheets.
Widget _sosButton(BuildContext context, TripState state) {
  return IconButton(
    tooltip: 'Safety',
    icon: const Icon(Icons.shield_outlined, color: AppColors.error),
    onPressed: () => _openSafety(context, state),
  );
}

/// Opens the in-trip chat with the assigned driver.
void _openTripChat(BuildContext context, TripState state) {
  final tripId = state.trip?.id;
  final userId = context.read<AuthBloc>().state.user?.id;
  if (tripId == null || userId == null) return;
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatPage(
        tripId: tripId,
        currentUserId: userId,
        title: state.driver?.name ?? 'Driver',
        chat: sl<ChatRemoteDataSource>(),
        realtime: sl<RealtimeClient>(),
      ),
    ),
  );
}

/// A toggle to add/remove the just-completed trip's driver as a favourite.
class _FavoriteDriverButton extends StatefulWidget {
  const _FavoriteDriverButton({required this.driverId, this.driverName});
  final String driverId;
  final String? driverName;

  @override
  State<_FavoriteDriverButton> createState() => _FavoriteDriverButtonState();
}

class _FavoriteDriverButtonState extends State<_FavoriteDriverButton> {
  final _favorites = sl<FavoritesRemoteDataSource>();
  bool _favorited = false;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final next = !_favorited;
    try {
      if (next) {
        await _favorites.add(widget.driverId);
      } else {
        await _favorites.remove(widget.driverId);
      }
      if (mounted) setState(() => _favorited = next);
      messenger.showSnackBar(SnackBar(
        content: Text(next
            ? 'Added ${widget.driverName ?? 'driver'} to favourites'
            : 'Removed from favourites'),
      ));
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: Icon(
        _favorited ? Icons.favorite : Icons.favorite_border,
        color: _favorited ? AppColors.error : null,
        size: 18,
      ),
      label: Text(_favorited ? 'Favourited' : 'Add to favourites'),
    );
  }
}

class _CompletedSheet extends StatelessWidget {
  const _CompletedSheet({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final fare = state.receipt?.fare ?? state.fareFinal ?? 0;
    final tip = state.tipAmount ?? state.receipt?.tip ?? 0;
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 64,
              height: 64,
              decoration: const BoxDecoration(
                color: AppColors.accentSoft,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded,
                  color: AppColors.accent, size: 36),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Text('Trip complete', style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: [
                _ReceiptRow(label: 'Fare', value: fare),
                if (tip > 0) _ReceiptRow(label: 'Tip', value: tip),
                Divider(height: AppSpacing.lg, color: theme.dividerColor),
                _ReceiptRow(label: 'Total', value: fare + tip, bold: true),
              ],
            ),
          ),
          if (state.receipt?.isCash ?? false)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Pay \$${_money(fare + tip)} in cash to your driver',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.warning),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.xl),
          // Rating
          Center(
              child: Text('Rate your driver',
                  style: theme.textTheme.titleMedium)),
          const SizedBox(height: AppSpacing.sm),
          StarRating(
            value: state.rating ?? 0,
            onRate: state.rating == null ? cubit.rateDriver : null,
          ),
          if (state.rating != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Text('Thanks for your feedback!',
                    style: theme.textTheme.bodySmall),
              ),
            ),
          if (state.driver?.id != null) ...[
            const SizedBox(height: AppSpacing.md),
            _FavoriteDriverButton(
              driverId: state.driver!.id!,
              driverName: state.driver!.name,
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          // Tips
          Text('Add a tip', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final amt in const [2.0, 3.0, 5.0])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _TipChip(
                      amount: amt,
                      selected: state.tipAmount == amt,
                      onTap: (state.tipping || state.tipAmount != null)
                          ? null
                          : () => cubit.tipDriver(amt),
                    ),
                  ),
                ),
              // Custom amount — a rider isn't limited to the presets.
              Expanded(
                child: _CustomTipChip(
                  // Highlight when the added tip isn't one of the presets.
                  selected: state.tipAmount != null &&
                      !const [2.0, 3.0, 5.0].contains(state.tipAmount),
                  onTap: (state.tipping || state.tipAmount != null)
                      ? null
                      : () => _promptCustomTip(context, cubit),
                ),
              ),
            ],
          ),
          if (state.tipAmount != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Tip of \$${_money(state.tipAmount!)} added.',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: 'Done',
            onPressed: () => context.read<TripCubit>().reset(),
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value, this.bold = false});
  final String label;
  final double value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final style = bold
        ? theme.textTheme.titleMedium
        : theme.textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          // Show cents so a custom tip like $7.50 sums correctly (whole amounts
          // still read cleanly as $7.00).
          Text('\$${value.toStringAsFixed(2)}', style: style?.tabular()),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({required this.amount, required this.selected, this.onTap});
  final double amount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null || selected;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? AppColors.accent : theme.dividerColor,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  AppHaptics.selection();
                  onTap!();
                },
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              '\$${amount.toStringAsFixed(0)}',
              style: theme.textTheme.titleMedium?.copyWith(
                color: selected
                    ? AppColors.accent
                    : (enabled ? theme.colorScheme.onSurface : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tip chip that lets the rider enter any amount, styled like [_TipChip].
class _CustomTipChip extends StatelessWidget {
  const _CustomTipChip({required this.selected, this.onTap});
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null || selected;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
              : theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          border: Border.all(
            color: selected ? AppColors.accent : theme.dividerColor,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Text(
              'Custom',
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected
                    ? AppColors.accent
                    : (enabled ? theme.colorScheme.onSurface : null),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Prompt for a custom tip amount and submit it.
Future<void> _promptCustomTip(BuildContext context, TripCubit cubit) async {
  final controller = TextEditingController();
  final amount = await showDialog<double>(
    context: context,
    builder: (dialogCtx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add a tip'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType:
                const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              prefixText: '\$ ',
              hintText: '0.00',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                if (v == null || v <= 0) {
                  setLocal(() => error = 'Enter an amount');
                  return;
                }
                if (v > 500) {
                  setLocal(() => error = 'Max \$500');
                  return;
                }
                Navigator.pop(dialogCtx, v);
              },
              child: const Text('Add tip'),
            ),
          ],
        ),
      );
    },
  );
  if (amount != null) cubit.tipDriver(amount);
}

/// Format a dollar amount without trailing `.00` (so `$4` not `$4.00`, but
/// `$4.50` keeps its cents).
String _money(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => child;
}

class _Busy extends StatelessWidget {
  const _Busy({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const SizedBox(
          height: 22,
          width: 22,
          child: CircularProgressIndicator(strokeWidth: 2.4),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(label: 'Try again', onPressed: onRetry),
      ],
    );
  }
}

