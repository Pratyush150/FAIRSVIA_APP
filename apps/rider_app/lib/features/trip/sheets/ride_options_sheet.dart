part of 'ride_sheets.dart';

/// "Plan your ride": tier cascade, stops, schedule, payment, promo, pickup
/// note, and the confirm footer whose label always names the consequence.

/// Keys the list of pickable ride tiers on the choose-ride sheet.
const rideTierListKey = Key('ride-tier-list');

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
        // A Wrap, not a Row: at the largest text sizes the distance and time
        // drop under the title instead of running off the edge.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            Text(
              'Choose a ride',
              style: theme.textTheme.headlineSmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              '${Market.current.legDistance(estimate.distanceM)} · '
              '${_minutes(estimate.durationS)} min',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
        if (estimate.surge > 1.0)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              'Fares are higher due to demand (${estimate.surge.toStringAsFixed(1)}x)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.warningTextOf(context),
              ),
            ),
          ),
        // The search ran its whole window and found no driver: the
        // empty-state art and what to do next (try again, or book for later)
        // instead of a bare warning line.
        if (_noCarsNearby(state))
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _NoCarsNotice(
              message: state.error ?? 'No cars nearby right now.',
              onTryAgain: state.selectedTier == null
                  ? null
                  : () => cubit.confirmRide(),
              onSchedule: () async {
                final when = await pickRideTime(context);
                if (when != null) cubit.setScheduledAt(when);
              },
            ),
          )
        // Surfaced when a request comes back with a create error; the ride is
        // kept so the rider can just re-tap Confirm.
        else if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(
                  PhosphorIconsRegular.info,
                  size: 16,
                  color: AppColors.warning,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    state.error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: AppColors.warningTextOf(context),
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        _StopsSection(state: state),
        const SizedBox(height: AppSpacing.sm),
        // The sheet body is the only scroll view: an inner scrollable here
        // swallowed swipes and hid the payment/schedule/promo rows behind a
        // nested-scroll trap.
        ListView(
          // The pickable tier list — distinct from the compare table in the
          // extras below, which repeats the tier names.
          key: rideTierListKey,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final (i, tier) in _listOrder(estimate.tiers).indexed)
              _RideTierTile(
                tier: tier,
                // The request for this tier just came back with no driver:
                // the estimate's "Pickup in 4 min" is no longer true.
                noDrivers: _noDriversFor(state, tier.tier),
                tripDurationS: estimate.durationS,
                selected: tier.tier == state.selectedTier,
                // Every ride type is bright and pickable. One with no car
                // nearby says so on its row — booking it starts a search that
                // keeps looking for a while (the server's search window).
                onTap: () {
                  AppHaptics.selection();
                  cubit.selectTier(tier.tier);
                },
              ).motion(
                (w) => w
                    .animate()
                    .fadeIn(
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                    )
                    .moveY(
                      begin: 8,
                      end: 0,
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                      curve: AppMotion.enter,
                    ),
              ),
          ],
        ),
        if (estimate.comparison != null) ...[
          const SizedBox(height: AppSpacing.sm),
          PriceComparisonCard(comparison: estimate.comparison!),
        ],
        const SizedBox(height: AppSpacing.sm),
        _ScheduleRow(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PromoField(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PickupNoteField(state: state),
        const SizedBox(height: AppSpacing.sm),
        _BookForSomeoneElseRow(state: state),
        // Below the fold at rest; what the sheet shows once pulled all the
        // way up, so it reads complete rather than ending in empty space.
        const SizedBox(height: AppSpacing.xl),
        _RideOptionsExtras(state: state),
      ],
    );
  }
}

/// The pulled-up part of "Choose a ride": the ride types side by side, what
/// the price is made of, the safety tools every ride has, and posters for
/// what the rider can do next. Every number comes from the estimate.
class _RideOptionsExtras extends StatelessWidget {
  const _RideOptionsExtras({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final estimate = state.estimate!;
    final cubit = context.read<TripCubit>();
    final tiers = _listOrder(estimate.tiers);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tiers.isNotEmpty)
          SheetSection(
            title: 'Compare rides',
            icon: PhosphorIconsRegular.squaresFour,
            child: CompareTable(
              columns: const ['Seats', 'Pickup', 'Fare'],
              rows: [
                for (final t in tiers)
                  CompareRow(
                    label: t.label,
                    highlighted: t.tier == state.selectedTier,
                    cells: [
                      '${t.capacity}',
                      _noDriversFor(state, t.tier) || t.etaSeconds == null
                          ? '—'
                          : '${_minutes(t.etaSeconds!)} min',
                      Fmt.money(t.fare, t.currency),
                    ],
                  ),
              ],
            ),
          ),
        const SizedBox(height: AppSpacing.lg),
        SheetSection(
          title: 'About this fare',
          icon: PhosphorIconsRegular.receipt,
          child: InfoPoints([
            InfoPoint(
              icon: PhosphorIconsRegular.path,
              title: 'Your route',
              text:
                  '${Market.current.legDistance(estimate.distanceM)} · about '
                  '${_minutes(estimate.durationS)} min of driving.',
            ),
            InfoPoint(
              icon: PhosphorIconsRegular.trendUp,
              title: 'Demand',
              text: estimate.surge > 1.0
                  ? 'Fares are ${estimate.surge.toStringAsFixed(1)}x right '
                        'now because many people are riding.'
                  : 'No demand surcharge on this quote.',
            ),
            const InfoPoint(
              icon: PhosphorIconsRegular.ruler,
              title: 'Final fare',
              text:
                  'Based on the distance and time actually driven. Tolls '
                  'and waiting time are charged separately.',
            ),
            if (tiers.any((t) => t.breakdown != null))
              const InfoPoint(
                icon: PhosphorIconsRegular.info,
                title: 'Itemised',
                text: 'Tap the info icon on a ride for its full fare.',
              ),
          ]),
        ),
        const SizedBox(height: AppSpacing.lg),
        const SheetSection(
          title: 'Safety on every ride',
          icon: PhosphorIconsRegular.shieldCheck,
          card: false,
          child: FeatureGrid([
            FeatureItem(
              icon: PhosphorIconsRegular.checks,
              title: 'Start code',
              subtitle: 'Your ride starts only with your PIN.',
            ),
            FeatureItem(
              icon: PhosphorIconsRegular.export,
              title: 'Share your trip',
              subtitle: 'Send a live link to family.',
            ),
            FeatureItem(
              icon: PhosphorIconsRegular.siren,
              title: 'SOS',
              subtitle: 'Alert your emergency contacts.',
            ),
            FeatureItem(
              icon: PhosphorIconsRegular.chatCircle,
              title: 'In-app chat',
              subtitle: 'Message your driver without sharing a number.',
            ),
          ]),
        ),
        const SizedBox(height: AppSpacing.lg),
        SheetSection(
          title: 'More with ${AppBrand.name}',
          icon: PhosphorIconsRegular.lightning,
          card: false,
          // The poster is a fixed-height image card: past 1.5x its copy
          // would outgrow it (the headline is still large at that size).
          child: MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: PromoCarousel([
              for (final p in homePosters(
                onOffers: () {},
                onSchedule: () async {
                  final when = await pickRideTime(context);
                  if (when != null) cubit.setScheduledAt(when);
                },
                onSafety: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => EmergencyContactsPage(
                      safety: sl<SafetyRemoteDataSource>(),
                    ),
                  ),
                ),
                onRide: () {},
              ))
                // The offers poster is the promo field above; the "start a
                // ride" one is this screen.
                if (p.id == 'poster-schedule' || p.id == 'poster-safety') p,
            ], padding: EdgeInsets.zero),
          ),
        ),
      ],
    );
  }
}

/// The order the ride list shows: the server's. It already leads with
/// India's own vehicles for the Pune market (cheapest first: bike, auto,
/// then the cars), so every look — Plan D included — keeps it.
List<FareTier> _listOrder(List<FareTier> tiers) => tiers;

/// "Riding yourself, or booking for someone else?" The booker still pays and
/// still tracks the ride; the passenger is who the driver collects, and who
/// gets the start code by text — they may not have the app at all.
class _BookForSomeoneElseRow extends StatelessWidget {
  const _BookForSomeoneElseRow({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    final passenger = state.passenger;

    if (passenger == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(PhosphorIconsRegular.userPlus, size: 20),
          label: const Text('Book for someone else'),
          onPressed: () async {
            final result = await _askPassenger(context, null);
            if (result != null) cubit.setPassenger(result);
          },
        ),
      );
    }

    return Row(
      children: [
        Icon(
          PhosphorIconsRegular.userCircle,
          size: 20,
          color: AppColors.accent,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                // No name given: the number, spaced as it is read aloud.
                'Ride for ${(passenger.name?.trim().isEmpty ?? true) ? Fmt.phone(passenger.phone) : passenger.displayName}',
                style: theme.textTheme.bodyMedium,
              ),
              Text(
                'They get the start code by text',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
        TextButton(
          onPressed: () async {
            final result = await _askPassenger(context, passenger);
            if (result != null) cubit.setPassenger(result);
          },
          child: const Text('Edit'),
        ),
        IconButton(
          tooltip: 'Ride it myself',
          icon: const Icon(PhosphorIconsRegular.x, size: 20),
          onPressed: () => cubit.setPassenger(null),
        ),
      ],
    );
  }
}

/// Collect the passenger's name and number. A number is required — the driver
/// calls it and the start code is texted to it — so the dialog refuses to
/// return without one. Returns null if the rider backs out.
Future<TripPassenger?> _askPassenger(
  BuildContext context,
  TripPassenger? existing,
) {
  final nameCtrl = TextEditingController(text: existing?.name ?? '');
  // Spaced for reading ("+91 98765 43210"); toE164 strips the spaces again.
  final phoneCtrl = TextEditingController(
    text: existing == null ? '' : Fmt.phone(existing.phone),
  );
  return showDialog<TripPassenger>(
    context: context,
    builder: (dialogCtx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Who is riding?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Their name (optional)',
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const Key('pick-from-contacts'),
                  icon: const Icon(Icons.contacts_outlined),
                  label: const Text('Pick from contacts'),
                  onPressed: () async {
                    PickedContact? picked;
                    try {
                      picked = await pickContactSafely();
                    } on ContactPickerUnavailable {
                      if (!ctx.mounted) return;
                      setLocal(
                        () => error =
                            "Couldn't open your contacts. Type the number instead.",
                      );
                      return;
                    }
                    // Cancelled: leave whatever was typed alone.
                    if (picked == null || !ctx.mounted) return;
                    final phone = normalizeContactPhone(picked.phone);
                    setLocal(() {
                      final name = picked!.name?.trim() ?? '';
                      if (name.isNotEmpty) nameCtrl.text = name;
                      if (phone != null) {
                        phoneCtrl.text = Fmt.phone(phone);
                        error = null;
                      } else {
                        error = 'That contact has no usable mobile number';
                      }
                    });
                  },
                ),
              ),
              TextField(
                controller: phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: 'Their mobile number',
                  hintText: Market.current.examplePhone,
                  errorText: error,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'We text them the start code and let you know when the '
                'driver arrives. You still pay and can track the ride.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                // Texted the start code, so it must be a dialable number;
                // a local number gets this market's country code.
                final phone = Market.current.toE164(phoneCtrl.text);
                if (phone == null) {
                  setLocal(() => error = 'Enter their mobile number');
                  return;
                }
                final name = nameCtrl.text.trim();
                Navigator.pop(
                  dialogCtx,
                  TripPassenger(phone: phone, name: name.isEmpty ? null : name),
                );
              },
              child: const Text('Done'),
            ),
          ],
        ),
      );
    },
  );
}

/// Pinned footer for the ride-options sheet: the confirm CTA and the
/// "change destination" escape hatch stay visible even when the options
/// above (surge line, stops, comparison card, promo) overflow and scroll.
class _RideConfirmFooter extends StatelessWidget {
  const _RideConfirmFooter({required this.state});
  final TripState state;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripCubit>();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // How it's paid sits right above the button that commits to it.
        _PaymentModeToggle(state: state),
        const SizedBox(height: AppSpacing.sm),
        PrimaryButton(
          label: _confirmLabel(state),
          onPressed: state.selectedTier != null
              ? () => cubit.confirmRide()
              : null,
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
      MaterialPageRoute(
        builder: (_) => DestinationSearchPage(
          singleDestination: true,
          // Only used to bias/sort the suggestions in this mode.
          initialPickup: state.pickup,
        ),
      ),
    );
    if (details != null) {
      await cubit.addStop(
        TripStop(point: details.location, address: details.shortAddress),
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
                const Icon(PhosphorIconsRegular.record, size: 20),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    state.stops[i].address ?? 'Stop ${i + 1}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                IconButton(
                  tooltip: 'Remove stop ${i + 1}',
                  onPressed: () => cubit.removeStop(i),
                  icon: const Icon(PhosphorIconsRegular.x, size: 20),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: canAdd ? () => _addStop(context) : null,
            icon: const Icon(PhosphorIconsRegular.mapPinPlus, size: 20),
            label: Text(canAdd ? 'Add stop' : 'Max 3 stops'),
          ),
        ),
      ],
    );
  }
}

/// Whether [tier] is the one a ride request just came back from with no
/// driver ([TripCubit.noDriversNearby]; the cubit keeps the booked tier
/// selected when it drops back to the options).
bool _noDriversFor(TripState state, String tier) =>
    state.error == TripCubit.noDriversNearby &&
    (state.trip?.tier ?? state.selectedTier) == tier;

/// Whether the options should show the no-cars empty state: the last
/// request's search ran out without a driver. A ride type merely having no
/// car nearby yet is not that — it can still be booked (the search keeps
/// looking for a while), and its row says so.
bool _noCarsNearby(TripState state) =>
    state.error == TripCubit.noDriversNearby && state.scheduledAt == null;

/// The no-cars empty state: a magnifier looking around (fixed 64px box; a
/// still frame under Reduce Motion) beside what happened and what to do.
class _NoCarsNotice extends StatelessWidget {
  const _NoCarsNotice({
    required this.message,
    this.onTryAgain,
    this.onSchedule,
  });
  final String message;

  /// Search again for the same ride; null hides the button.
  final VoidCallback? onTryAgain;

  /// Open the ride-time picker; null hides the button.
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final notice = Row(
      children: [
        const LottieMoment.noCars(size: 64),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                message,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColors.warningTextOf(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Try again in a minute, or schedule the ride for later.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ],
    );
    if (onTryAgain == null && onSchedule == null) return notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        notice,
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            if (onTryAgain != null)
              TextButton.icon(
                onPressed: onTryAgain,
                icon: const Icon(PhosphorIconsRegular.arrowClockwise, size: 18),
                label: const Text('Try again'),
              ),
            if (onSchedule != null)
              TextButton.icon(
                onPressed: onSchedule,
                icon: const Icon(PhosphorIconsRegular.clock, size: 18),
                label: const Text('Schedule for later'),
              ),
          ],
        ),
      ],
    );
  }
}

/// A tier row's line when it has no pickup ETA to promise. Honest, not a
/// dead end: the ride can still be booked and the search keeps looking for a
/// while. After a search for it already ran out ([noDrivers]) it says that.
String _noneNearbyLine(String tier, bool noDrivers) {
  final what = switch (tier) {
    'auto' => 'autos',
    'bike' => 'bikes',
    _ => 'cars',
  };
  return noDrivers
      ? 'No $what found — try again'
      : 'No $what nearby now — we\'ll keep looking';
}

String _confirmLabel(TripState state) {
  final fare = state.selectedFare;
  if (fare == null) return 'Choose a ride';
  final net = state.discountedFare ?? fare.fare;
  final amount = (state.appliedPromo != null && net != fare.fare)
      ? net
      : fare.fare;
  final verb = state.scheduledAt != null ? 'Schedule' : 'Confirm';
  return '$verb ${fare.label} · ${Fmt.money(amount, fare.currency)}';
}

String _formatSchedule(DateTime when) {
  final local = when.toLocal();
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final ampm = local.hour < 12 ? 'AM' : 'PM';
  final min = local.minute.toString().padLeft(2, '0');
  return '${months[local.month - 1]} ${local.day}, $h:$min $ampm';
}

/// The native wheel picker on Apple platforms (the Material calendar + clock
/// dial looked out of place on iOS). Returns null when dismissed.
Future<DateTime?> _pickCupertino(BuildContext context) async {
  final now = DateTime.now();
  // Backend rule: at least 5 min ahead; keep a minute of slack (see the
  // Material path). Start on the next 5-minute mark an hour from now.
  final floor = now.add(const Duration(minutes: 6));
  var initial = now.add(const Duration(hours: 1));
  initial = initial.subtract(
    Duration(
      minutes: initial.minute % 5,
      seconds: initial.second,
      milliseconds: initial.millisecond,
      microseconds: initial.microsecond,
    ),
  );
  var picked = initial;
  final theme = Theme.of(context);
  final ok = await showCupertinoModalPopup<bool>(
    context: context,
    builder: (ctx) => Container(
      height: 340,
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      color: theme.colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            Row(
              children: [
                CupertinoButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  child: const Text('Cancel'),
                ),
                const Spacer(),
                Text('Schedule for', style: theme.textTheme.titleMedium),
                const Spacer(),
                CupertinoButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text('Done'),
                ),
              ],
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.dateAndTime,
                initialDateTime: initial,
                minimumDate: floor,
                maximumDate: now.add(const Duration(days: 30)),
                minuteInterval: 5,
                // A 12-hour wheel with an AM/PM column, whatever the phone's
                // 24-hour setting.
                use24hFormat: false,
                onDateTimeChanged: (d) => picked = d,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (ok != true) return null;
  return picked.isBefore(floor) ? floor : picked;
}

/// Wraps a time picker so it is always the plain 12-hour clock face with an
/// AM/PM toggle — even on a phone set to 24-hour time, which otherwise turns
/// the Material dial into a two-ring 0–23 clock.
Widget twelveHourClock(BuildContext context, Widget? child) => MediaQuery(
  data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: false),
  child: child ?? const SizedBox.shrink(),
);

/// Asks for a future pickup time — the native wheel on Apple platforms, the
/// Material date + time pickers elsewhere — clamped to the backend's rule
/// (at least 5 minutes ahead, with a minute of slack; up to 30 days).
Future<DateTime?> pickRideTime(BuildContext context) async {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.iOS || platform == TargetPlatform.macOS) {
    return _pickCupertino(context);
  }
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    firstDate: now,
    lastDate: now.add(const Duration(days: 30)),
    initialDate: now.add(const Duration(hours: 1)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(now.add(const Duration(hours: 1))),
    initialEntryMode: TimePickerEntryMode.dial,
    helpText: 'Pickup time',
    builder: twelveHourClock,
  );
  if (time == null) return null;
  final when = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  // Clamping to exactly now+5 and sending a few seconds later was rejected
  // by the backend with a 400 — hence 6.
  final floor = now.add(const Duration(minutes: 6));
  return when.isBefore(floor) ? floor : when;
}

/// "Ride now" vs "Schedule for …" row with a date/time picker.
class _ScheduleRow extends StatelessWidget {
  const _ScheduleRow({required this.state});
  final TripState state;

  Future<void> _pick(BuildContext context) async {
    final cubit = context.read<TripCubit>();
    final when = await pickRideTime(context);
    if (when != null) cubit.setScheduledAt(when);
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
        // 48 tall: Android's minimum touch target.
        constraints: const BoxConstraints(minHeight: 48),
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
            const Icon(PhosphorIconsRegular.clock, size: 20),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                when == null ? 'Ride now' : 'For ${_formatSchedule(when)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            if (when != null)
              IconButton(
                icon: const Icon(PhosphorIconsRegular.x, size: 20),
                tooltip: 'Ride now instead',
                onPressed: () => cubit.setScheduledAt(null),
              )
            else
              Text(
                'Schedule',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: AppColors.accentText,
                ),
              ),
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
        Icon(
          PhosphorIconsRegular.calendarCheck,
          color: AppColors.accent,
          size: 48,
        ),
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

  /// The saved card currently in effect: the explicitly chosen one, else the
  /// default, else the first. Null when there are no saved cards.
  Map<String, dynamic>? get _activeCard {
    final cards = state.paymentMethods;
    if (cards.isEmpty) return null;
    final id = state.selectedMethodId;
    if (id != null) {
      for (final c in cards) {
        if (c['id'] == id) return c;
      }
    }
    for (final c in cards) {
      if (c['isDefault'] == true) return c;
    }
    return cards.first;
  }

  static String _cardLabel(Map<String, dynamic> c) {
    final brand = (c['brand'] as String?)?.trim();
    final last4 = (c['last4'] as String?)?.trim();
    final b = (brand == null || brand.isEmpty) ? 'Card' : cardBrandName(brand);
    // Short form ("Mastercard ••5555") so long brands fit the half-width chip.
    return last4 == null || last4.isEmpty ? b : '$b ••$last4';
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<TripCubit>();
    final card = _activeCard;
    final cardSelected = state.paymentMode == 'card';
    final cardLabel = card == null ? 'Add card' : _cardLabel(card);
    // With >1 saved card, tapping Card opens a picker; otherwise it just
    // selects card mode (backend uses the default / mock method).
    final hasChoice = state.paymentMethods.length > 1;
    return Row(
      children: [
        Expanded(
          child: _PayChip(
            icon: PhosphorIconsRegular.creditCard,
            label: cardLabel,
            selected: cardSelected,
            trailing: hasChoice ? PhosphorIconsRegular.caretDown : null,
            onTap: () {
              if (card == null) {
                _addCard(context, cubit);
              } else if (hasChoice) {
                _showCardPicker(context, cubit);
              } else {
                cubit.setPaymentMode('card');
              }
            },
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: _PayChip(
            icon: PhosphorIconsRegular.money,
            label: 'Cash',
            selected: state.paymentMode == 'cash',
            onTap: () => cubit.setPaymentMode('cash'),
          ),
        ),
      ],
    );
  }

  /// No card on file: take the rider to Payment methods, then select the
  /// card they added (if any) for this ride.
  Future<void> _addCard(BuildContext context, TripCubit cubit) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaymentMethodsPage(
          payments: sl<PaymentsRemoteDataSource>(),
          stripeCardAdder: sl.isRegistered<StripeCardAdder>()
              ? sl<StripeCardAdder>()
              : null,
        ),
      ),
    );
    await cubit.loadPaymentMethods();
    if (cubit.state.paymentMethods.isNotEmpty) cubit.setPaymentMode('card');
  }

  Future<void> _showCardPicker(BuildContext context, TripCubit cubit) async {
    final cards = state.paymentMethods;
    final activeId = _activeCard?['id'];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetCtx) {
        final theme = Theme.of(sheetCtx);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  0,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text('Pay with', style: theme.textTheme.titleMedium),
              ),
              for (final c in cards)
                ListTile(
                  leading: const Icon(PhosphorIconsRegular.creditCard),
                  title: Text(_cardLabel(c)),
                  trailing: c['id'] == activeId
                      ? Icon(
                          PhosphorIconsRegular.check,
                          color: AppColors.accent,
                        )
                      : null,
                  onTap: () {
                    AppHaptics.selection();
                    cubit.selectPaymentCard(c['id'] as String);
                    Navigator.of(sheetCtx).pop();
                  },
                ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }
}

/// What marks the chosen option: the ink, or teal in THEME=ink (Plan E keeps
/// teal for the route and the selection).
Color get _selectionInk => InkPaper.on ? AppColors.highlight : AppColors.accent;

class _PayChip extends StatelessWidget {
  const _PayChip({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Selected is never colour alone: the chip's glyph becomes a check.
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: () {
          AppHaptics.selection();
          onTap();
        },
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          curve: AppMotion.standard,
          // 48 tall: Android's minimum touch target.
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          // THEME=ink: outlined on the paper; the chosen one in teal (the
          // selection colour), 1.6 wide, with the check.
          decoration: BoxDecoration(
            color: selected && !InkPaper.on
                ? (theme.brightness == Brightness.dark
                      ? AppColors.accentSoftDark
                      : AppColors.accentSoft)
                : null,
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            border: Border.all(
              color: selected
                  ? _selectionInk
                  : (InkPaper.on
                        ? InkPaper.outline(theme.brightness == Brightness.dark)
                        : theme.dividerColor),
              width: InkPaper.on ? (selected ? 1.6 : 1) : 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                selected ? PhosphorIconsFill.checkCircle : icon,
                size: 20,
                color: selected ? _selectionInk : null,
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected ? _selectionInk : null,
                  ),
                ),
              ),
              if (trailing != null)
                Icon(
                  trailing,
                  size: 20,
                  color: selected ? _selectionInk : null,
                ),
            ],
          ),
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
  void initState() {
    super.initState();
    _prefillOffer();
  }

  /// A code picked on the Offers page shows in the field — so if the server
  /// turned it down for this fare, the rider sees which code and why.
  void _prefillOffer() {
    final offer = widget.state.offerPromo;
    if (offer != null && _controller.text.isEmpty) {
      _controller.text = offer.code;
    }
  }

  @override
  void didUpdateWidget(covariant _PromoField old) {
    super.didUpdateWidget(old);
    _prefillOffer();
    // The field sits low in the scrolling sheet; an error or the "applied"
    // chip appearing below the fold went unseen. Bring it into view.
    final changed =
        old.state.promoError != widget.state.promoError ||
        old.state.appliedPromo != widget.state.appliedPromo;
    if (changed &&
        (widget.state.promoError != null ||
            widget.state.appliedPromo != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: AppMotion.of(context, AppMotion.normal),
        );
      });
    }
  }

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
            const Icon(
              PhosphorIconsRegular.tag,
              size: 20,
              color: AppColors.success,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${promo.code} applied · −${Money.format(promo.discount, wholeOnly: true)}',
                // Ink, not green: green text on the green tint is 3.4:1,
                // under WCAG AA. The green tag and tint still say "applied".
                style: theme.textTheme.bodyMedium,
              ),
            ),
            IconButton(
              icon: const Icon(PhosphorIconsRegular.x, size: 20),
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
                  prefixIcon: Icon(PhosphorIconsRegular.tag),
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
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.error,
              ),
            ),
          ),
      ],
    );
  }
}

/// A small teal tick that plays once where a ride type was just selected
/// (the success moment, 24 px). Reduce Motion shows its still, final frame.
/// Decorative: the row's Semantics already says "selected".
class _SelectTick extends StatelessWidget {
  const _SelectTick();

  @override
  Widget build(BuildContext context) {
    return const IgnorePointer(
      child: ExcludeSemantics(child: LottieMoment.success(size: 24)),
    );
  }
}

/// A quick scale bump (1 -> 1.03 -> 1) when [selected] turns true. Plays
/// once per selection, so pumpAndSettle settles; static under Reduce Motion.
class _SelectBump extends StatefulWidget {
  const _SelectBump({required this.selected, required this.child});
  final bool selected;
  final Widget child;

  @override
  State<_SelectBump> createState() => _SelectBumpState();
}

class _SelectBumpState extends State<_SelectBump>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  late final Animation<double> _scale = TweenSequence<double>([
    TweenSequenceItem(
      tween: Tween(begin: 1.0, end: 1.03)
          .chain(CurveTween(curve: Curves.easeOut)),
      weight: 40,
    ),
    TweenSequenceItem(
      tween: Tween(begin: 1.03, end: 1.0)
          .chain(CurveTween(curve: Curves.easeIn)),
      weight: 60,
    ),
  ]).animate(_c);

  @override
  void didUpdateWidget(_SelectBump old) {
    super.didUpdateWidget(old);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (widget.selected && !old.selected && !reduce) {
      _c.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}

class _RideTierTile extends StatelessWidget {
  const _RideTierTile({
    required this.tier,
    this.noDrivers = false,
    required this.tripDurationS,
    required this.selected,
    required this.onTap,
  });

  final FareTier tier;

  /// True when a request for this tier has just found no driver: the row
  /// then shows no pickup ETA ("No cars nearby") although the estimate
  /// quoted one. It stays pickable so the rider can try again.
  final bool noDrivers;

  /// The pickup ETA to show, or null when there is none to promise.
  int? get _eta => noDrivers ? null : tier.etaSeconds;

  /// Pickup → destination drive time, for the "Drop 11:41 PM" estimate.
  final int tripDurationS;
  final bool selected;

  /// Selects this ride type. Every type is pickable, with or without a car
  /// nearby (null only disables the row).
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return _SelectBump(
      selected: selected,
      child: AppVariant.local ? _buildLocal(context) : _buildDefault(context),
    );
  }

  Widget _buildDefault(BuildContext context) {
    final theme = Theme.of(context);
    final eta = _eta;
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      // Never dimmed: a ride type with no car nearby can still be booked.
      child: Padding(
        padding: EdgeInsets.only(bottom: InkPaper.on ? 0 : 4),
        child: Material(
          color: Colors.transparent,
          // THEME=ink: ruled rows, no box; the selection is the teal marker
          // under the name and a teal check (below).
          shape: InkPaper.on
              ? Border(
                  bottom: BorderSide(
                    color: InkPaper.rule(theme.brightness == Brightness.dark),
                  ),
                )
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppSpacing.radius),
                  // The selected ride is outlined in ink; the rest have no
                  // box at all.
                  side: BorderSide(
                    color: selected ? AppColors.highlight : Colors.transparent,
                    width: 2,
                  ),
                ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.md,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 76,
                    child: InkPaper.on
                        // THEME=ink: the teal check sits on the drawing's
                        // corner, so selection is never the underline's
                        // colour alone and the text column keeps its width.
                        ? Stack(
                            clipBehavior: Clip.none,
                            children: [
                              VehicleGlyph(tier: tier.tier, width: 76),
                              if (selected)
                                Positioned(
                                  left: -2,
                                  top: -4,
                                  child: Icon(
                                    PhosphorIconsRegular.check,
                                    size: 20,
                                    color: AppColors.highlight,
                                  ),
                                ),
                              if (selected)
                                const Positioned(
                                  left: -4,
                                  top: -6,
                                  child: _SelectTick(),
                                ),
                            ],
                          )
                        : Stack(
                            clipBehavior: Clip.none,
                            children: [
                              VehicleGlyph(tier: tier.tier, width: 76),
                              if (selected)
                                const Positioned(
                                  left: -4,
                                  top: -6,
                                  child: _SelectTick(),
                                ),
                            ],
                          ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: MarkerUnderline(
                                visible: InkPaper.on && selected,
                                child: Text(
                                  tier.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: InkPaper.on
                                        ? FontWeight.w600
                                        : FontWeight.w700,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Icon(
                              PhosphorIconsRegular.user,
                              size: 16,
                              color: theme.colorScheme.onSurface,
                            ),
                            Text(
                              '${tier.capacity}',
                              style: theme.textTheme.labelMedium,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          eta == null
                              ? _noneNearbyLine(tier.tier, noDrivers)
                              // When the car comes, and when the rider gets
                              // there: the two numbers people compare tiers on.
                              : 'Pickup in ${_minutes(eta)} min · Drop ${_arrivalClock(eta + tripDurationS)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    // Same rule as the confirm footer (Fmt.money), so the
                    // list and the button always agree.
                    Fmt.money(tier.fare, tier.currency),
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)
                        .tabular(),
                  ),
                  // What the number is made of — only when the backend
                  // itemised it; an empty breakdown is worse than none. The
                  // glyph is 20 but the target is a full 48 × 48, beside the
                  // fare rather than under it so the row stays one height.
                  if (tier.breakdown != null)
                    Semantics(
                      button: true,
                      label: 'Fare details for ${tier.label}',
                      onTap: () => showFareDetailsSheet(context, tier),
                      excludeSemantics: true,
                      child: InkResponse(
                        onTap: () => showFareDetailsSheet(context, tier),
                        radius: 22,
                        child: SizedBox(
                          width: 48,
                          height: 48,
                          child: Icon(
                            PhosphorIconsRegular.info,
                            size: 20,
                            color: theme.textTheme.bodySmall?.color,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Plan D's row: a warm card on the paper sheet. Selected = brand.tint
  /// fill with a 2 px brand border (5.2:1 brand text on the tint). The
  /// vehicle sits on a soft marigold ground; seats and the fare's make-up
  /// are warm chips, the latter a "Rate card" chip (48 dp target).
  Widget _buildLocal(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final eta = _eta;
    final ink = AppColors.inkFor(dark);
    return Semantics(
      selected: selected,
      button: true,
      enabled: onTap != null,
      // Never dimmed: a ride type with no car nearby can still be booked.
      child: Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
        child: Material(
          color: selected
              ? AppColors.softFor(dark)
              : (dark ? AppColors.surfaceDark : AppColors.surfaceLight),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
            side: BorderSide(
              color: selected
                  ? ink
                  : (dark ? AppColors.borderDark : AppColors.borderLight),
              width: selected ? 2 : 1,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.md,
                0,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 80,
                    height: 60,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // A marigold ground under the vehicle (art only).
                        Positioned(
                          bottom: 6,
                          child: Container(
                            width: 66,
                            height: 14,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              color: LocalColour.marigold.withValues(
                                alpha: dark ? 0.22 : 0.28,
                              ),
                            ),
                          ),
                        ),
                        VehicleGlyph(tier: tier.tier, width: 76),
                        if (selected)
                          const Positioned(
                            left: 0,
                            top: 0,
                            child: _SelectTick(),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Expanded(
                              child: Text(
                                tier.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: selected ? ink : null,
                                ),
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Text(
                              Fmt.money(tier.fare, tier.currency),
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700)
                                  .tabular(),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          eta == null
                              ? _noneNearbyLine(tier.tier, noDrivers)
                              : 'Pickup in ${_minutes(eta)} min · Drop ${_arrivalClock(eta + tripDurationS)}',
                          style: theme.textTheme.bodySmall,
                        ),
                        Row(
                          children: [
                            Semantics(
                              label: '${tier.capacity} seats',
                              excludeSemantics: true,
                              child: LocalChip(
                                label: '${tier.capacity}',
                                icon: PhosphorIconsRegular.user,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            if (tier.breakdown != null)
                              LocalChip(
                                label: 'Rate card',
                                icon: PhosphorIconsRegular.receipt,
                                semanticLabel: 'Fare details for ${tier.label}',
                                onTap: () =>
                                    showFareDetailsSheet(context, tier),
                              )
                            else
                              const SizedBox(height: 48),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// "5:42 PM" — when the car would reach the pickup.
  static String _arrivalClock(int etaSeconds) {
    final t = DateTime.now().add(Duration(seconds: etaSeconds));
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
  }
}

/// The itemised fare behind a tier's "Details" control: exactly the lines the
/// receipt will show after the ride, so the price is never a bare number the
/// rider has to take on trust. The backend guarantees these sum to the fare.
Future<void> showFareDetailsSheet(BuildContext context, FareTier tier) {
  final breakdown = tier.breakdown;
  if (breakdown == null) return Future<void>.value();
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${tier.label} fare', style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.md),
              FareBreakdownRows(
                breakdown: breakdown,
                currency: tier.currency,
                showTip: false,
              ),
              Divider(height: AppSpacing.lg, color: theme.dividerColor),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Estimated total', style: theme.textTheme.titleMedium),
                  Text(
                    Fmt.money(tier.fare, tier.currency),
                    style: theme.textTheme.titleMedium?.tabular(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'The final fare can differ if the route or traffic changes on '
                'the day. Tolls and waiting time are charged separately.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// Free-text note for the driver ("meet at the lobby"), stored on the trip and
/// shown on the driver's offer card and en-route sheet.
class _PickupNoteField extends StatefulWidget {
  const _PickupNoteField({required this.state});
  final TripState state;

  @override
  State<_PickupNoteField> createState() => _PickupNoteFieldState();
}

class _PickupNoteFieldState extends State<_PickupNoteField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.state.pickupNote ?? '',
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      textCapitalization: TextCapitalization.sentences,
      maxLength: 200,
      minLines: 1,
      maxLines: 2,
      decoration: const InputDecoration(
        hintText: 'Note for driver (e.g. "meet at the lobby")',
        prefixIcon: Icon(PhosphorIconsRegular.note),
        isDense: true,
        counterText: '',
      ),
      onChanged: (v) => context.read<TripCubit>().setPickupNote(v),
    );
  }
}
