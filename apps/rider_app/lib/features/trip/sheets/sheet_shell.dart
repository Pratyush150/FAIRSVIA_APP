part of 'ride_sheets.dart';

/// The sheet shell: the phase → sheet dispatcher, and the small pieces
/// (warnings, busy/error cards, the SOS and chat affordances) that more than
/// one sheet needs.

/// The phases whose sheet is held at a set share of the screen
/// ([RiderSheetHeights]): ride options, finding a driver (when set) and a
/// ride-complete page that leaves a map peek. Null: the sheet fits its
/// content.
double? _fixedFraction(TripPhase phase, double screenHeight) {
  final h = RiderSheetHeights.current;
  return switch (phase) {
    TripPhase.choosingRide => h.chooseRideAt(screenHeight),
    TripPhase.searching => h.searching,
    TripPhase.completed when h.completed < 1 => h.completed,
    _ => null,
  };
}

bool _completedFullScreen(TripPhase phase) =>
    phase == TripPhase.completed && RiderSheetHeights.current.completed >= 1;

class RideSheetForPhase extends StatelessWidget {
  const RideSheetForPhase({
    super.key,
    required this.state,
    required this.onSearch,
    this.savedPlaces = const [],
    required this.onPickSaved,
    this.locationIssue,
    this.onFixLocation,
    this.onSheetSettled,
  });

  /// Called when a dragged sheet settles on a new size (rest / expanded /
  /// peek), so the map's fit padding can follow it — only on settle, not
  /// per drag frame, so the camera does not churn.
  final VoidCallback? onSheetSettled;

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
      TripPhase.loadingEstimate => const _InfoCard(
        child: _Busy(label: 'Finding the best route…'),
      ),
      TripPhase.choosingRide => _RideOptions(state: state),
      TripPhase.requesting => const _InfoCard(
        child: _Busy(label: 'Requesting your ride…'),
      ),
      TripPhase.scheduled => _ScheduledConfirmation(state: state),
      TripPhase.searching => _FindingDriver(state: state),
      TripPhase.driverEnRoute => DriverInfoSheet(state: state, arrived: false),
      TripPhase.driverArrived => DriverInfoSheet(state: state, arrived: true),
      TripPhase.onTrip => OnTripSheet(state: state),
      TripPhase.completed => CompletedSheet(state: state),
      TripPhase.error => _ErrorCard(
        message: state.error ?? 'Something went wrong',
        onRetry: onSearch,
        onBack: context.read<TripCubit>().backFromError,
      ),
    };
    final footer =
        state.phase == TripPhase.choosingRide && state.estimate != null
        ? _RideConfirmFooter(state: state)
        : state.phase == TripPhase.completed
        ? const CompletedDoneButton()
        : null;
    if (AppGlass.enabled) {
      // Plan F: one floating glass card that morphs between phases.
      return _GlassPhaseSheet(
        state: state,
        footer: footer,
        chromeless: state.phase == TripPhase.idle && locationIssue == null,
        onSettled: onSheetSettled,
        child: child,
      );
    }
    return _ClassicPhaseSheet(
      state: state,
      footer: footer,
      onSettled: onSheetSettled,
      child: child,
    );
  }
}

/// Every build but Plan F: the solid sheet, cross-fading between phases,
/// draggable between its sizes as the glass card is ([_SheetDrag]).
class _ClassicPhaseSheet extends StatefulWidget {
  const _ClassicPhaseSheet({
    required this.state,
    required this.child,
    required this.footer,
    this.onSettled,
  });

  final TripState state;
  final Widget child;
  final Widget? footer;
  final VoidCallback? onSettled;

  @override
  State<_ClassicPhaseSheet> createState() => _ClassicPhaseSheetState();
}

class _ClassicPhaseSheetState extends State<_ClassicPhaseSheet>
    with SingleTickerProviderStateMixin, _SheetDrag {
  @override
  TripPhase get dragPhase => widget.state.phase;

  @override
  VoidCallback? get onSettled => widget.onSettled;

  @override
  void didUpdateWidget(_ClassicPhaseSheet old) {
    super.didUpdateWidget(old);
    if (old.state.phase != widget.state.phase) resetDrag();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final child = widget.child;
    final footer = widget.footer;
    final toggles = _draggablePhase(state.phase);
    // Cross-fade + slide between phases, and smoothly resize the sheet as each
    // phase's content changes height — so the flow feels like one continuous
    // surface rather than a stack of hard-swapped cards. Under Reduce Motion
    // it is a plain cross-fade: no slide, and the sheet snaps to its new size.
    final reduced = AppMotion.reduced(context);
    final fixed = _fixedFraction(
      state.phase,
      MediaQuery.sizeOf(context).height,
    );
    return draggable(
      AppSheet(
        height: sheetHeight,
        onHandleTap: toggles ? toggleSheet : null,
        handleLabel: toggles ? handleLabel : null,
        // Keep the routed map visible while choosing a ride: the options sheet
        // is otherwise tall enough to hide the route and both markers. The
        // live phases rest at their compact share too (the decided ratio);
        // a drag up shows the rest of the sheet.
        maxHeightFraction: _glassCompactPhase(state.phase)
            ? RiderSheetHeights.current.liveCompactAt(
                onTrip: state.phase == TripPhase.onTrip,
                screenHeight: MediaQuery.sizeOf(context).height,
              )
            : fixed,
        minHeightFraction: fixed,
        // Ride complete: the sheet grows into a full-screen page (or nearly).
        fullScreen: _completedFullScreen(state.phase),
        footer: footer,
        child: _MaybeAnimatedSize(
          reduced: reduced,
          child: AnimatedSwitcher(
            duration: AppMotion.slow,
            switchInCurve: AppMotion.enter,
            switchOutCurve: AppMotion.exit,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: reduced
                  ? child
                  : SlideTransition(
                      position: Tween(
                        begin: const Offset(0, 0.06),
                        end: Offset.zero,
                      ).animate(anim),
                      child: child,
                    ),
            ),
            layoutBuilder: (currentChild, previousChildren) => Stack(
              alignment: Alignment.bottomCenter,
              children: [...previousChildren, ?currentChild],
            ),
            child: KeyedSubtree(key: ValueKey(state.phase), child: child),
          ),
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
        const Icon(
          PhosphorIconsRegular.info,
          size: 16,
          color: AppColors.warning,
        ),
        const SizedBox(width: AppSpacing.xs),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodySmall?.copyWith(
              color: AppColors.warningTextOf(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// On-trip readout: "Arriving 3:42 PM · 12 min · 4.1 mi to go" built from the
/// live progress, or from the routed estimate before the first ping.
/// True when the live headline already says the minutes left ("12 min to
/// destination"), so a second line must not repeat them.
bool _headlineHasMinutes(TripState state) =>
    RideStatus.of(state).subtitle?.contains(' min') ?? false;

/// "Arriving 2:23 PM · 12 min · 4.1 km to go"; without the minutes
/// ("Arriving 2:23 PM · 4.1 km to go") when [withMinutes] is false because
/// they are shown elsewhere on the same sheet.
String? _tripEtaLine(TripState state, {bool withMinutes = true}) {
  final secs = state.liveEtaSec ?? state.estimate?.durationS;
  final metres = state.liveRemainingM ?? state.estimate?.distanceM;
  if (secs == null) return null;
  final arrival = DateTime.now().add(Duration(seconds: secs));
  final h = arrival.hour % 12 == 0 ? 12 : arrival.hour % 12;
  final clock =
      '$h:${arrival.minute.toString().padLeft(2, '0')} ${arrival.hour < 12 ? 'AM' : 'PM'}';
  final mins = (secs / 60).ceil().clamp(1, 999);
  final dist = metres == null ? '' : ' · ${Fmt.distance(metres)} to go';
  return withMinutes
      ? 'Arriving $clock · $mins min$dist'
      : 'Arriving $clock$dist';
}

/// Opens the safety toolkit (SOS) for the active trip.
void _openSafety(BuildContext context, TripState state) {
  final tripId = state.trip?.id;
  if (tripId == null) return;
  final at = state.driverLocation;
  final where = at == null
      ? ''
      : ' Where I am: https://maps.google.com/?q=${at.lat.toStringAsFixed(5)},${at.lng.toStringAsFixed(5)}';
  final cubit = context.read<TripCubit>();
  final share = '${riderTripShareText(state)}$where';
  showSafetySheet(
    context,
    tripId: tripId,
    safety: sl<SafetyRemoteDataSource>(),
    shareText: share,
    // The rider is in the car: their own fix first, the car's last position
    // if the phone has none.
    locate: () async {
      try {
        final p =
            await Geolocator.getLastKnownPosition() ??
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
  // Regular: nothing is "on" at rest (audit 2.1 rule 3 — Fill is state).
  icon: PhosphorIconsRegular.shieldCheck,
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

/// Shares the trip text with the public live-tracking link when the backend
/// issues one; without it if that request fails (never blocks sharing).
void _shareTrip(BuildContext context, TripState state) {
  final tripId = state.trip?.id;
  if (tripId == null) {
    shareTripText(context, riderTripShareText(state));
    return;
  }
  shareTripTextWithLink(
    context,
    riderTripShareText(state),
    fetchLink: () => sl<SafetyRemoteDataSource>().tripShareLink(tripId),
  );
}

/// `I'm on a RideVela ride to PLACE. Car: VEHICLE, plate PLATE. Driver: NAME.`
/// — shared by the Share pill, the ••• menu and the safety sheet, each of
/// which appends `Track my ride live: URL` once the backend has issued the
/// trip's public tracking link (see [shareTripTextWithLink]).
String riderTripShareText(TripState state) {
  final d = state.driver;
  return tripShareText(
    brand: AppBrand.name,
    destination: state.dropoffAddr,
    vehicle: d?.vehicleLabel,
    // Spaced the way it is painted ("MH 12 AB 3456"), as on the card.
    plate: d?.plate == null ? null : Market.current.formatPlate(d!.plate!),
    driverName: d?.name,
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
      padding: const EdgeInsets.only(right: 6),
      child: Semantics(
        button: true,
        label: label,
        onTap: onTap,
        excludeSemantics: true,
        // The pill is drawn 40 tall, but the touch target is 48 (Android's
        // minimum, above iOS's 44): the 4 pt band above and below it still
        // takes the tap, without a ripple spilling past the pill.
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Material(
              // THEME=ink: an ink-outline pill on the paper.
              color: InkPaper.on
                  ? Colors.transparent
                  : dark
                  ? AppColors.surfaceMutedDark
                  : AppColors.surfaceMutedLight,
              shape: InkPaper.on
                  ? StadiumBorder(
                      side: BorderSide(color: InkPaper.outline(dark)),
                    )
                  : const StadiumBorder(),
              child: InkWell(
                customBorder: const StadiumBorder(),
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 40),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 16,
                          color: theme.colorScheme.onSurface,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          label,
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
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
  unawaited(
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => ChatPage(
              tripId: tripId,
              currentUserId: userId,
              title: state.driver?.name ?? 'Driver',
              // "White Maruti Suzuki Dzire · MH 12 AB 1234" under the name.
              subtitle: _chatSubtitle(state),
              chat: sl<ChatRemoteDataSource>(),
              realtime: sl<RealtimeClient>(),
            ),
          ),
        )
        .then((_) => cubit.setChatOpen(false)),
  );
}

String? _chatSubtitle(TripState state) {
  final d = state.driver;
  if (d == null) return null;
  final parts = [
    if (d.vehicleLabel.isNotEmpty) d.vehicleLabel,
    if (d.plate != null) Market.current.formatPlate(d.plate!),
  ];
  return parts.isEmpty ? null : parts.join(' · ');
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
        // A calm looping sand-glass while the request goes through (a plain
        // spinner under Reduce Motion — LottieMoment draws nothing then).
        MediaQuery.maybeDisableAnimationsOf(context) ?? false
            ? const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(strokeWidth: 2.4),
              )
            : const LottieMoment.loading(size: 40),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.titleMedium),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    required this.onBack,
  });
  final String message;
  final VoidCallback onRetry;

  /// Out of the dead end: back to the ride options (or home).
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: const TextStyle(color: AppColors.error)),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                key: const Key('error-back'),
                onPressed: onBack,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
                child: const Text('Back'),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PrimaryButton(label: 'Try again', onPressed: onRetry),
            ),
          ],
        ),
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
  final trip = await Navigator.of(context).push<Trip>(
    MaterialPageRoute(
      builder: (_) => PreBookPage(
        repository: sl<TripRepository>(),
        pickup: state.pickup,
        pickupAddr: state.pickupAddr,
        paymentMode: state.paymentMode,
        paymentMethodId: state.selectedMethodId,
        payments: sl.isRegistered<PaymentsRemoteDataSource>()
            ? sl<PaymentsRemoteDataSource>()
            : null,
      ),
    ),
  );
  if (trip == null) return;
  final when = trip.scheduledAt;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          when == null
              ? 'Ride scheduled. Find it in Account › Scheduled rides.'
              : 'Ride scheduled for ${_formatSchedule(when)}. '
                    'Find it in Account › Scheduled rides.',
        ),
      ),
    );
}

/// The classic sheet's resize between phases: an [AnimatedSize], or under
/// Reduce Motion no wrapper at all — a zero-duration AnimatedSize threw
/// "RenderAnimatedSize was mutated in its own performLayout" in this tree
/// (as on the glass card).
class _MaybeAnimatedSize extends StatelessWidget {
  const _MaybeAnimatedSize({required this.reduced, required this.child});

  final bool reduced;
  final Widget child;

  @override
  Widget build(BuildContext context) => reduced
      ? child
      : AnimatedSize(
          duration: AppMotion.slow,
          curve: AppMotion.standard,
          alignment: Alignment.bottomCenter,
          child: child,
        );
}
