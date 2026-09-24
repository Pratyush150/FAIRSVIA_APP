part of 'ride_sheets.dart';

/// The sheet shell: the phase → sheet dispatcher, and the small pieces
/// (warnings, busy/error cards, the SOS and chat affordances) that more than
/// one sheet needs.

/// Share of the screen the ride-options sheet may take, so the route stays
/// visible above it (also drives the map's bottom fit padding).
const double kRideOptionsSheetFraction = 0.58;

class RideSheetForPhase extends StatelessWidget {
  const RideSheetForPhase({
    super.key,
    required this.state,
    required this.onSearch,
    this.savedPlaces = const [],
    required this.onPickSaved,
    this.locationIssue,
    this.onFixLocation,
  });

  final TripState state;
  final VoidCallback onSearch;
  final List<SavedPlace> savedPlaces;
  final ValueChanged<SavedPlace> onPickSaved;

  /// Non-null when no real position is known: the idle sheet then shows a
  /// blocking "Location required" gate instead of the destination search.
  final LocationIssue? locationIssue;
  final VoidCallback? onFixLocation;

  @override
  Widget build(BuildContext context) {
    final child = switch (state.phase) {
      TripPhase.idle => _WhereToCard(
          onTap: onSearch,
          locationIssue: locationIssue,
          onFixLocation: onFixLocation,
          savedPlaces: savedPlaces,
          onPickSaved: onPickSaved,
          onSchedule: () => _openPreBook(context, state),
        ),
      TripPhase.loadingEstimate =>
        const _InfoCard(child: _Busy(label: 'Finding the best route…')),
      TripPhase.choosingRide => _RideOptions(state: state),
      TripPhase.requesting =>
        const _InfoCard(child: _Busy(label: 'Requesting your ride…')),
      TripPhase.scheduled => _ScheduledConfirmation(state: state),
      TripPhase.searching => _FindingDriver(state: state),
      TripPhase.driverEnRoute => DriverInfoSheet(state: state, arrived: false),
      TripPhase.driverArrived => DriverInfoSheet(state: state, arrived: true),
      TripPhase.onTrip => _OnTripSheet(state: state),
      TripPhase.completed => CompletedSheet(state: state),
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

/// Inline warning line for the live-trip sheets (failed cancel, locked start
/// code) — the ride is still on, so it sits with the ride rather than
/// replacing it.
class _SheetWarning extends StatelessWidget {
  const _SheetWarning({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(PhosphorIconsRegular.info,
            size: 16, color: AppColors.warning),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(message,
              style:
                  theme.textTheme.bodySmall?.copyWith(color: AppColors.warning)),
        ),
      ],
    );
  }
}

/// On-trip readout: "Arriving 3:42 PM · 12 min · 4.1 mi to go" built from the
/// live progress, or from the routed estimate before the first ping.
String? _tripEtaLine(TripState state) {
  final secs = state.liveEtaSec ?? state.estimate?.durationS;
  final metres =
      state.liveRemainingM ?? state.estimate?.distanceM;
  if (secs == null) return null;
  final arrival = DateTime.now().add(Duration(seconds: secs));
  final h = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
  final clock =
      '$h:${arrival.minute.toString().padLeft(2, '0')} ${arrival.hour < 12 ? 'AM' : 'PM'}';
  final mins = (secs / 60).ceil().clamp(1, 999);
  final dist = metres == null ? '' : ' · ${Fmt.distance(metres)} to go';
  return 'Arriving $clock · $mins min$dist';
}

/// Opens the safety toolkit (SOS) for the active trip.
void _openSafety(BuildContext context, TripState state) {
  final tripId = state.trip?.id;
  if (tripId == null) return;
  final car = state.driver;
  final carLine = car == null
      ? ''
      : ' Car: ${car.vehicleLabel}${car.plate != null ? ', plate ${car.plate}' : ''}.'
          ' Driver: ${car.name}.';
  final at = state.driverLocation;
  final where = at == null
      ? ''
      : ' Where I am: https://maps.google.com/?q=${at.lat.toStringAsFixed(5)},${at.lng.toStringAsFixed(5)}';
  final cubit = context.read<TripCubit>();
  final share = "I'm on a ${AppBrand.name} ride to "
      '${state.dropoffAddr ?? 'my destination'}.$carLine$where';
  showSafetySheet(
    context,
    tripId: tripId,
    safety: sl<SafetyRemoteDataSource>(),
    shareText: share,
    // The rider is in the car: their own fix first, the car's last position
    // if the phone has none.
    locate: () async {
      try {
        final p = await Geolocator.getLastKnownPosition() ??
            await Geolocator.getCurrentPosition();
        return (lat: p.latitude, lng: p.longitude);
      } catch (_) {
        final d = cubit.state.driverLocation;
        return d == null ? null : (lat: d.lat, lng: d.lng);
      }
    },
  );
}

/// The Safety entry on the active-trip sheets: a labelled pill, not a bare
/// shield icon — riders looking for help should not have to guess what an
/// icon means. Neutral at rest; the sheet it opens carries the red.
Widget _sosButton(BuildContext context, TripState state) => _RidePill(
      icon: PhosphorIconsFill.shieldCheck,
      label: 'Safety',
      onTap: () => _openSafety(context, state),
    );

/// Share the live trip (who, which car, where to) — a pill beside Safety
/// once the ride is under way.
Widget _shareButton(BuildContext context, TripState state) => _RidePill(
      icon: PhosphorIconsRegular.export,
      label: 'Share',
      onTap: () => _shareTrip(context, state),
    );

void _shareTrip(BuildContext context, TripState state) {
  final d = state.driver;
  final car = d == null
      ? ''
      : ' Car: ${d.vehicleLabel}${d.plate != null ? ', plate ${d.plate}' : ''}. Driver: ${d.name}.';
  shareTripText(
    context,
    "I'm on a ${AppBrand.name} ride to "
    '${state.dropoffAddr ?? 'my destination'}.$car',
  );
}

class _RidePill extends StatelessWidget {
  const _RidePill({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 4, right: 6),
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
          shape: const StadiumBorder(),
          child: InkWell(
            customBorder: const StadiumBorder(),
            onTap: onTap,
            child: ConstrainedBox(
              // 44 pt tap target, per the icon rules.
              constraints: const BoxConstraints(minHeight: 40),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 16, color: theme.colorScheme.onSurface),
                    const SizedBox(width: 4),
                    Text(label,
                        style: theme.textTheme.labelLarge
                            ?.copyWith(fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the in-trip chat with the assigned driver.
void _openTripChat(BuildContext context, TripState state) {
  final cubit = context.read<TripCubit>();
  cubit.setChatOpen(true);
  final tripId = state.trip?.id;
  final userId = context.read<AuthBloc>().state.user?.id;
  if (tripId == null || userId == null) return;
  unawaited(Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => ChatPage(
        tripId: tripId,
        currentUserId: userId,
        title: state.driver?.name ?? 'Driver',
        chat: sl<ChatRemoteDataSource>(),
        realtime: sl<RealtimeClient>(),
      ),
    ),
  ).then((_) => cubit.setChatOpen(false)));}

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

/// Chat bubble with an unread-count badge (Uber-style) for the sheet buttons.
class _ChatIcon extends StatelessWidget {
  const _ChatIcon({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(PhosphorIconsRegular.chatCircle);
    if (unread <= 0) return icon;
    return Badge.count(count: unread, child: icon);
  }
}

/// Whole minutes for a duration, never showing "0 min" for a short hop.
int _minutes(num seconds) => (seconds / 60).ceil().clamp(1, 9999).toInt();

/// "Later" on the home sheet: pre-book from where the rider is now.
Future<void> _openPreBook(BuildContext context, TripState state) async {
  final messenger = ScaffoldMessenger.of(context);
  final trip = await Navigator.of(context).push<Trip>(MaterialPageRoute(
    builder: (_) => PreBookPage(
      repository: sl<TripRepository>(),
      pickup: state.pickup,
      pickupAddr: state.pickupAddr,
      paymentMode: state.paymentMode,
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
