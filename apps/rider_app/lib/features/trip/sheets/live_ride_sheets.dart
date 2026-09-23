part of 'ride_sheets.dart';

/// The sheets of a live ride: finding a driver, the driver on the way or
/// arrived, the trip in progress, and cancelling.

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
              child: RideStatusHeader(
                status: RideStatus.of(state),
                detail: Text(
                  'Trip to ${state.dropoffAddr ?? 'your destination'}',
                  style: theme.textTheme.bodySmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _SheetWarning(message: state.error!),
        ],
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
  final reason = await showDialog<String>(
    context: context,
    builder: (_) => CancelRideDialog(cubit: cubit, feeWarning: feeWarning),
  );
  if (reason == null) return;
  final fee = await cubit.cancelTrip(reason: reason);
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          fee > 0
              ? 'Ride cancelled. A \$${fee.toStringAsFixed(2)} cancellation '
                  'fee was charged.'
              : 'Ride cancelled.',
        ),
      ),
    );
}

/// "$5.00" from the trip's configured cancellation fee, or a generic word
/// when an older backend didn't send one.
String _feeLabel(TripCubit cubit) {
  final fee = cubit.state.trip?.cancellationFee;
  return fee == null ? '' : '\$${fee.toStringAsFixed(2)}';
}

/// The cancellation reasons a rider can pick from (Uber-style), captured for
/// ops/analytics instead of a hardcoded label.
const List<String> cancelReasons = [
  'Driver is taking too long',
  'Wrong pickup location',
  'Booked by mistake',
  'Changed my plans',
  'Other',
];

/// "Cancel this ride?" prompt: pops with the chosen reason, or null to keep
/// the ride. If the trip ends underneath it (driver
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
        Navigator.of(ctx).pop();
      },
      child: AlertDialog(
        title: const Text('Cancel this ride?'),
        contentPadding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                feeWarning
                    ? 'Your driver is already on the way. Cancelling is free '
                        'for 2 minutes after they accept; after that a '
                        '${_feeLabel(cubit)} cancellation fee applies. '
                        'Let us know why:'
                    : 'Let us know why:',
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final r in cancelReasons)
                ListTile(
                  key: ValueKey('cancel-reason-$r'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context).pop(r),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Keep ride'),
          ),
        ],
      ),
    );
  }
}

/// The driver-arriving screen (matched → arrived): who is coming and when,
/// the ride PIN, where to meet, the driver and the car, and what the rider can
/// do. Public so it can be widget-tested without the map. [dialer] launches
/// the driver's number (`tel:`); injectable for tests.
class DriverInfoSheet extends StatelessWidget {
  const DriverInfoSheet({
    super.key,
    required this.state,
    required this.arrived,
    this.dialer = dialPhone,
  });
  final TripState state;
  final bool arrived;
  final Future<bool> Function(String phone) dialer;

  static const String waitingForLocation =
      "Waiting for your driver's location…";

  Future<void> _call(BuildContext context, String phone) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await dialer(phone);
    if (!ok) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't open the dialler for $phone")),
      );
    }
  }

  /// "I'm on my way" is worth showing once the driver is close or waiting —
  /// earlier, it would tell the driver nothing useful.
  bool get _showOnMyWay {
    if (arrived) return true;
    final eta = state.liveEtaSec ?? state.driver?.etaSec;
    return eta != null && eta > 0 && eta <= RideStatus.almostHereSec;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final driver = state.driver;
    final otp = state.trip?.startOtp;
    final phone = driver?.phone;
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
                  // Headline ("Bekzod is arriving now") + ETA come from
                  // RideStatus, so every sheet words a moment the same way.
                  RideStatusHeader(status: RideStatus.of(state)),
                  // No ping for a while: the car on the map (and the ETA)
                  // may be stale — say so instead of pretending it's live.
                  // Not once arrived: a parked car stops sending positions,
                  // and "waiting for your driver's location" while they sit
                  // at the pickup reads as if we had lost them.
                  if (state.driverStale && !arrived) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Flexible(
                          child: Text(waitingForLocation,
                              style: theme.textTheme.bodySmall),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _sosButton(context, state),
            _RideMenuButton(state: state),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _SheetWarning(message: state.error!),
        ],
        if (otp != null) ...[
          const SizedBox(height: AppSpacing.lg),
          _RidePin(pin: otp, driverName: RideStatus.driverName(state)),
        ],
        const SizedBox(height: AppSpacing.md),
        _PickupSummary(state: state),
        const SizedBox(height: AppSpacing.md),
        _DriverVehicleCard(driver: driver),
        if (_showOnMyWay) ...[
          const SizedBox(height: AppSpacing.lg),
          _OnMyWayButton(state: state),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                label: state.unreadMessages > 0
                    ? 'Message (${state.unreadMessages})'
                    : 'Message',
                icon: Icons.chat_bubble_rounded,
                onPressed: () => _openTripChat(context, state),
              ),
            ),
            // Only when the payload carries a number — a dead Call button is
            // worse than none.
            if (phone != null) ...[
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: SecondaryButton(
                  label: 'Call',
                  icon: Icons.call_rounded,
                  onPressed: () => _call(context, phone),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // The fare and the car, reachable while the rider waits.
        RideDetailsButton(state: state),
      ],
    );
  }
}

/// The 4-digit ride PIN, big enough to read out through a car window.
class _RidePin extends StatelessWidget {
  const _RidePin({required this.pin, required this.driverName});

  final String pin;
  final String driverName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final who = driverName == 'Your driver' ? 'your driver' : driverName;
    return Semantics(
      label: 'Ride PIN ${pin.split('').join(' ')}. Tell $who when you get in.',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: dark ? AppColors.accentSoftDark : AppColors.accentSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Ride PIN',
                      style: theme.textTheme.titleSmall
                          ?.copyWith(color: AppColors.accentInk)),
                ),
                for (final d in pin.split('')) ...[
                  Container(
                    width: 36,
                    height: 44,
                    margin: const EdgeInsets.only(left: 6),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    ),
                    child: Text(d,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppColors.accentInk)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text('Tell $who when you get in',
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

/// Where to meet, which ride it is, and how it is paid.
class _PickupSummary extends StatelessWidget {
  const _PickupSummary({required this.state});

  final TripState state;

  String get _tier {
    final tier = state.trip?.tier ?? state.selectedTier;
    if (tier == null) return 'Ride';
    for (final t in state.estimate?.tiers ?? const <FareTier>[]) {
      if (t.tier == tier) return t.label;
    }
    return tier.isEmpty ? 'Ride' : tier[0].toUpperCase() + tier.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cash = (state.trip?.paymentMode ?? state.paymentMode) == 'cash';
    final pickup = state.trip?.pickup.address ?? state.pickupAddr;
    Widget chip(IconData icon, String label) => Container(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm, vertical: 4),
          decoration: BoxDecoration(
            color: dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
            borderRadius: BorderRadius.circular(AppSpacing.pill),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14),
              const SizedBox(width: 4),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(Icons.trip_origin_rounded, size: 18, color: AppColors.accent),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Pickup', style: theme.textTheme.labelMedium),
              Text(
                pickup ?? 'Your pickup point',
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [
                  chip(Icons.directions_car_rounded, _tier),
                  chip(cash ? Icons.payments_rounded : Icons.credit_card_rounded,
                      cash ? 'Cash' : 'Card'),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A car icon in the vehicle's own colour, so the rider can spot it — the
/// stand-in until real vehicle photos exist.
Color? vehicleTint(String? colorName) {
  switch (colorName?.trim().toLowerCase()) {
    case 'white':
      return const Color(0xFFF4F4F2);
    case 'black':
      return const Color(0xFF1F1F1F);
    case 'silver':
    case 'grey':
    case 'gray':
      return const Color(0xFF9EA3A8);
    case 'red':
      return const Color(0xFFC62828);
    case 'blue':
      return const Color(0xFF1E5AA8);
    case 'green':
      return const Color(0xFF2E7D32);
    case 'yellow':
      return const Color(0xFFF2C94C);
    case 'orange':
      return const Color(0xFFEF6C00);
    case 'brown':
      return const Color(0xFF6D4C41);
    case 'beige':
      return const Color(0xFFD8C8A8);
    default:
      return null;
  }
}

class _DriverVehicleCard extends StatelessWidget {
  const _DriverVehicleCard({required this.driver});

  final AssignedDriver? driver;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final d = driver;
    // "Your driver" is the payload's placeholder, not a name: never turn it
    // into initials ("YD").
    final realName =
        (d == null || d.name.trim().isEmpty || d.name == 'Your driver')
            ? null
            : d.name.trim();
    final tint = vehicleTint(d?.vehicleColor);
    final lightCar = tint != null && tint.computeLuminance() > 0.6;
    final vehicle = d?.vehicleLabel ?? '';
    return AppCard(
      child: Row(
        children: [
          SizedBox(
            width: 60,
            height: 66,
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.topCenter,
              children: [
                AppAvatar(name: realName, size: 56),
                Positioned(
                  bottom: 0,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(AppSpacing.pill),
                      boxShadow: AppElevation.sm,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.star_rounded,
                            size: 13, color: AppColors.star),
                        const SizedBox(width: 2),
                        // No driver payload yet (e.g. restored after a cold
                        // start) — show "—" rather than inventing a 5.0.
                        Text(
                          d == null ? '—' : d.rating.toStringAsFixed(1),
                          style: theme.textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  realName ?? 'Your driver',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (vehicle.isNotEmpty)
                  Text(
                    vehicle,
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (d?.plate != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm, vertical: 3),
                    decoration: BoxDecoration(
                      color: dark
                          ? AppColors.surfaceMutedDark
                          : AppColors.surfaceMutedLight,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(
                          color: dark
                              ? AppColors.borderDark
                              : AppColors.borderLight),
                    ),
                    child: Text(
                      d!.plate!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(letterSpacing: 1),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Semantics(
            label: vehicle.isEmpty ? 'Car' : vehicle,
            excludeSemantics: true,
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                // A white/silver car on a light disc disappears — give light
                // cars a dark disc so the colour still reads.
                color: lightCar
                    ? AppColors.primaryElevated
                    : (dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight),
                shape: BoxShape.circle,
                border: Border.all(
                    color: dark ? AppColors.borderDark : AppColors.borderLight),
              ),
              child: Icon(
                Icons.directions_car_filled_rounded,
                size: 30,
                color: tint ??
                    (dark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "I'm on my way": tells the driver waiting at the pickup the rider is
/// coming out, so they don't give up or keep calling.
class _OnMyWayButton extends StatefulWidget {
  const _OnMyWayButton({required this.state});

  final TripState state;

  @override
  State<_OnMyWayButton> createState() => _OnMyWayButtonState();
}

class _OnMyWayButtonState extends State<_OnMyWayButton> {
  bool _sending = false;

  Future<void> _send() async {
    setState(() => _sending = true);
    final ok = await context.read<TripCubit>().imOnMyWay();
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) {
      AppHaptics.success();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Couldn't reach your driver — try again, or call them.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    final who = RideStatus.driverName(widget.state);
    if (widget.state.riderComingSent) {
      final theme = Theme.of(context);
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                "${who == 'Your driver' ? 'Your driver knows' : '$who knows'} you're on your way",
                style: theme.textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ).animate().fadeIn(duration: AppMotion.normal);
    }
    return PrimaryButton(
      label: "I'm on my way",
      icon: Icons.directions_walk_rounded,
      loading: _sending,
      onPressed: _sending ? null : _send,
    );
  }
}

/// ••• — the less frequent ride actions, kept out of the way of the main ones.
class _RideMenuButton extends StatelessWidget {
  const _RideMenuButton({required this.state});

  final TripState state;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More options',
      icon: const Icon(Icons.more_horiz_rounded),
      onSelected: (v) {
        switch (v) {
          case 'share':
            final d = state.driver;
            final car = d == null
                ? ''
                : ' Car: ${d.vehicleLabel}${d.plate != null ? ', plate ${d.plate}' : ''}. Driver: ${d.name}.';
            shareTripText(
              context,
              "I'm on a ${AppBrand.name} ride to "
              '${state.dropoffAddr ?? 'my destination'}.$car',
            );
          case 'safety':
            _openSafety(context, state);
          case 'help':
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) =>
                  SupportPage(support: sl<SupportRemoteDataSource>()),
            ));
          case 'cancel':
            _confirmCancel(context, feeWarning: true);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'share',
          child: ListTile(
            leading: Icon(Icons.ios_share_rounded),
            title: Text('Share trip status'),
          ),
        ),
        PopupMenuItem(
          value: 'safety',
          child: ListTile(
            leading: Icon(Icons.shield_outlined),
            title: Text('Safety'),
          ),
        ),
        PopupMenuItem(
          value: 'help',
          child: ListTile(
            leading: Icon(Icons.support_agent_rounded),
            title: Text('Help'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'cancel',
          child: ListTile(
            leading: Icon(Icons.close_rounded, color: AppColors.error),
            title: Text('Cancel ride', style: TextStyle(color: AppColors.error)),
          ),
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
        // On trip the map is the star: the sheet says the state, the time
        // left and the destination, and gets out of the way.
        RideStatusHeader(
          status: RideStatus.of(state),
          detail: Text(
            state.dropoffAddr ?? '',
            style: theme.textTheme.bodySmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _sosButton(context, state),
              IconButton(
                tooltip: 'Message driver',
                icon: _ChatIcon(unread: state.unreadMessages),
                onPressed: () => _openTripChat(context, state),
              ),
            ],
          ),
        ),
        if (_tripEtaLine(state) case final eta?) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              const Icon(Icons.schedule_rounded,
                  size: 18, color: AppColors.accent),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(eta,
                    style: theme.textTheme.titleSmall?.tabular(),
                    maxLines: 2),
              ),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.md),
        // Mid-ride, this is the only way to see the fare and the car's details.
        RideDetailsButton(state: state),
      ],
    );
  }
}
