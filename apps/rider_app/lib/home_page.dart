import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  GoogleMapController? _mapController;
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

  void _fitRoute(TripState state) {
    final controller = _mapController;
    final estimate = state.estimate;
    if (controller == null || estimate == null) return;
    final points = [
      MapUtils.toLatLng(estimate.pickup),
      MapUtils.toLatLng(estimate.dropoff),
    ];
    controller.animateCamera(
      CameraUpdate.newLatLngBounds(MapUtils.boundsFor(points), 80),
    );
  }

  Set<Marker> _markers(TripState state) {
    final markers = <Marker>{};
    if (state.pickup != null) {
      markers.add(Marker(
        markerId: const MarkerId('pickup'),
        position: MapUtils.toLatLng(state.pickup!),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ));
    }
    if (state.dropoff != null) {
      markers.add(Marker(
        markerId: const MarkerId('dropoff'),
        position: MapUtils.toLatLng(state.dropoff!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Destination'),
      ));
    }
    if (state.driverLocation != null) {
      markers.add(Marker(
        markerId: const MarkerId('driver'),
        position: MapUtils.toLatLng(state.driverLocation!),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'Driver'),
      ));
    }
    return markers;
  }

  Set<Polyline> _polylines(TripState state) {
    final encoded = state.estimate?.polyline;
    if (encoded == null || encoded.isEmpty) return {};
    return {
      Polyline(
        polylineId: const PolylineId('route'),
        points: MapUtils.decodePolyline(encoded),
        color: AppColors.accent,
        width: 5,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<TripCubit, TripState>(
      listenWhen: (p, c) => p.phase != c.phase,
      listener: (context, state) {
        if (state.phase == TripPhase.choosingRide) _fitRoute(state);
      },
      child: BlocBuilder<TripCubit, TripState>(
        builder: (context, state) {
          return Scaffold(
            body: Stack(
              children: [
                // Google Maps needs a JS key on web; until one is set we show a
                // placeholder so the rest of the flow stays testable in-browser.
                if (kIsWeb)
                  const MapPlaceholder()
                else
                  GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: MapUtils.toLatLng(_myLocation),
                      zoom: 14,
                    ),
                    myLocationEnabled: true,
                    myLocationButtonEnabled: false,
                    markers: _markers(state),
                    polylines: _polylines(state),
                    onMapCreated: (c) => _mapController = c,
                  ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Align(
                      alignment: Alignment.topRight,
                      child: _CircleButton(
                        icon: Icons.menu,
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
      ),
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
    return _SheetContainer(child: child);
  }
}

class _SheetContainer extends StatelessWidget {
  const _SheetContainer({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: SafeArea(top: false, child: child),
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Where to?', style: theme.textTheme.headlineSmall),
        const SizedBox(height: AppSpacing.md),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: theme.scaffoldBackgroundColor,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: AppColors.accent),
                const SizedBox(width: AppSpacing.md),
                Text('Enter your destination',
                    style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
        ),
        if (savedPlaces.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final place in savedPlaces)
                ActionChip(
                  avatar: Icon(_iconFor(place.label), size: 18),
                  label: Text(place.label),
                  onPressed: () => onPickSaved(place),
                ),
            ],
          ),
        ],
      ],
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
              '${estimate.distanceKm.toStringAsFixed(1)} km · '
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
          constraints: const BoxConstraints(maxHeight: 220),
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
  return '$verb ${fare.label} · ₹${amount.toStringAsFixed(0)}';
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
                '${promo.code} applied · −₹${promo.discount.toStringAsFixed(0)}',
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(
            color: selected ? AppColors.accent : Colors.transparent,
            width: 2,
          ),
          color: theme.scaffoldBackgroundColor,
        ),
        child: Row(
          children: [
            const Icon(Icons.local_taxi, size: 32),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tier.label, style: theme.textTheme.titleMedium),
                  Text(
                    '${tier.capacity} seats · ${(tier.etaSeconds / 60).round()} min',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            Text(
              '₹${tier.fare.toStringAsFixed(0)}',
              style: theme.textTheme.titleMedium,
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
            const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('Connecting you with a driver…',
                  style: theme.textTheme.titleMedium),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          'Trip to ${state.dropoffAddr ?? 'your destination'}',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton(
          onPressed: () => context.read<TripCubit>().cancelTrip(),
          child: const Text('Cancel ride'),
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
          children: [
            Expanded(
              child: Text(
                arrived ? 'Your driver has arrived' : 'Driver on the way',
                style: theme.textTheme.headlineSmall,
              ),
            ),
            _sosButton(context, state),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            const CircleAvatar(radius: 24, child: Icon(Icons.person)),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(driver?.name ?? 'Your driver',
                      style: theme.textTheme.titleMedium),
                  Row(
                    children: [
                      const Icon(Icons.star, size: 14, color: AppColors.warning),
                      const SizedBox(width: 2),
                      Text((driver?.rating ?? 5).toStringAsFixed(1),
                          style: theme.textTheme.bodySmall),
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
                if (driver?.plate != null)
                  Text(driver!.plate!, style: theme.textTheme.titleMedium),
              ],
            ),
          ],
        ),
        if (otp != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Start code:  ', style: theme.textTheme.bodyMedium),
                Text(otp,
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(letterSpacing: 4)),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _openTripChat(context, state),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('Message'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: () => context.read<TripCubit>().cancelTrip(),
                child: const Text('Cancel ride'),
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
          const Icon(Icons.check_circle, color: AppColors.accent, size: 48),
          const SizedBox(height: AppSpacing.sm),
          Center(
            child: Text('Trip complete', style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.lg),
          _ReceiptRow(label: 'Fare', value: fare),
          if (tip > 0) _ReceiptRow(label: 'Tip', value: tip),
          const Divider(height: AppSpacing.xl),
          _ReceiptRow(label: 'Total', value: fare + tip, bold: true),
          if (state.receipt?.isCash ?? false)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  const Icon(Icons.payments_outlined,
                      size: 16, color: AppColors.warning),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'Pay ₹${(fare + tip).toStringAsFixed(0)} in cash to your driver',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: AppColors.warning),
                  ),
                ],
              ),
            ),
          const SizedBox(height: AppSpacing.lg),
          // Rating
          Text('Rate your driver', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          _StarRating(
            value: state.rating ?? 0,
            onRate: state.rating == null ? cubit.rateDriver : null,
          ),
          if (state.rating != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('Thanks for your feedback!',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.lg),
          // Tips
          Text('Add a tip', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              for (final amt in const [20.0, 30.0, 50.0])
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: OutlinedButton(
                      onPressed: (state.tipping || state.tipAmount != null)
                          ? null
                          : () => cubit.tipDriver(amt),
                      child: Text('₹${amt.toStringAsFixed(0)}'),
                    ),
                  ),
                ),
            ],
          ),
          if (state.tipAmount != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text('Tip of ₹${state.tipAmount!.toStringAsFixed(0)} added.',
                  style: theme.textTheme.bodySmall),
            ),
          const SizedBox(height: AppSpacing.lg),
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
          Text('₹${value.toStringAsFixed(0)}', style: style),
        ],
      ),
    );
  }
}

class _StarRating extends StatelessWidget {
  const _StarRating({required this.value, this.onRate});
  final int value;
  final void Function(int stars)? onRate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 1; i <= 5; i++)
          IconButton(
            iconSize: 34,
            tooltip: '$i star${i > 1 ? 's' : ''}',
            onPressed: onRate == null ? null : () => onRate!(i),
            icon: Icon(
              i <= value ? Icons.star : Icons.star_border,
              color: AppColors.warning,
            ),
          ),
      ],
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

class _CircleButton extends StatelessWidget {
  const _CircleButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(icon: Icon(icon), onPressed: onPressed),
    );
  }
}
