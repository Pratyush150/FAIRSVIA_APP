part of 'ride_sheets.dart';

/// The sheets of a live ride: finding a driver, the driver on the way or
/// arrived, the trip in progress, and cancelling.

class _FindingDriver extends StatefulWidget {
  const _FindingDriver({required this.state});
  final TripState state;

  /// Always show the pulled-up extras (tests render the expanded page).
  bool get showExtras => debugFindingExtras;

  @override
  State<_FindingDriver> createState() => _FindingDriverState();
}

class _FindingDriverState extends State<_FindingDriver> {
  Timer? _timer;
  Timer? _tick;
  bool _stillLooking = false;
  final DateTime _shownAt = DateTime.now();

  /// When the server's search ends: its own deadline when it has sent one,
  /// else the default window from the request (or from when this showed).
  DateTime get _endsAt =>
      widget.state.searchEndsAt ??
      (widget.state.trip?.requestedAt?.toLocal() ?? _shownAt).add(
        RideStatus.searchWindow,
      );

  @override
  void initState() {
    super.initState();
    // Re-render once a second for the time-left line and ring.
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    // Count from when the ride was requested when the server says so (a
    // relaunch mid-search must not restart the clock); otherwise from now.
    final requested = widget.state.trip?.requestedAt;
    final elapsed = requested == null
        ? Duration.zero
        : DateTime.now().difference(requested.toLocal());
    final wait = RideStatus.stillLookingAfter - elapsed;
    if (wait <= Duration.zero) {
      _stillLooking = true;
    } else {
      _timer = Timer(wait, () {
        if (mounted) setState(() => _stillLooking = true);
      });
    }
  }

  _SheetDrag? _drag;

  /// The sheet is settled fully pulled up (expanded): it has a fixed height
  /// then, so extra content scrolls instead of growing it. Only once it has
  /// settled there, so a drag between rest and expanded, and the snap back
  /// to rest, move the compact card alone and it rests at the height it had.
  bool get _pulledUp {
    final d = _drag;
    return d != null &&
        d.sheetExpanded &&
        d._snapTween == null &&
        d._dragHeight != null;
  }

  void _onSnap() {
    if (mounted) setState(() {});
  }

  void _onSnapStatus(AnimationStatus _) => _onSnap();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final drag = context.findAncestorStateOfType<_SheetDrag>();
    if (!identical(drag, _drag)) {
      _drag?._snapAnim
        ?..removeListener(_onSnap)
        ..removeStatusListener(_onSnapStatus);
      _drag = drag;
      drag?._snapAnim
        ?..addListener(_onSnap)
        ..addStatusListener(_onSnapStatus);
    }
  }

  @override
  void dispose() {
    _drag?._snapAnim
      ?..removeListener(_onSnap)
      ..removeStatusListener(_onSnapStatus);
    _timer?.cancel();
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final place = RideStatus.placeName(state);
    var left = _endsAt.difference(DateTime.now());
    if (left.isNegative) left = Duration.zero;
    final total = left > RideStatus.searchWindow
        ? left
        : RideStatus.searchWindow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            // Animated radar sweeping for a nearby driver — reads as the system
            // actively looking, not a generic spinner. The default look uses
            // the Lottie sweep (a beam turning round the pickup pin); Plan D
            // keeps its kolam radar. Under Reduce Motion both hold still: the
            // Lottie shows one frame, the radar's ticker is muted. The map's
            // own rings round the pickup are unchanged.
            if (LocalArt.on)
              TickerMode(
                enabled: !AppMotion.reduced(context),
                child: ExcludeSemantics(
                  child: PulseRadar(
                    // Plan D's kolam needs room round the glyph.
                    size: 76,
                    child: Icon(
                      PhosphorIconsRegular.taxi,
                      size: 20,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              )
            else
              const LottieMoment.searching(size: 64),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: RideStatusHeader(
                status: RideStatus.of(state, stillLooking: _stillLooking),
                detail: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // What was booked, so the rider can check it while
                    // waiting: "Economy · ₹102 · Cash".
                    Text(
                      searchingSummary(state),
                      style: theme.textTheme.bodyMedium?.tabular(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      'To ${place ?? 'your destination'}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        // The search is bounded: say how long it can still run, with a
        // subtle ring draining towards the end of the window.
        Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: total.inMilliseconds == 0
                    ? 0
                    : left.inMilliseconds / total.inMilliseconds,
                strokeWidth: 2,
                color: AppColors.accent,
                backgroundColor: theme.dividerColor,
                semanticsLabel: 'Search time left',
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                RideStatus.searchTimeLeft(left),
                style: theme.textTheme.bodySmall,
              ),
            ),
          ],
        ),
        if (_stillLooking) ...[
          const SizedBox(height: AppSpacing.sm),
          // No "try another ride type" here: the cubit cannot re-request a
          // live search on another tier without cancelling it (which clears
          // the whole draft), so offering it would be a button that lies.
          Text(
            'Drivers nearby are busy. We’ll keep looking.',
            style: theme.textTheme.bodySmall,
          ),
        ],
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _SheetWarning(message: state.error!),
        ],
        const SizedBox(height: AppSpacing.lg),
        SecondaryButton(
          label: 'Cancel ride',
          onPressed: () => _confirmCancel(context, feeWarning: false),
        ),
        // This sheet rests at its content's height, so the extras show only
        // once the rider pulls it up (it is then a fixed height and
        // scrolls); at rest it stays the compact card it was.
        if (widget.showExtras || _pulledUp)
          LiveRideExtras(state: state, searching: true),
      ],
    );
  }
}

/// The booked ride's tier label ("Economy"), from the estimate when it is
/// held, else the tier id capitalised; "Ride" when nothing names it.
String _tierLabel(TripState state) {
  final tier = state.trip?.tier ?? state.selectedTier;
  if (tier == null) return 'Ride';
  for (final t in state.estimate?.tiers ?? const <FareTier>[]) {
    if (t.tier == tier) return t.label;
  }
  return tier.isEmpty ? 'Ride' : tier[0].toUpperCase() + tier.substring(1);
}

/// Who the pay strip names: the driver's first name, or "your driver"
/// mid-sentence when the payload has none.
String _payee(TripState state) {
  final n = RideStatus.driverName(state);
  return n == 'Your driver' ? 'your driver' : n;
}

bool _paysCash(TripState state) =>
    (state.trip?.paymentMode ?? state.paymentMode) == 'cash';

/// "Economy · ₹102 · Cash" — tier, whole-unit fare, payment mode — for the
/// finding-driver sheet. The fare is left out when nothing has priced the
/// ride yet rather than showing a zero. Public for tests.
String searchingSummary(TripState state) {
  final fare = state.displayFare;
  final currency =
      state.trip?.currency ??
      state.selectedFare?.currency ??
      state.estimate?.currency;
  return [
    _tierLabel(state),
    if (fare != null) Money.format(fare, currency: currency, wholeOnly: true),
    _paysCash(state) ? 'Cash' : 'Card',
  ].join(' · ');
}

/// Confirms a ride cancellation before calling through. When a driver is already
/// on the way ([feeWarning]), warns that a cancellation fee may apply, then — if
/// one was charged — tells the rider the exact amount. Prevents a silent charge.
Future<void> _confirmCancel(
  BuildContext context, {
  required bool feeWarning,
}) async {
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

/// "End your trip here?" → POST /trips/:id/end-early. The rider pays for the
/// distance travelled, at least the tier's minimum fare — never the full
/// up-front price. The completed sheet follows on success.
Future<void> _confirmEndEarly(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final cubit = context.read<TripCubit>();
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => EndTripEarlyDialog(
      minFare: cubit.state.trip?.minFare,
      currency: cubit.state.trip?.currency,
    ),
  );
  if (ok != true) return;
  final ended = await cubit.endTripEarly(reason: 'Rider ended the trip');
  if (!ended) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(cubit.state.error ?? 'Could not end the trip.')),
      );
  }
}

/// The rider's confirm for ending an in-progress ride early. Pops true to end.
class EndTripEarlyDialog extends StatelessWidget {
  const EndTripEarlyDialog({super.key, this.minFare, this.currency});

  /// The tier's minimum fare; null on older backends (generic wording).
  final double? minFare;
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final min = minFare == null
        ? 'at least the minimum fare'
        : 'min fare ${Fmt.money(minFare!, currency)}';
    return AlertDialog(
      title: const Text('End your trip here?'),
      content: Text("You'll pay for the distance travelled ($min)."),
      actions: [
        TextButton(
          key: const ValueKey('end-early-keep-riding'),
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Keep riding'),
        ),
        FilledButton(
          key: const ValueKey('end-early-confirm'),
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('End trip here'),
        ),
      ],
    );
  }
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
          AppSpacing.lg,
          AppSpacing.md,
          AppSpacing.lg,
          0,
        ),
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

/// Dials the driver through [dialer]; says so, with the number spaced the
/// way it is read, when no dialler could open it.
Future<void> _callDriver(
  BuildContext context,
  String phone,
  Future<bool> Function(String phone) dialer,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final ok = await dialer(phone);
  if (!ok) {
    messenger.showSnackBar(
      SnackBar(
        content: Text("Couldn't open the dialler for ${Fmt.phone(phone)}"),
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

  Future<void> _call(BuildContext context, String phone) =>
      _callDriver(context, phone, dialer);

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
            // Once the car is here: a pin drops and lands (plays once, holds
            // on the landed pin; one still frame under Reduce Motion). A
            // fixed 40px box, so the headline never shifts.
            if (arrived) ...[
              const LottieMoment.arrived(size: 40),
              const SizedBox(width: AppSpacing.sm),
            ],
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
                          child: Text(
                            waitingForLocation,
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            _RideMenuButton(state: state),
          ],
        ),
        // Safety on its own line under the headline (as on trip), so the
        // title keeps the width and "arriving in 9 min" never wraps
        // (audit 2026-09-25, top-10 #6).
        const SizedBox(height: AppSpacing.xs),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: _sosButton(context, state),
        ),
        if (state.error != null) ...[
          const SizedBox(height: AppSpacing.sm),
          _SheetWarning(message: state.error!),
        ],
        const SizedBox(height: AppSpacing.md),
        _DriverVehicleCard(
          driver: driver,
          tier: state.trip?.tier ?? state.selectedTier,
        ),
        if (otp != null) ...[
          const SizedBox(height: AppSpacing.md),
          _RidePin(pin: otp, driverName: RideStatus.driverName(state)),
        ],
        // Plan D: once the car is here, a cash rider sees who to pay.
        if (LocalArt.on &&
            arrived &&
            _paysCash(state) &&
            state.displayFare != null) ...[
          const SizedBox(height: AppSpacing.md),
          PayDriverStrip(
            amount: Money.format(
              state.displayFare!,
              currency:
                  state.trip?.currency ??
                  state.selectedFare?.currency ??
                  state.estimate?.currency,
              wholeOnly: true,
            ),
            driverName: _payee(state),
          ),
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
        // Below the fold (the compact card scrolls), so pulling the card
        // fully up shows a complete page, not an empty one.
        LiveRideExtras(state: state, searching: false),
      ],
    );
  }
}

/// Tests only: render the finding-driver sheet with its pulled-up extras
/// without driving the drag.
@visibleForTesting
bool debugFindingExtras = false;

/// The below-the-fold part of the finding-driver and driver-arriving sheets:
/// what fills the card when the rider pulls it fully up. Every figure is the
/// trip's own (tier, fare, payment, addresses, the driver's ETA); a figure
/// that is not known leaves its line out. [searching]: the finding-driver
/// variant (what was booked, what happens next); otherwise the driver is
/// assigned (pickup ETA and clock time, meeting tips). Public for tests.
/// "Driver arriving": the car glides along the bar toward a pickup pin as the
/// real ETA falls. Progress is how much of the first ETA seen for this trip
/// has elapsed (1 - eta / firstEta), so it only moves when the ETA does and
/// never invents a distance. One-shot tweens (see RideProgressCard), so tests
/// settle; Reduce Motion snaps.
class DriverArrivingCard extends StatefulWidget {
  const DriverArrivingCard({super.key, required this.etaSec});

  final int etaSec;

  @override
  State<DriverArrivingCard> createState() => _DriverArrivingCardState();
}

class _DriverArrivingCardState extends State<DriverArrivingCard> {
  late int _firstEta = widget.etaSec;

  @override
  void didUpdateWidget(DriverArrivingCard old) {
    super.didUpdateWidget(old);
    // A re-route can push the ETA up; widen the leg rather than go negative.
    if (widget.etaSec > _firstEta) _firstEta = widget.etaSec;
  }

  @override
  Widget build(BuildContext context) {
    final eta = widget.etaSec;
    final progress = _firstEta > 0 ? 1 - eta / _firstEta : 0.0;
    return RideProgressCard(
      icon: PhosphorIconsRegular.clock,
      title: 'Driver arriving',
      headline: '${(eta / 60).ceil()} min away',
      arrival:
          'At your pickup by '
          '${Fmt.time(DateTime.now().add(Duration(seconds: eta)))}',
      progress: progress.clamp(0.0, 1.0),
      glyph: PhosphorIconsRegular.car,
      endGlyph: PhosphorIconsRegular.mapPin,
      startLabel: 'Driver',
      endLabel: 'Your pickup',
    );
  }
}

class LiveRideExtras extends StatelessWidget {
  const LiveRideExtras({
    super.key,
    required this.state,
    required this.searching,
  });

  final TripState state;
  final bool searching;

  String? get _fareText {
    final fare = state.displayFare;
    if (fare == null) return null;
    return Money.format(
      fare,
      currency:
          state.trip?.currency ??
          state.selectedFare?.currency ??
          state.estimate?.currency,
      wholeOnly: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pickup = state.trip?.pickup.address ?? state.pickupAddr;
    final drop = state.trip?.dropoff.address ?? state.dropoffAddr;
    final tier = state.trip?.tier ?? state.selectedTier;
    final fare = _fareText;
    final eta = state.liveEtaSec ?? state.driver?.etaSec;
    final hasTrip = state.trip?.id != null;
    return Column(
      key: ValueKey(searching ? 'finding-extras' : 'driver-extras'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!searching && eta != null && eta > 0)
          RideExtrasSection(
            title: 'Pickup',
            child: DriverArrivingCard(
              key: ValueKey('driver-arriving-${state.trip?.id}'),
              etaSec: eta,
            ),
          ),
        // The driver sheet already shows the car, tier, pickup and payment
        // chips above the fold; only the finding sheet repeats what was
        // booked, and the driver sheet adds where the ride goes.
        if (!searching && drop != null)
          RideExtrasSection(
            title: 'Going to',
            child: AppCard(
              child: RouteTimeline(
                stops: [
                  for (final s in state.trip?.stops ?? const <TripStop>[])
                    RouteTimelineStop(
                      label: 'Stop',
                      address: s.address ?? 'Pinned location',
                    ),
                  RouteTimelineStop(label: 'Drop-off', address: drop),
                ],
              ),
            ),
          ),
        if (searching)
          RideExtrasSection(
            title: 'What you booked',
            child: AppCard(
              child: Row(
                children: [
                  VehicleGlyph(tier: tier ?? 'comfort', width: 72),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _tierLabel(state),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          [
                            ?fare,
                            _paysCash(state) ? 'Cash' : 'Card',
                          ].join(' · '),
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium?.tabular(),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (searching && (pickup != null || drop != null))
          RideExtrasSection(
            title: 'Route',
            child: AppCard(
              child: RouteTimeline(
                stops: [
                  RouteTimelineStop(
                    label: 'Pickup',
                    address: pickup ?? 'Your pickup point',
                  ),
                  for (final s in state.trip?.stops ?? const <TripStop>[])
                    RouteTimelineStop(
                      label: 'Stop',
                      address: s.address ?? 'Pinned location',
                    ),
                  RouteTimelineStop(
                    label: 'Drop-off',
                    address: drop ?? 'Your destination',
                  ),
                ],
              ),
            ),
          ),
        RideExtrasSection(
          title: 'Payment',
          child: RideDetailRowsCard(
            rows: [
              if (fare != null)
                RideDetailRow(
                  label: 'Fare',
                  value: fare,
                  emphasis: true,
                  icon: PhosphorIconsRegular.receipt,
                ),
              RideDetailRow(
                label: 'Pay by',
                value: _paysCash(state) ? 'Cash to your driver' : 'Card',
                icon: _paysCash(state)
                    ? PhosphorIconsRegular.money
                    : PhosphorIconsRegular.creditCard,
              ),
            ],
            footnote: searching
                ? 'Cancelling now is free — no driver has been assigned yet.'
                : 'Cancelling after a driver is assigned may carry a fee. '
                      'You will see it before you confirm.',
          ),
        ),
        RideExtrasSection(
          title: 'Stay safe',
          child: RideToolkitGrid(
            perRow: 3,
            actions: [
              RideToolkitAction(
                icon: PhosphorIconsRegular.export,
                label: 'Share trip',
                onTap: () => _shareTrip(context, state),
              ),
              if (hasTrip)
                RideToolkitAction(
                  icon: PhosphorIconsRegular.siren,
                  label: 'SOS & contacts',
                  danger: true,
                  onTap: () => _openSafety(context, state),
                ),
              RideToolkitAction(
                icon: PhosphorIconsRegular.headset,
                label: 'Get help',
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SupportPage(support: sl<SupportRemoteDataSource>()),
                  ),
                ),
              ),
            ],
          ),
        ),
        RideExtrasSection(
          title: searching ? 'While you wait' : 'Meeting your driver',
          child: RideDetailRowsCard(
            rows: searching
                ? const [
                    RideDetailRow(
                      icon: PhosphorIconsRegular.mapPin,
                      label: 'Stay near your pickup point',
                      value: '',
                    ),
                    RideDetailRow(
                      icon: PhosphorIconsRegular.bellRinging,
                      label: 'We’ll alert you when a driver accepts',
                      value: '',
                    ),
                    RideDetailRow(
                      icon: PhosphorIconsRegular.shieldCheck,
                      label: 'Check the plate before you get in',
                      value: '',
                    ),
                  ]
                : const [
                    RideDetailRow(
                      icon: PhosphorIconsRegular.car,
                      label: 'Match the plate and car before you get in',
                      value: '',
                    ),
                    RideDetailRow(
                      icon: PhosphorIconsRegular.shieldCheck,
                      label: 'Share the ride PIN only inside the car',
                      value: '',
                    ),
                    RideDetailRow(
                      icon: PhosphorIconsRegular.chatCircle,
                      label: 'Hard to find? Message or call your driver',
                      value: '',
                    ),
                  ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        // The posters are fixed-height art: cap their text like the on-trip
        // sheet does so large Dynamic Type cannot overflow them.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.5,
          child: PromoCarousel(
            [
              PromoBannerData(
                id: 'ride-poster-share',
                headline: 'Let family follow your ride',
                subline: 'Share a live trip link in one tap.',
                image: PromoPhoto.shareTrip,
                art: HomeArt.ride,
                onTap: () => _shareTrip(context, state),
              ),
              PromoBannerData(
                id: 'ride-poster-safety',
                headline: 'Help is one tap away',
                subline: 'SOS and your emergency contacts, on every ride.',
                image: PromoPhoto.safetyRide,
                art: HomeArt.someoneElse,
                tone: PromoTone.sun,
                onTap: hasTrip ? () => _openSafety(context, state) : null,
              ),
            ],
            padding: EdgeInsets.zero,
            autoAdvance: !AppMotion.reduced(context),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
      label: 'Ride PIN ${AppA11y.spell(pin)}. Tell $who when you get in.',
      excludeSemantics: true,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ride PIN',
                  style: inkSectionLabel(context, theme.textTheme.titleMedium),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tell $who when you get in',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
          // One box per digit, like a code on a receipt: easy to read out
          // one number at a time through a car window.
          for (final d in pin.split('')) ...[
            const SizedBox(width: 6),
            Container(
              width: 38,
              height: 46,
              alignment: Alignment.center,
              // THEME=ink: plain surface.2 boxes with ink digits.
              decoration: InkPaper.on
                  ? BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    )
                  : BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                      border: Border.all(color: AppColors.accent, width: 1.5),
                    ),
              child: Text(
                d,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Where to meet, which ride it is, and how it is paid.
class _PickupSummary extends StatelessWidget {
  const _PickupSummary({required this.state});

  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final cash = _paysCash(state);
    final pickup = state.trip?.pickup.address ?? state.pickupAddr;
    Widget chip(Widget icon, String label) => Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
        borderRadius: BorderRadius.circular(AppSpacing.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
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
          child: Icon(
            PhosphorIconsRegular.record,
            size: 20,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Pickup',
                style: inkSectionLabel(context, theme.textTheme.labelMedium),
              ),
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
                  chip(
                    const Icon(
                      PhosphorIconsRegular.car,
                      size: AppIconSize.inline,
                    ),
                    _tierLabel(state),
                  ),
                  chip(
                    cash
                        ? _HeroIcon(
                            asset: 'cash',
                            size: AppIconSize.inline,
                            fallback: const Icon(
                              PhosphorIconsRegular.money,
                              size: AppIconSize.inline,
                            ),
                          )
                        : const Icon(
                            PhosphorIconsRegular.creditCard,
                            size: AppIconSize.inline,
                          ),
                    cash ? 'Cash' : 'Card',
                  ),
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

/// The art key for the car on the driver card. Once the real car is known
/// ("White Maruti Suzuki Dzire") the neutral grey sedan stands in for it —
/// the booked tier's coloured art (a teal SUV for Comfort) would contradict
/// the words beside it (audit 2026-09-25 A.14). The tier's art only while
/// nothing is known about the car, and always for an auto or a bike (the
/// grey art is a sedan). Public for tests.
String driverCardArtKey(AssignedDriver? driver, String? tier) {
  // An auto-rickshaw or a bike is never a sedan: those keep their own art.
  if (tier == 'auto' || tier == 'bike') return tier!;
  final known = driver?.vehicleLabel.trim().isNotEmpty ?? false;
  return known ? 'driver' : (tier ?? 'comfort');
}

class _DriverVehicleCard extends StatelessWidget {
  const _DriverVehicleCard({required this.driver, this.tier});

  final AssignedDriver? driver;

  /// The booked ride type, for the vehicle art beside the driver.
  final String? tier;

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
    final vehicle = d?.vehicleLabel ?? '';
    final plate = d?.plate;
    final muted = dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;
    return AppCard(
      child: Row(
        children: [
          // The driver's face over the vehicle they are bringing (the booked
          // ride type's 3D art), like the big apps: the rider matches a
          // person and a car at a glance.
          Semantics(
            label: vehicle.isEmpty ? 'Car' : vehicle,
            excludeSemantics: true,
            child: SizedBox(
              width: 104,
              height: 64,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: VehicleGlyph(
                      tier: driverCardArtKey(d, tier),
                      width: 80,
                    ),
                  ),
                  Positioned(
                    left: 0,
                    top: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.colorScheme.surface,
                          width: 2,
                        ),
                      ),
                      child: AppAvatar(name: realName, size: 48),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The plate is what the rider checks at the kerb, so it is the
                // biggest thing on the card (Uber/Ola do the same).
                // A screen reader spells it out, one character at a time —
                // "M H 1 2…", not "MH twelve".
                if (plate != null)
                  Semantics(
                    label:
                        'Number plate ${AppA11y.spell(Market.current.formatPlate(plate))}',
                    excludeSemantics: true,
                    child: _InkPlate(
                      child: Text(
                        Market.current.formatPlate(plate),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.plate.copyWith(
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                if (vehicle.isNotEmpty)
                  Text(
                    vehicle,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        realName ?? 'Your driver',
                        style: theme.textTheme.titleSmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // No driver payload yet (e.g. restored after a cold
                    // start) — show "—" rather than inventing a 5.0.
                    Semantics(
                      label: d == null
                          ? 'Rating not known yet'
                          : 'Rated ${d.rating.toStringAsFixed(1)}',
                      excludeSemantics: true,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            PhosphorIconsFill.star,
                            size: 16,
                            color: AppColors.star,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            d == null ? '—' : d.rating.toStringAsFixed(1),
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't reach your driver — try again, or call them.",
          ),
        ),
      );
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
            const Icon(
              PhosphorIconsFill.checkCircle,
              size: 20,
              color: AppColors.success,
            ),
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
            _shareTrip(context, state);
          case 'help':
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) =>
                    SupportPage(support: sl<SupportRemoteDataSource>()),
              ),
            );
          case 'cancel':
            _confirmCancel(context, feeWarning: true);
          case 'end-early':
            _confirmEndEarly(context);
        }
      },
      itemBuilder: (_) => [
        const PopupMenuItem(
          value: 'share',
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.export),
            title: Text('Share trip status'),
          ),
        ),
        const PopupMenuItem(
          value: 'help',
          child: ListTile(
            leading: Icon(PhosphorIconsRegular.headset),
            title: Text('Help'),
          ),
        ),
        const PopupMenuDivider(),
        // Once the ride has started it can't be cancelled — only ended here.
        if (state.phase == TripPhase.onTrip)
          const PopupMenuItem(
            value: 'end-early',
            child: ListTile(
              leading: Icon(PhosphorIconsRegular.flag, color: AppColors.error),
              title: Text(
                'End trip here',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          )
        else
          const PopupMenuItem(
            value: 'cancel',
            child: ListTile(
              leading: Icon(PhosphorIconsRegular.x, color: AppColors.error),
              title: Text(
                'Cancel ride',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ),
      ],
    );
  }
}

/// The trip in progress. Public so it can be widget-tested; [dialer]
/// launches the driver's number (`tel:`), injectable for tests.
class OnTripSheet extends StatelessWidget {
  const OnTripSheet({super.key, required this.state, this.dialer = dialPhone});
  final TripState state;
  final Future<bool> Function(String phone) dialer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final phone = state.driver?.phone;
    // Plan G: a 3D icon needs something to sit on — the same soft disc as
    // the map buttons, instead of floating in the header.
    final discStyle = AppClay3D.on
        ? IconButton.styleFrom(
            backgroundColor: theme.brightness == Brightness.dark
                ? AppColors.surfaceMutedDark
                : AppColors.surfaceMutedLight,
            fixedSize: const Size(48, 48),
          )
        : null;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // On trip the map is the star: the sheet says the state, the time
        // left and the destination — once, in the headline ("On the way to
        // …") or, near the end, under "Arriving soon" — and gets out of the
        // way.
        RideStatusHeader(
          status: RideStatus.of(state),
          // Message and Call side by side, as while the driver was on the
          // way (audit 2026-09-25 A.21: on trip had no Call). Call only
          // when the payload carries a number — a dead button is worse
          // than none.
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: 'Message driver',
                style: discStyle,
                icon: _ChatIcon(unread: state.unreadMessages),
                onPressed: () => _openTripChat(context, state),
              ),
              if (phone != null)
                IconButton(
                  tooltip: 'Call driver',
                  style: discStyle,
                  icon: const Icon(PhosphorIconsRegular.phone),
                  onPressed: () => _callDriver(context, phone, dialer),
                ),
              // ••• — Share, Help and "End trip here".
              _RideMenuButton(state: state),
            ],
          ),
        ),
        // Safety and Share side by side, labelled: in-trip they are the two
        // things a rider may need in a hurry.
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          children: [_sosButton(context, state), _shareButton(context, state)],
        ),
        // The minutes are already in the headline's sub-line ("12 min to
        // destination"): here only the clock and the distance (A.21).
        if (_tripEtaLine(state, withMinutes: !_headlineHasMinutes(state))
            case final eta?) ...[
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              Icon(
                PhosphorIconsRegular.clock,
                size: 20,
                color: AppColors.accent,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  eta,
                  style: theme.textTheme.titleSmall?.tabular(),
                  maxLines: 2,
                ),
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
        // Below the fold: what the rider sees when they pull the sheet up.
        _OnTripExtras(state: state),
      ],
    );
  }
}

/// On trip, pulled up: the trip's progress, the driver and car, the route,
/// the safety toolkit, the fare and payment, and posters for what the rider
/// can do next. Every figure comes from the trip; a figure that is not
/// known leaves its line out rather than showing a made-up one.
class _OnTripExtras extends StatelessWidget {
  const _OnTripExtras({required this.state});

  final TripState state;

  static String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} '
        '${t.hour < 12 ? 'AM' : 'PM'}';
  }

  void _openContacts(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) =>
          EmergencyContactsPage(safety: sl<SafetyRemoteDataSource>()),
    ),
  );

  void _openHelp(BuildContext context) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SupportPage(support: sl<SupportRemoteDataSource>()),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final trip = state.trip;
    final secs = state.liveEtaSec ?? trip?.durationS;
    final left = state.liveRemainingM ?? trip?.distanceM;
    final total = trip?.distanceM;
    final progress = (left != null && total != null && total > 0)
        ? 1 - left / total
        : null;
    // The minutes and the destination are already in the header: here the
    // distance covered, and the arrival clock.
    final headline = (progress != null && total != null && left != null)
        ? '${Fmt.distance((total - left).clamp(0, total))} of ${Fmt.distance(total)}'
        : left != null
        ? '${Fmt.distance(left)} to go'
        : '';
    final currency =
        trip?.currency ??
        state.selectedFare?.currency ??
        state.estimate?.currency;
    final fare = state.displayFare;
    final promo = trip?.promoCode;
    final discount = trip?.promoDiscount ?? 0;
    final pickupAddr = trip?.pickup.address ?? state.pickupAddr;
    return Column(
      key: const ValueKey('on-trip-extras'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (headline.isNotEmpty)
          RideExtrasSection(
            title: 'Trip progress',
            child: RideProgressCard(
              key: const ValueKey('on-trip-progress'),
              title: 'Distance covered',
              icon: PhosphorIconsRegular.navigationArrow,
              headline: headline,
              arrival: secs == null
                  ? null
                  : 'Expected at ${_clock(DateTime.now().add(Duration(seconds: secs)))}',
              progress: progress,
              glyph: Icons.directions_car_filled,
              startLabel: progress == null ? null : 'Pickup',
              endLabel: progress == null ? null : 'Drop-off',
            ),
          ),
        RideExtrasSection(
          title: 'Your driver',
          child: _DriverVehicleCard(
            driver: state.driver,
            tier: trip?.tier ?? state.selectedTier,
          ),
        ),
        RideExtrasSection(
          title: 'Safety',
          child: RideToolkitGrid(
            actions: [
              RideToolkitAction(
                key: const ValueKey('toolkit-sos'),
                icon: PhosphorIconsRegular.siren,
                label: 'SOS',
                danger: true,
                onTap: () => _openSafety(context, state),
              ),
              RideToolkitAction(
                key: const ValueKey('toolkit-share'),
                icon: PhosphorIconsRegular.export,
                label: 'Share trip',
                onTap: () => _shareTrip(context, state),
              ),
              RideToolkitAction(
                key: const ValueKey('toolkit-contacts'),
                icon: PhosphorIconsRegular.addressBook,
                label: 'Contacts',
                onTap: () => _openContacts(context),
              ),
              RideToolkitAction(
                key: const ValueKey('toolkit-help'),
                icon: PhosphorIconsRegular.headset,
                label: 'Report issue',
                onTap: () => _openHelp(context),
              ),
            ],
          ),
        ),
        RideExtrasSection(
          title: 'Trip details',
          child: RideDetailRowsCard(
            key: const ValueKey('on-trip-fare'),
            rows: [
              if (pickupAddr != null)
                RideDetailRow(
                  icon: PhosphorIconsRegular.mapPin,
                  label: 'Pickup',
                  value: pickupAddr,
                ),
              RideDetailRow(
                icon: PhosphorIconsRegular.car,
                label: 'Ride',
                value: _tierLabel(state),
              ),
              if (promo != null && promo.isNotEmpty)
                RideDetailRow(
                  icon: PhosphorIconsRegular.tag,
                  label: 'Promo $promo',
                  value: discount > 0
                      ? '−${Money.format(discount, currency: currency)}'
                      : 'Applied',
                  positive: true,
                ),
              RideDetailRow(
                icon: _paysCash(state)
                    ? PhosphorIconsRegular.money
                    : PhosphorIconsRegular.creditCard,
                label: 'Payment',
                value: _paysCash(state) ? 'Cash' : 'Card',
              ),
              if (fare != null)
                RideDetailRow(
                  label: 'Estimated fare',
                  value: Money.format(fare, currency: currency),
                  emphasis: true,
                ),
            ],
            footnote: 'The final fare is confirmed when the trip ends.',
          ),
        ),
        RideExtrasSection(
          title: 'Next up',
          // Posters are fixed-ratio artwork: past 1.5x their copy would
          // spill out of the frame, so their text stops growing there.
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: PromoCarousel([
              PromoBannerData(
                id: 'ride-poster-return',
                headline: 'Plan your ride back',
                subline: 'Pre-book a pickup from where you are headed.',
                image: PromoPhoto.scheduleDusk,
                art: HomeArt.prebook,
                tone: PromoTone.mint,
                onTap: () => _RideQuickActions(state: state)._preBook(context),
              ),
              PromoBannerData(
                id: 'ride-poster-share',
                headline: 'Let family follow your ride',
                subline: 'Send a live trip link in one tap.',
                image: PromoPhoto.shareTrip,
                art: HomeArt.ride,
                onTap: () => _shareTrip(context, state),
              ),
              PromoBannerData(
                id: 'ride-poster-safety',
                headline: 'Help is one tap away',
                subline: 'Add emergency contacts for SOS on every ride.',
                image: PromoPhoto.safetyRide,
                art: HomeArt.someoneElse,
                tone: PromoTone.sun,
                onTap: () => _openContacts(context),
              ),
            ], padding: EdgeInsets.zero),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
                  child: Icon(
                    PhosphorIconsRegular.flag,
                    size: 20,
                    color: AppColors.warning,
                  ),
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
    final trip = await Navigator.of(context).push<Trip>(
      MaterialPageRoute(
        builder: (_) => PreBookPage(
          repository: sl<TripRepository>(),
          // Most pre-books from mid-ride are the ride back.
          pickup: state.trip?.dropoff.point ?? state.dropoff,
          pickupAddr: state.trip?.dropoff.address ?? state.dropoffAddr,
          paymentMode: state.trip?.paymentMode ?? state.paymentMode,
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Not in the last kilometre: by then a stop is a detour, not a plan.
        if (TripCubit.canAddStopTo(state) &&
            !RideStatus.nearlyThere(state)) ...[
          _QuickActionCard(
            icon: PhosphorIconsRegular.mapPinPlus,
            hero: 'add_stop',
            title: 'Add a stop',
            subtitle: 'See the new price before you confirm',
            onTap: () => _addStopToRide(context, state),
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        _QuickActionCard(
          icon: PhosphorIconsRegular.calendarCheck,
          hero: 'prebook',
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
    this.hero,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;

  /// The Plan B/C 3D art for this action (see [_HeroIcon]).
  final String? hero;
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
          // Plan B/C: the 3D hero art on a plain disc. Everywhere else (and
          // if the art fails to load): the one shared icon container.
          if (hero != null && _HeroIcon.enabled(context))
            // Plan G (clay3d): the render sits inside a 48 px disc with
            // room to breathe — at 40 on 40 its edges touched the rim.
            Container(
              width: AppClay3D.on ? 48 : 40,
              height: AppClay3D.on ? 48 : 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                shape: BoxShape.circle,
              ),
              child: _HeroIcon(
                asset: hero,
                size: AppClay3D.on ? 36 : 40,
                fallback: AppIconBadge(icon: icon),
              ),
            )
          else
            AppIconBadge(icon: icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleSmall),
                Text(
                  subtitle,
                  style: theme.textTheme.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(PhosphorIconsRegular.caretRight),
        ],
      ),
    );
  }
}

/// A Plan B/C ("daylight"/"daynight") or Plan G ("clay3d") 3D hero icon, or
/// [fallback] everywhere else. Only in a light-themed Plan B/C build: the art is lit for a light
/// background, and every other build must look exactly as before — which the
/// const [AppColors.planLight] guarantees at compile time. A missing or broken
/// asset falls back to the Phosphor glyph rather than an empty box.
/// THEME=ink: the plate drawn like a plate, the number inside a 1.5 px ink
/// border. Other builds: the text alone.
class _InkPlate extends StatelessWidget {
  const _InkPlate({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!InkPaper.on) return child;
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: Theme.of(context).colorScheme.onSurface,
          width: 1.5,
        ),
      ),
      child: child,
    );
  }
}

class _HeroIcon extends StatelessWidget {
  const _HeroIcon({
    required this.asset,
    required this.size,
    required this.fallback,
  });

  /// File name under `design_system/assets/heroes/daylight/`, without `.png`.
  final String? asset;
  final double size;
  final Widget fallback;

  /// Plan B/C in a light theme, or Plan G (THEME=clay3d) in either theme —
  /// its 3D renders come in a light and a dark set.
  static bool enabled(BuildContext context) =>
      AppClay3D.on ||
      (AppColors.planLight && Theme.of(context).brightness == Brightness.light);

  @override
  Widget build(BuildContext context) {
    final name = asset;
    if (name == null || !enabled(context)) return fallback;
    return Image.asset(
      AppClay3D.on
          ? AppClay3D.heroAsset(
              name,
              Theme.of(context).brightness == Brightness.dark,
            )
          : 'assets/heroes/daylight/$name.png',
      package: 'design_system',
      width: size,
      height: size,
      fit: BoxFit.contain,
      excludeFromSemantics: true,
      errorBuilder: (_, _, _) => fallback,
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
          _notice =
              'The price changed while you were deciding. '
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
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg + MediaQuery.viewPaddingOf(context).bottom,
      ),
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
                child: Text(
                  widget.stop.address ?? 'Pinned location',
                  style: theme.textTheme.bodyLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_error != null)
            Text(
              _error!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: AppColors.error,
              ),
            )
          else if (q == null)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(AppSpacing.md),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            if (_notice != null) ...[
              Text(
                _notice!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.warningTextOf(context),
                ),
              ),
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
                        Text(
                          Fmt.money(q.fareEstimate, q.currency),
                          style: theme.textTheme.headlineSmall,
                        ),
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
                      Text(
                        'was ${Fmt.money(q.previousFare, q.currency)}',
                        style: theme.textTheme.bodySmall,
                      ),
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
          await (widget.load ??
              () => sl<ContentRemoteDataSource>().rideCards())();
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
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Code $value copied — add it when you book your next ride.',
            ),
          ),
        );
      return;
    }
    final ok = await (widget.openUrl ?? openExternalUrl)(value);
    if (!ok) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't open that link.")),
      );
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
                      ? const [
                          AppColors.accentSoftDark,
                          AppColors.surfaceMutedDark,
                        ]
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
                        Text(
                          c.body,
                          style: theme.textTheme.bodySmall,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
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
