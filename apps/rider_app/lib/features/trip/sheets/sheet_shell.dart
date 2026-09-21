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
        const Icon(Icons.info_outline_rounded,
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
  final miles = metres == null ? null : (metres / 1609.344);
  final dist = miles == null
      ? ''
      : miles < 0.1
          ? ' · ${(metres! * 3.28084).round()} ft to go'
          : ' · ${miles.toStringAsFixed(1)} mi to go';
  return 'Arriving $clock · $mins min$dist';
}

/// Opens the safety toolkit (SOS) for the active trip.
void _openSafety(BuildContext context, TripState state) {
  final tripId = state.trip?.id;
  if (tripId == null) return;
  final share = '${AppBrand.name} trip to ${state.dropoffAddr ?? 'my destination'}. '
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

/// Chat bubble with an unread-count badge (Uber-style) for the sheet buttons.
class _ChatIcon extends StatelessWidget {
  const _ChatIcon({required this.unread});
  final int unread;

  @override
  Widget build(BuildContext context) {
    final icon = const Icon(Icons.chat_bubble_outline);
    if (unread <= 0) return icon;
    return Badge.count(count: unread, child: icon);
  }
}

/// Whole minutes for a duration, never showing "0 min" for a short hop.
int _minutes(num seconds) => (seconds / 60).ceil().clamp(1, 9999).toInt();
