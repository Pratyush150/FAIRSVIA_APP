import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_models/shared_models.dart';

import 'features/trip/destination_search_page.dart';
import 'features/trip/location_service.dart';
import 'features/trip/map_utils.dart';
import 'features/trip/trip_cubit.dart';

/// Rider home: full-screen map with a bottom sheet that changes with the
/// request phase (where-to → choose ride → finding driver).
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

class _RiderHomeViewState extends State<_RiderHomeView> {
  final _location = LocationService();
  GeoPoint _myLocation = LocationService.fallback;
  List<SavedPlace> _savedPlaces = const [];

  @override
  void initState() {
    super.initState();
    _loadLocation();
    _loadSavedPlaces();
    _connectSocket();
  }

  Future<void> _loadLocation() async {
    final loc = await _location.currentOrFallback();
    if (mounted) setState(() => _myLocation = loc);
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
          pickupAddr: 'Current location',
          dropoff: place.point,
          dropoffAddr: place.address ?? place.label,
        );
  }

  Future<void> _connectSocket() async {
    final token = await sl<TokenStorage>().readAccessToken();
    if (token != null && mounted) {
      await context.read<TripCubit>().init(token);
    }
  }

  Future<void> _openSearch() async {
    final details = await Navigator.of(context).push<PlaceDetails>(
      MaterialPageRoute(builder: (_) => const DestinationSearchPage()),
    );
    if (details != null && mounted) {
      await context.read<TripCubit>().chooseDestination(
            pickup: _myLocation,
            pickupAddr: 'Current location',
            dropoff: details.location,
            dropoffAddr: details.address,
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
    final encoded = state.estimate?.polyline;
    if (encoded == null || encoded.isEmpty) return const [];
    return MapUtils.decodePolyline(encoded);
  }

  /// Fit pickup + dropoff once an estimate exists (stable during the trip, so
  /// AppMap only re-fits when the endpoints actually change).
  List<LatLng>? _fitBounds(TripState state) {
    final e = state.estimate;
    if (e == null) return null;
    return [MapUtils.toLatLng(e.pickup), MapUtils.toLatLng(e.dropoff)];
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripCubit, TripState>(
        builder: (context, state) {
          return Scaffold(
            body: Stack(
              children: [
                // Real OpenStreetMap tiles (no API key) — renders on mobile + web.
                AppMap(
                  initialCenter: MapUtils.toLatLng(_myLocation),
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
                    child: Align(
                      alignment: Alignment.topRight,
                      child: AppCircleButton(
                        icon: Icons.menu_rounded,
                        tooltip: 'Account menu',
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const AccountMenuPage(isDriver: false),
                          ),
                        ),
                      ),
                    ),
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
    return AppSheet(child: child);
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
              'Fares are higher due to demand (${estimate.surge}x)',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.warning),
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
              for (final tier in estimate.tiers)
                _RideTierTile(
                  tier: tier,
                  selected: tier.tier == state.selectedTier,
                  onTap: () => cubit.selectTier(tier.tier),
                ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        _PaymentModeToggle(state: state),
        const SizedBox(height: AppSpacing.sm),
        _ScheduleRow(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PromoField(state: state),
        const SizedBox(height: AppSpacing.md),
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
      MaterialPageRoute(builder: (_) => const DestinationSearchPage()),
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
  return '$verb ${fare.label} · \$${amount.toStringAsFixed(0)}';
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
    // Must be at least 5 minutes ahead (backend rule).
    if (when.isBefore(now.add(const Duration(minutes: 5)))) {
      cubit.setScheduledAt(now.add(const Duration(minutes: 5)));
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

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripCubit>();
    return Row(
      children: [
        Expanded(
          child: _PayChip(
            icon: Icons.credit_card,
            label: 'Card',
            selected: state.paymentMode == 'card',
            onTap: () => cubit.setPaymentMode('card'),
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
}

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
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
            Text(
              label,
              style: theme.textTheme.titleSmall?.copyWith(
                color: selected ? AppColors.accent : null,
              ),
            ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        selected: selected,
        onTap: onTap,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.md,
        ),
        color: selected ? AppColors.accentSoft : null,
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
              style: theme.textTheme.titleLarge,
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
            SizedBox(
              height: 48,
              width: 48,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(
                    height: 48,
                    width: 48,
                    child: CircularProgressIndicator(strokeWidth: 3),
                  ),
                  Container(
                    height: 32,
                    width: 32,
                    decoration: const BoxDecoration(
                      color: AppColors.accentSoft,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.local_taxi_rounded,
                        size: 18, color: AppColors.accent),
                  ),
                ],
              ),
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
          onPressed: () => context.read<TripCubit>().cancelTrip(),
        ),
      ],
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
                        : 'Your driver is on the way',
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
                        Text((driver?.rating ?? 5).toStringAsFixed(1),
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
                        color: AppColors.surfaceMutedLight,
                        borderRadius:
                            BorderRadius.circular(AppSpacing.radiusSm),
                        border: Border.all(color: AppColors.borderLight),
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
                onPressed: () => context.read<TripCubit>().cancelTrip(),
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
  final share = 'UberNav trip to ${state.dropoffAddr ?? 'my destination'}. '
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
                    'Pay \$${(fare + tip).toStringAsFixed(0)} in cash to your driver',
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
            ],
          ),
          if (state.tipAmount != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text('Tip of \$${state.tipAmount!.toStringAsFixed(0)} added.',
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
          Text('\$${value.toStringAsFixed(0)}', style: style),
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
    final enabled = onTap != null || selected;
    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          color: selected
              ? AppColors.accentSoft
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

