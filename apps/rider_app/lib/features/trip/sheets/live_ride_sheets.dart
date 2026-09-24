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
            PulseRadar(
              size: 56,
              child: Icon(PhosphorIconsRegular.taxi,
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
              ? 'Ride cancelled. A ${Fmt.money(fee, cubit.state.trip?.currency)} '
                  'cancellation fee was charged.'
              : 'Ride cancelled.',
        ),
      ),
    );
}

/// "₹50" from the trip's configured cancellation fee, or a generic word
/// when an older backend didn't send one.
String _feeLabel(TripCubit cubit) {
  final fee = cubit.state.trip?.cancellationFee;
  return fee == null ? '' : Fmt.money(fee, cubit.state.trip?.currency);
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
                  trailing: const Icon(PhosphorIconsRegular.caretRight),
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
        const SizedBox(height: AppSpacing.md),
        _DriverVehicleCard(driver: driver),
        if (otp != null) ...[
          const SizedBox(height: AppSpacing.md),
          _RidePin(pin: otp, driverName: RideStatus.driverName(state)),
        ],
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
                icon: PhosphorIconsRegular.chatCircle,
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
                  icon: PhosphorIconsRegular.phone,
                  onPressed: () => _call(context, phone),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        Divider(height: 1, color: theme.dividerColor),
        const SizedBox(height: AppSpacing.md),
        _PickupSummary(state: state),
        if (state.trip?.stops.isNotEmpty ?? false)
          _RideStops(stops: state.trip!.stops),
        const SizedBox(height: AppSpacing.md),
        // The fare and the car, reachable while the rider waits.
        RideDetailsButton(state: state),
        const RideCardsSection(),
        const SizedBox(height: AppSpacing.md),
        _RideQuickActions(state: state),
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
    final who = driverName == 'Your driver' ? 'your driver' : driverName;
    return Semantics(
      label: 'Ride PIN ${pin.split('').join(' ')}. Tell $who when you get in.',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ride PIN', style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text('Tell $who when you get in',
                    style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          // The PIN as one ink badge, readable through a car window.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final d in pin.split(''))
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: Text(d,
                        style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppColors.onAccent,
                            letterSpacing: 0)),
                  ),
              ],
            ),
          ),
        ],
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
        Padding(
          padding: EdgeInsets.only(top: 2),
          child: Icon(PhosphorIconsRegular.record, size: 18, color: AppColors.accent),
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
                  chip(PhosphorIconsRegular.car, _tier),
                  chip(cash ? PhosphorIconsRegular.money : PhosphorIconsRegular.creditCard,
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
                        const Icon(PhosphorIconsFill.star,
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
                      Market.current.formatPlate(d!.plate!),
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
                PhosphorIconsRegular.car,
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
            const Icon(PhosphorIconsFill.checkCircle, color: AppColors.success),
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
      icon: PhosphorIconsRegular.personSimpleWalk,
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
      icon: const Icon(PhosphorIconsRegular.dotsThree),
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
            leading: Icon(PhosphorIconsRegular.export),
            title: Text('Share trip status'),
          ),
        ),
        PopupMenuItem(
          value: 'safety',
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.shieldCheck),
            title: Text('Safety'),
          ),
        ),
        PopupMenuItem(
          value: 'help',
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.headset),
            title: Text('Help'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'cancel',
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.x, color: AppColors.error),
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
              Icon(PhosphorIconsRegular.clock,
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
        if (state.trip?.stops.isNotEmpty ?? false) ...[
          const SizedBox(height: AppSpacing.xs),
          _RideStops(stops: state.trip!.stops),
        ],
        const SizedBox(height: AppSpacing.md),
        // Mid-ride, this is the only way to see the fare and the car's details.
        RideDetailsButton(state: state),
        const SizedBox(height: AppSpacing.md),
        _RideQuickActions(state: state),
      ],
    );
  }
}

/// The ride's stops, in order, once any exist.
class _RideStops extends StatelessWidget {
  const _RideStops({required this.stops});

  final List<TripStop> stops;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < stops.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(PhosphorIconsRegular.flag,
                      size: 18, color: AppColors.warning),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    '${stops.length > 1 ? 'Stop ${i + 1}' : 'Stop'} · '
                    '${stops[i].address ?? 'Pinned location'}',
                    style: theme.textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Quick actions under the ride: "Add a stop" (the brief's "Add trip") and
/// "Pre-book" a ride for later.
class _RideQuickActions extends StatelessWidget {
  const _RideQuickActions({required this.state});

  final TripState state;

  Future<void> _preBook(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final trip = await Navigator.of(context).push<Trip>(MaterialPageRoute(
      builder: (_) => PreBookPage(
        repository: sl<TripRepository>(),
        // Most pre-books from mid-ride are the ride back.
        pickup: state.trip?.dropoff.point ?? state.dropoff,
        pickupAddr: state.trip?.dropoff.address ?? state.dropoffAddr,
        paymentMode: state.trip?.paymentMode ?? state.paymentMode,
      ),
    ));
    if (trip == null) return;
    final when = trip.scheduledAt;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(when == null
            ? 'Ride scheduled. Find it in Account › Scheduled rides.'
            : 'Ride scheduled for ${_formatSchedule(when)}. '
                'Find it in Account › Scheduled rides.'),
      ));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (TripCubit.canAddStopTo(state)) ...[
          _QuickActionCard(
            icon: PhosphorIconsRegular.mapPinPlus,
            title: 'Add a stop',
            subtitle: 'See the new price before you confirm',
            onTap: () => _addStopToRide(context, state),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _QuickActionCard(
          icon: PhosphorIconsRegular.calendarCheck,
          title: 'Pre-book a ride',
          subtitle: 'Your ride back, or any trip later',
          onTap: () => _preBook(context),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    // A grey tile, like the shortcut tiles at the bottom of Uber's sheets.
    return AppCard(
      onTap: onTap,
      color: dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.accentInk, size: 22),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(subtitle,
                    style: theme.textTheme.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const Icon(PhosphorIconsRegular.caretRight),
        ],
      ),
    );
  }
}

/// Pick a place, show what it does to the fare, add it on confirm.
Future<void> _addStopToRide(BuildContext context, TripState state) async {
  final cubit = context.read<TripCubit>();
  final messenger = ScaffoldMessenger.of(context);
  final place = await Navigator.of(context).push<PlaceDetails>(
    MaterialPageRoute(
      builder: (_) => DestinationSearchPage(
        singleDestination: true,
        initialPickup: state.driverLocation ?? state.pickup,
      ),
    ),
  );
  if (place == null || !context.mounted) return;
  final stop = TripStop(point: place.location, address: place.address);
  final added = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => AddStopConfirmSheet(
      stop: stop,
      quote: () => cubit.quoteRideStop(stop),
      add: (fare) => cubit.addRideStop(stop, fare),
      driverName: RideStatus.driverName(state),
    ),
  );
  if (added == true) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Stop added to your ride.')));
  }
}

/// Confirms a new stop: the new fare against the current one, then adds it.
/// A price that moved while the sheet was open is re-quoted and shown, never
/// silently accepted. Public for widget tests.
class AddStopConfirmSheet extends StatefulWidget {
  const AddStopConfirmSheet({
    super.key,
    required this.stop,
    required this.quote,
    required this.add,
    required this.driverName,
  });

  final TripStop stop;
  final Future<StopQuote> Function() quote;
  final Future<void> Function(double quotedFare) add;
  final String driverName;

  @override
  State<AddStopConfirmSheet> createState() => _AddStopConfirmSheetState();
}

class _AddStopConfirmSheetState extends State<AddStopConfirmSheet> {
  StopQuote? _quote;
  String? _error;
  String? _notice;
  bool _adding = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _error = null;
      _quote = null;
    });
    try {
      final q = await widget.quote();
      if (mounted) setState(() => _quote = q);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = "Couldn't price this stop. Try again.");
      }
    }
  }

  Future<void> _confirm() async {
    final q = _quote;
    if (q == null) return;
    setState(() {
      _adding = true;
      _notice = null;
    });
    try {
      await widget.add(q.fareEstimate);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (!mounted) return;
      if (e.code == TripCubit.priceChangedCode) {
        setState(() {
          _adding = false;
          _notice = 'The price changed while you were deciding. '
              'Here is the new one.';
        });
        await _load();
      } else {
        setState(() {
          _adding = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _adding = false;
          _error = "Couldn't add the stop. Try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final q = _quote;
    final who = widget.driverName == 'Your driver'
        ? 'your driver'
        : widget.driverName;
    return Padding(
      padding: EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg,
          AppSpacing.lg + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add a stop', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(PhosphorIconsRegular.flag, color: AppColors.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(widget.stop.address ?? 'Pinned location',
                    style: theme.textTheme.bodyLarge),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_error != null)
            Text(_error!,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: AppColors.error))
          else if (q == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (_notice != null) ...[
              Text(_notice!,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: AppColors.warning)),
              const SizedBox(height: AppSpacing.sm),
            ],
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('New fare', style: theme.textTheme.labelMedium),
                        Text(Fmt.money(q.fareEstimate, q.currency),
                            style: theme.textTheme.headlineSmall),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        q.difference >= 0.005
                            ? '+${Fmt.money(q.difference, q.currency)}'
                            : 'No change',
                        style: theme.textTheme.titleSmall,
                      ),
                      Text('was ${Fmt.money(q.previousFare, q.currency)}',
                          style: theme.textTheme.bodySmall),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'We’ll let $who know. You can add up to '
              '${TripCubit.maxRideStops} stops.',
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          PrimaryButton(
            label: _error != null && q == null ? 'Try again' : 'Add stop',
            loading: _adding,
            onPressed: _adding
                ? null
                : (_error != null && q == null)
                    ? _load
                    : (q == null ? null : _confirm),
          ),
          TextButton(
            onPressed: _adding ? null : () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
        ],
      ),
    );
  }
}

/// Admin-managed promo / recommendation cards under the ride details. Purely
/// additive: if they cannot be loaded, the section is simply absent.
class RideCardsSection extends StatefulWidget {
  const RideCardsSection({super.key, this.load, this.openUrl});

  /// Injectable for tests; defaults to the content API.
  final Future<List<RideCard>> Function()? load;
  final Future<bool> Function(String url)? openUrl;

  @override
  State<RideCardsSection> createState() => _RideCardsSectionState();
}

class _RideCardsSectionState extends State<RideCardsSection> {
  List<RideCard> _cards = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final cards =
          await (widget.load ?? () => sl<ContentRemoteDataSource>().rideCards())();
      if (mounted) setState(() => _cards = cards);
    } catch (_) {
      // Promotions must never get in the way of the ride.
    }
  }

  Future<void> _act(RideCard c) async {
    final messenger = ScaffoldMessenger.of(context);
    final value = c.ctaValue!;
    if (c.ctaType == 'promo_code') {
      await Clipboard.setData(ClipboardData(text: value));
      AppHaptics.selection();
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(
            content: Text('Code $value copied — add it when you book your next ride.')));
      return;
    }
    final ok = await (widget.openUrl ?? openExternalUrl)(value);
    if (!ok) {
      messenger.showSnackBar(
          const SnackBar(content: Text("Couldn't open that link.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_cards.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final c in _cards) ...[
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: dark
                      ? const [AppColors.accentSoftDark, AppColors.surfaceMutedDark]
                      : [AppColors.accentSoft, AppColors.surfaceMutedLight],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AppSpacing.radius),
              ),
              child: Row(
                children: [
                  Icon(PhosphorIconsRegular.tag, color: AppColors.accentInk),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.title, style: theme.textTheme.titleSmall),
                        const SizedBox(height: 2),
                        Text(c.body,
                            style: theme.textTheme.bodySmall,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                  if (c.hasAction) ...[
                    const SizedBox(width: AppSpacing.sm),
                    TextButton(
                      onPressed: () => _act(c),
                      child: Text(c.ctaLabel!),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
