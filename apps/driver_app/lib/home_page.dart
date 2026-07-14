import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
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
  static const _fallback = LatLng(12.9716, 77.5946);
  StreamSubscription<Position>? _posSub;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  Future<void> _connect() async {
    final token = await sl<TokenStorage>().readAccessToken();
    if (token != null && mounted) {
      await context.read<DriverCubit>().init(token);
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
      context.read<DriverCubit>().sendLocation(
            pos.latitude,
            pos.longitude,
            heading: pos.heading,
            speed: pos.speed,
          );
    });
  }

  void _stopStreamingLocation() {
    _posSub?.cancel();
    _posSub = null;
  }

  @override
  void dispose() {
    _stopStreamingLocation();
    super.dispose();
  }

  Set<Marker> _markers(DriverState state) {
    final trip = state.trip;
    if (trip == null) return {};
    return {
      Marker(
        markerId: const MarkerId('pickup'),
        position: LatLng(trip.pickup.point.lat, trip.pickup.point.lng),
        infoWindow: const InfoWindow(title: 'Pickup'),
      ),
      Marker(
        markerId: const MarkerId('dropoff'),
        position: LatLng(trip.dropoff.point.lat, trip.dropoff.point.lng),
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueGreen),
        infoWindow: const InfoWindow(title: 'Dropoff'),
      ),
    };
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
              // Google Maps needs a JS key on web; placeholder keeps the driver
              // flow testable in-browser until a key is set.
              if (kIsWeb)
                const MapPlaceholder()
              else
                GoogleMap(
                  initialCameraPosition:
                      const CameraPosition(target: _fallback, zoom: 14),
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  markers: _markers(state),
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
                      _CircleButton(
                        icon: Icons.menu,
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
            Text("You're offline", style: theme.textTheme.headlineSmall),
            if (state.lastEarned != null)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text('Today: ₹${state.lastEarned!.toStringAsFixed(0)}',
                    style: theme.textTheme.bodyMedium),
              ),
            const SizedBox(height: AppSpacing.md),
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
                const Icon(Icons.wifi_tethering, color: AppColors.accent),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text("You're online — looking for trips",
                      style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: () => cubit.goOffline(),
              child: const Text('Go offline'),
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
    return _SheetContainer(child: child);
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
        Row(
          children: [
            const Icon(Icons.check_circle, color: AppColors.accent),
            const SizedBox(width: AppSpacing.sm),
            Text('Trip complete', style: theme.textTheme.headlineSmall),
          ],
        ),
        if (state.lastEarned != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text("Today's earnings: ₹${state.lastEarned!.toStringAsFixed(0)}",
              style: theme.textTheme.bodyMedium),
        ],
        if (state.cashToCollect != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
              color: AppColors.warning.withValues(alpha: 0.14),
            ),
            child: Row(
              children: [
                const Icon(Icons.payments, color: AppColors.warning),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    'Collect ₹${state.cashToCollect!.toStringAsFixed(0)} in cash from the rider',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: AppColors.warning),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Rate your rider', style: theme.textTheme.titleMedium),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 1; i <= 5; i++)
              IconButton(
                iconSize: 32,
                tooltip: '$i',
                onPressed: state.riderRating == null
                    ? () => cubit.rateRider(i)
                    : null,
                icon: Icon(
                  i <= (state.riderRating ?? 0)
                      ? Icons.star
                      : Icons.star_border,
                  color: AppColors.warning,
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
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
            if (tripId != null)
              IconButton(
                tooltip: 'Message rider',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => openDriverChat(context, tripId!),
              ),
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
            if (widget.tripId != null)
              IconButton(
                tooltip: 'Message rider',
                icon: const Icon(Icons.chat_bubble_outline),
                onPressed: () => openDriverChat(context, widget.tripId!),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('Ask the rider for their 4-digit start code',
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.md),
        OtpInput(length: 4, onChanged: (v) => setState(() => _otp = v)),
        const SizedBox(height: AppSpacing.md),
        PrimaryButton(
          label: 'Start trip',
          loading: widget.busy,
          onPressed: _otp.length == 4 && !widget.busy
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

  @override
  void initState() {
    super.initState();
    _total = widget.offer.expiresInSec;
    _remaining = _total;
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remaining -= 1);
      if (_remaining <= 0) {
        t.cancel();
        context.read<DriverCubit>().declineOffer();
      }
    });
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
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: 0.55),
        alignment: Alignment.center,
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Material(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          color: theme.colorScheme.surface,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      height: 72,
                      width: 72,
                      child: CircularProgressIndicator(
                        value: _total == 0 ? 0 : _remaining / _total,
                        strokeWidth: 6,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.accent),
                      ),
                    ),
                    Text('$_remaining', style: theme.textTheme.headlineSmall),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
                Text('New ride request', style: theme.textTheme.headlineSmall),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '₹${offer.fare.toStringAsFixed(0)} · '
                  '${(offer.distanceM / 1000).toStringAsFixed(1)} km',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(offer.pickup.address ?? 'Pickup',
                    style: theme.textTheme.bodyMedium),
                const SizedBox(height: AppSpacing.xl),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () =>
                            context.read<DriverCubit>().declineOffer(),
                        child: const Text('Decline'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: PrimaryButton(
                        label: 'Accept',
                        onPressed: () =>
                            context.read<DriverCubit>().acceptOffer(),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
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
  final _model = TextEditingController(text: 'Etios');
  final _plate = TextEditingController(text: 'KA01AB1234');
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle,
              size: 10, color: online ? AppColors.success : Colors.grey),
          const SizedBox(width: AppSpacing.sm),
          Text(online ? 'Online' : 'Offline'),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  const _CircleButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });
  final IconData icon;
  final VoidCallback onPressed;

  /// Accessible label / hover hint for this icon-only control.
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: const CircleBorder(),
      elevation: 3,
      child: IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
