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

/// Matched / arrived sheet: status + live ETA, driver card, start code and
/// the Message / Call / Cancel actions. Public so it can be widget-tested
/// without the map. [dialer] launches the driver's number (`tel:`);
/// injectable for tests.
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
                  // Headline + ETA come from RideStatus, so "on the way" turns
                  // into "almost here" at the same threshold everywhere, and
                  // the ETA is a sub-line rather than the headline itself.
                  RideStatusHeader(status: RideStatus.of(state)),
                  // No ping for a while: the car on the map (and the ETA)
                  // may be stale — say so instead of pretending it's live.
                  if (state.driverStale) ...[
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.6),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(waitingForLocation,
                            style: theme.textTheme.bodySmall),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _sosButton(context, state),
          ],
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _SheetWarning(message: state.error!),
        ],
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
        // The fare and the car, reachable while the rider waits — both used to
        // disappear from the app the moment a driver accepted.
        RideDetailsButton(state: state),
        const SizedBox(height: AppSpacing.sm),
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
              Text(eta, style: theme.textTheme.titleSmall?.tabular()),
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
