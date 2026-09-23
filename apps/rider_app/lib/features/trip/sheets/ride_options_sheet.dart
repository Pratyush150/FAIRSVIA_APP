part of 'ride_sheets.dart';

/// "Plan your ride": tier cascade, stops, schedule, payment, promo, pickup
/// note, and the confirm footer whose label always names the consequence.

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
            Expanded(
              child: Text('Choose a ride',
                  style: theme.textTheme.headlineSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: AppSpacing.sm),
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
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: AppColors.warning),
            ),
          ),
        // Surfaced when a request comes back with no drivers (or a create error);
        // the ride is kept so the rider can just re-tap Confirm.
        if (state.error != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Row(
              children: [
                const Icon(Icons.info_outline_rounded,
                    size: 16, color: AppColors.warning),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(state.error!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: AppColors.warning)),
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
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            children: [
              for (final (i, tier) in estimate.tiers.indexed)
                _RideTierTile(
                  tier: tier,
                  selected: tier.tier == state.selectedTier,
                  onTap: () {
                    AppHaptics.selection();
                    cubit.selectTier(tier.tier);
                  },
                ).animate().fadeIn(
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                    ).moveY(
                      begin: 8,
                      end: 0,
                      delay: AppMotion.stagger * i,
                      duration: AppMotion.normal,
                      curve: AppMotion.emphasized,
                    ),
            ],
          ),
        if (estimate.comparison != null) ...[
          const SizedBox(height: AppSpacing.sm),
          PriceComparisonCard(comparison: estimate.comparison!),
        ],
        const SizedBox(height: AppSpacing.sm),
        _PaymentModeToggle(state: state),
        const SizedBox(height: AppSpacing.sm),
        _ScheduleRow(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PromoField(state: state),
        const SizedBox(height: AppSpacing.sm),
        _PickupNoteField(state: state),
        const SizedBox(height: AppSpacing.sm),
        _BookForSomeoneElseRow(state: state),
      ],
    );
  }
}

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
          icon: const Icon(Icons.person_add_alt_outlined, size: 18),
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
        Icon(Icons.person_pin_circle_outlined,
            size: 18, color: AppColors.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Ride for ${passenger.displayName}',
                  style: theme.textTheme.bodyMedium),
              Text('They get the start code by text',
                  style: theme.textTheme.bodySmall),
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
          icon: const Icon(Icons.close, size: 18),
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
  final phoneCtrl = TextEditingController(text: existing?.phone ?? '');
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
                  TripPassenger(
                    phone: phone,
                    name: name.isEmpty ? null : name,
                  ),
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
  return '$verb ${fare.label} · ${Fmt.money(amount, fare.currency)}';
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

/// The native wheel picker on Apple platforms (the Material calendar + clock
/// dial looked out of place on iOS). Returns null when dismissed.
Future<DateTime?> _pickCupertino(BuildContext context) async {
  final now = DateTime.now();
  // Backend rule: at least 5 min ahead; keep a minute of slack (see the
  // Material path). Start on the next 5-minute mark an hour from now.
  final floor = now.add(const Duration(minutes: 6));
  var initial = now.add(const Duration(hours: 1));
  initial = initial.subtract(Duration(
    minutes: initial.minute % 5,
    seconds: initial.second,
    milliseconds: initial.millisecond,
    microseconds: initial.microsecond,
  ));
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
  );
  if (time == null) return null;
  final when =
      DateTime(date.year, date.month, date.day, time.hour, time.minute);
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
        Icon(Icons.event_available, color: AppColors.accent, size: 48),
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
            icon: Icons.credit_card,
            label: cardLabel,
            selected: cardSelected,
            trailing: hasChoice ? Icons.expand_more : null,
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
            icon: Icons.payments_outlined,
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
                    AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                child: Text('Pay with',
                    style: theme.textTheme.titleMedium),
              ),
              for (final c in cards)
                ListTile(
                  leading: const Icon(Icons.credit_card),
                  title: Text(_cardLabel(c)),
                  trailing: c['id'] == activeId
                      ? Icon(Icons.check, color: AppColors.accent)
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
    return InkWell(
      onTap: () {
        AppHaptics.selection();
        onTap();
      },
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.standard,
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: selected
              ? (theme.brightness == Brightness.dark
                  ? AppColors.accentSoftDark
                  : AppColors.accentSoft)
              : null,
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
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: selected ? AppColors.accent : null,
                ),
              ),
            ),
            if (trailing != null)
              Icon(trailing,
                  size: 18, color: selected ? AppColors.accent : null),
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
  void didUpdateWidget(covariant _PromoField old) {
    super.didUpdateWidget(old);
    // The field sits low in the scrolling sheet; an error or the "applied"
    // chip appearing below the fold went unseen. Bring it into view.
    final changed = old.state.promoError != widget.state.promoError ||
        old.state.appliedPromo != widget.state.appliedPromo;
    if (changed &&
        (widget.state.promoError != null ||
            widget.state.appliedPromo != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 250),
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
            const Icon(Icons.local_offer, size: 18, color: AppColors.success),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                '${promo.code} applied · −${Money.format(promo.discount, wholeOnly: true)}',
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

  IconData get _icon {
    switch (tier.tier) {
      case 'comfort':
        return Icons.directions_car_filled_rounded;
      case 'xl':
        return Icons.airport_shuttle_rounded;
      case 'premium':
        return Icons.local_taxi_rounded;
      default:
        return Icons.directions_car_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final eta = tier.etaSeconds;
    return Semantics(
      selected: selected,
      button: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            // The selected ride is outlined in ink; the rest have no box at all.
            side: BorderSide(
              color: selected ? AppColors.accent : Colors.transparent,
              width: 2,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm, AppSpacing.md, AppSpacing.md, AppSpacing.md),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Icon(_icon, size: 40, color: theme.colorScheme.onSurface),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(tier.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.titleMedium
                                      ?.copyWith(fontWeight: FontWeight.w700)),
                            ),
                            const SizedBox(width: 6),
                            Icon(Icons.person_rounded,
                                size: 14, color: theme.colorScheme.onSurface),
                            Text('${tier.capacity}',
                                style: theme.textTheme.labelMedium),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          eta == null
                              ? 'No cars nearby'
                              : '${_arrivalClock(eta)} · ${_minutes(eta)} min away',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        // Same rule as the confirm footer (Fmt.money), so the
                        // list and the button always agree.
                        Fmt.money(tier.fare, tier.currency),
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)
                            .tabular(),
                      ),
                      // What the number is made of — only when the backend
                      // itemised it; an empty "Details" is worse than none.
                      if (tier.breakdown != null)
                        GestureDetector(
                          onTap: () => showFareDetailsSheet(context, tier),
                          behavior: HitTestBehavior.opaque,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text('Details',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  decoration: TextDecoration.underline,
                                )),
                          ),
                        ),
                    ],
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
                  Text(Fmt.money(tier.fare, tier.currency),
                      style: theme.textTheme.titleMedium?.tabular()),
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
  late final TextEditingController _controller =
      TextEditingController(text: widget.state.pickupNote ?? '');

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
        prefixIcon: Icon(Icons.sticky_note_2_outlined),
        isDense: true,
        counterText: '',
      ),
      onChanged: (v) => context.read<TripCubit>().setPickupNote(v),
    );
  }
}
