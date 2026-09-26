part of 'ride_sheets.dart';

/// The post-ride sheet: the receipt, the rating, and the tip flow.

/// A toggle to add/remove the just-completed trip's driver as a favourite.
class _FavoriteDriverButton extends StatefulWidget {
  const _FavoriteDriverButton({required this.driverId, this.driverName});
  final String driverId;
  final String? driverName;

  @override
  State<_FavoriteDriverButton> createState() => _FavoriteDriverButtonState();
}

class _FavoriteDriverButtonState extends State<_FavoriteDriverButton> {
  final _favorites = sl<FavoritesRemoteDataSource>();
  bool _favorited = false;
  bool _busy = false;

  Future<void> _toggle() async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final next = !_favorited;
    try {
      if (next) {
        await _favorites.add(widget.driverId);
      } else {
        await _favorites.remove(widget.driverId);
      }
      if (mounted) setState(() => _favorited = next);
      messenger.showSnackBar(
        _completionSnackBar(
          next
              ? 'Added ${widget.driverName ?? 'driver'} to favourites'
              : 'Removed from favourites',
        ),
      );
    } on ApiException catch (e) {
      messenger.showSnackBar(_completionSnackBar(e.message));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: _favorited
          ? const Icon(
              PhosphorIconsFill.heart,
              color: AppColors.error,
              size: 20,
            )
          // THEME=clay3d: one 3D heart for both states, so grey the off one.
          : AppClay3D.off(const Icon(PhosphorIconsRegular.heart, size: 20)),
      label: Text(_favorited ? 'Favourited' : 'Add to favourites'),
    );
  }
}

/// Snackbar for the trip-complete sheet: floats above the pinned Done button
/// instead of sliding up over it (a fixed snackbar sits flush with the
/// bottom edge, exactly where the CTA is).
SnackBar _completionSnackBar(String text) => SnackBar(
  content: Text(text),
  behavior: SnackBarBehavior.floating,
  margin: const EdgeInsets.fromLTRB(
    AppSpacing.lg,
    0,
    AppSpacing.lg,
    _kCompletionSnackBarLift,
  ),
);

/// The chosen tip's colour: the ink, or teal in THEME=ink, where teal is
/// kept for the selection.
Color get _chosen => InkPaper.on ? AppColors.highlight : AppColors.accent;

/// Bottom margin that clears the Done button (button + sheet padding).
const double _kCompletionSnackBarLift = 96;

/// The post-ride sheet: fare, rating, favourite-driver and the tip flow.
/// Public (like [DriverInfoSheet]) so it can be widget-tested on its own.
class CompletedSheet extends StatefulWidget {
  const CompletedSheet({super.key, required this.state});
  final TripState state;

  @override
  State<CompletedSheet> createState() => _CompletedSheetState();
}

class _CompletedSheetState extends State<CompletedSheet> {
  /// The amount the rider has picked but not yet confirmed. A tip can only be
  /// sent once (the backend rejects a second one with 409), so the choice has
  /// to stay changeable on this side of the send rather than firing on the
  /// first tap — which is what made a mis-tap permanent.
  double? _pendingTip;

  /// The draggable sheet this page sits in (null when it is built on its
  /// own, e.g. in a widget test).
  _SheetDrag? _drag;

  /// Owner (2026-09-25): at rest the page holds 75% of the screen and the
  /// tip and Done fit there without scrolling; the rest of the trip
  /// ([CompletedSheetExtras]) is only for a sheet pulled up past its rest
  /// size. Built on its own (no sheet around it) it shows everything.
  bool get _pulledUp => _drag == null || _drag!._dragHeight != null;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final theme = Theme.of(context);
    final cubit = context.read<TripCubit>();
    // Take the first source that actually states a fare. The receipt is the
    // richest, but a capture still settling (or a failed fetch on a weak
    // signal) can leave it at zero, and showing \$0.00 for a ride that just
    // happened reads as a broken app — or a free ride.
    final fare =
        [
          state.receipt?.fare,
          state.fareFinal,
          state.trip?.fareDisplay,
        ].firstWhere((v) => v != null && v > 0, orElse: () => null) ??
        0;
    final tip = state.tipAmount ?? state.receipt?.tip ?? 0;
    // A tip that has actually been charged. The backend puts `tip: 0` on the
    // receipt of every untipped ride, and taking that at face value locked the
    // whole tip section on arrival — chips greyed out, "Tip of \$0 added."
    // under them — so a rider who wanted to tip simply could not. Only an
    // amount greater than zero is a tip that was sent.
    final double? sentTip = [
      state.tipAmount,
      state.receipt?.tip,
    ].firstWhere((v) => v != null && v > 0, orElse: () => null);
    final double? chosenTip = sentTip ?? _pendingTip;
    final bool locked = sentTip != null || state.tipping;
    return SingleChildScrollView(
      // The confetti bursts 70px above the check; the default hard-edge clip
      // cut the top of the burst off at the sheet's first line.
      clipBehavior: Clip.none,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (LocalArt.on)
            // Plan D: the check pops on a marigold flower (still under
            // Reduce Motion).
            const Center(child: LocalDoneArt(size: 104))
          else
            // Confetti bursts once behind the check (not under Reduce Motion).
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                const Positioned(
                  top: -70,
                  child: LottieMoment.confetti(size: 220),
                ),
                Center(
                  child: _HeroIcon(
                    asset: 'done',
                    size: 56,
                    fallback: Container(
                      width: 64,
                      height: 64,
                      // THEME=ink: a hairline ring, not a tinted disc.
                      decoration: InkPaper.on
                          ? BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: InkPaper.outline(
                                  theme.brightness == Brightness.dark,
                                ),
                              ),
                            )
                          : BoxDecoration(
                              color: AppColors.accentSoft,
                              shape: BoxShape.circle,
                            ),
                      child: Icon(
                        PhosphorIconsRegular.check,
                        color: AppColors.accent,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(height: AppSpacing.md),
          // Announced as it appears: the ride's last change of moment.
          Center(
            child: Semantics(
              liveRegion: true,
              header: true,
              child: Text(
                RideStatus.of(state).title,
                // THEME=ink: the status headline is a serif moment.
                style: theme.textTheme.headlineSmall?.serifMoment(32),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          // One line — "Total ₹75" — with everything that makes it up folded
          // under it (audit 3.11). The total is said once, here.
          // THEME=ink: printed as a ticket (perforated top, dotted leaders,
          // the total in serif) instead of a card.
          if (InkPaper.on)
            TicketPaper(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.x20,
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: _TotalWithBreakdown(
                fare: fare,
                tip: tip,
                breakdown: state.fareBreakdown,
                currency: state.receipt?.currency,
              ),
            )
          else
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.sm,
              ),
              child: _TotalWithBreakdown(
                fare: fare,
                tip: tip,
                breakdown: state.fareBreakdown,
                currency: state.receipt?.currency,
              ),
            ),
          if ((state.receipt?.isCash ?? false) && LocalArt.on)
            // Plan D's signature: one amber strip says who to pay, and how.
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: PayDriverStrip(
                amount: Fmt.money(fare + tip, state.receipt?.currency),
                driverName: _payee(state),
              ),
            )
          else if (state.receipt?.isCash ?? false)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Row(
                children: [
                  // Banknotes flutter once beside the cash reminder.
                  const LottieMoment.money(size: 32),
                  const SizedBox(width: AppSpacing.xs),
                  // Wraps at large text sizes instead of running off the edge.
                  Expanded(
                    child: Text(
                      'Pay ${Fmt.money(fare + tip, state.receipt?.currency)} in cash to your driver',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.warningTextOf(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: InkPaper.on ? AppSpacing.xxxl : AppSpacing.md),
          // Rating
          Center(
            child: Text(
              'Rate your driver',
              style: inkSectionLabel(context, theme.textTheme.titleMedium),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          // Always tappable: the backend stores one rating per trip and
          // recomputes the driver's average from it, so tapping again is a
          // correction, not a second vote. A mis-tapped star used to be
          // permanent — unfair to the driver and frustrating for the rider.
          StarRating(value: state.rating ?? 0, onRate: cubit.rateDriver),
          if (state.rating != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // A star fills with a small sparkle — replayed when the
                    // rider changes the rating (keyed on it). Fixed 28px box.
                    LottieMoment.thanks(key: ValueKey(state.rating), size: 28),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        'Thanks for your feedback! Tap a star to change it.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Compliment tags — shown once a (positive) rating is given, so the
          // rider can say what went well (Uber-style). Persisted with the rating.
          if (state.rating != null && state.rating! >= 4) ...[
            const SizedBox(height: AppSpacing.md),
            _ComplimentTags(
              selected: state.ratingTags,
              onChanged: (tags) => cubit.updateRatingTags(tags),
            ),
          ],
          if (state.driver?.id != null) ...[
            const SizedBox(height: AppSpacing.md),
            _FavoriteDriverButton(
              driverId: state.driver!.id!,
              driverName: state.driver!.name,
            ),
          ],
          SizedBox(height: InkPaper.on ? AppSpacing.xxxl : AppSpacing.md),
          if (InkPaper.on) ...[
            const InkRule(),
            const SizedBox(height: AppSpacing.xl),
          ],
          // Tips
          Text(
            'Add a tip',
            style: inkSectionLabel(context, theme.textTheme.titleMedium),
          ),
          SizedBox(height: InkPaper.on ? AppSpacing.md : AppSpacing.sm),
          Row(
            children: [
              for (final amt in Market.current.tipPresets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: AppSpacing.sm),
                    child: _TipChip(
                      amount: amt,
                      selected: sentTip == null
                          ? _pendingTip == amt
                          : sentTip == amt,
                      // Locked only once the tip has actually been sent.
                      // Tapping the chosen amount again clears it: there was
                      // otherwise no way back to "no tip" once a chip had been
                      // touched, which is a dead end for a mis-tap.
                      onTap: locked
                          ? null
                          : () => setState(() {
                              _pendingTip = _pendingTip == amt ? null : amt;
                              cubit.selectedTip = _pendingTip;
                            }),
                    ),
                  ),
                ),
              // Custom amount — a rider isn't limited to the presets.
              Expanded(
                child: _CustomTipChip(
                  // Highlight when the chosen tip isn't one of the presets.
                  selected:
                      chosenTip != null &&
                      !Market.current.tipPresets.contains(chosenTip),
                  onTap: locked
                      ? null
                      : () async {
                          final amount = await _askCustomTip(context);
                          if (amount != null && mounted) {
                            setState(() {
                              _pendingTip = amount;
                              cubit.selectedTip = amount;
                            });
                          }
                        },
                ),
              ),
            ],
          ),
          // A tip that failed to send. Without this the button simply went
          // back to saying "Add \$5 tip" with no explanation, which reads as
          // the sheet being stuck — the rider has no way to tell a rejected
          // charge from a dead button. The choice stays live so they can retry.
          if (sentTip == null && state.error != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _SheetWarning(message: state.error!),
          ],
          if (sentTip != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Row(
                children: [
                  // The tip went through: a teal check with a small burst,
                  // played once and held (fixed 28px box).
                  const LottieMoment.success(size: 28),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Tip of ${Fmt.money(sentTip, state.receipt?.currency)} added.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            )
          else if (_pendingTip != null)
            // Selected = confirmed: no second "Add tip" button. It is charged
            // when the rider taps Done; tapping the amount again removes it.
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.sm),
              child: Text(
                state.tipping
                    ? 'Adding your tip…'
                    : '${Fmt.money(_pendingTip!, state.receipt?.currency)} tip will be added when you tap Done. Tap it again to remove.',
                style: theme.textTheme.bodySmall,
              ),
            ),
          // Pulled fully up: the trip, the ride back, receipt/help, posters.
          if (_pulledUp) CompletedSheetExtras(state: state),
          // Done is not here: it is pinned under the sheet
          // ([CompletedDoneButton], the sheet's footer) so it never scrolls
          // away behind the tip and rating sections.
        ],
      ),
    );
  }
}

/// The completed sheet's "Done": the sheet's pinned footer, always in reach
/// however tall the rating/tip sections grow.
class CompletedDoneButton extends StatelessWidget {
  const CompletedDoneButton({super.key});

  @override
  Widget build(BuildContext context) => PrimaryButton(
    label: 'Done',
    // Sends the selected tip (if any), then closes the ride.
    onPressed: () => context.read<TripCubit>().finishRide(),
  );
}

/// "Total ₹75" on one line; tap it for what it is made of — the itemised
/// fare (base / distance / time / booking fee / surge / promo) when the
/// backend recorded one, else the fare, plus the tip. The tip line is the
/// sheet's own (it tracks a just-added tip live), so the breakdown's tip is
/// not repeated.
class _TotalWithBreakdown extends StatefulWidget {
  const _TotalWithBreakdown({
    required this.fare,
    required this.tip,
    required this.breakdown,
    required this.currency,
  });
  final double fare;
  final double tip;
  final FareBreakdown? breakdown;
  final String? currency;

  @override
  State<_TotalWithBreakdown> createState() => _TotalWithBreakdownState();
}

class _TotalWithBreakdownState extends State<_TotalWithBreakdown> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final breakdown = widget.breakdown;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Row(
                children: [
                  Expanded(
                    child: InkPaper.on
                        // One string still ("Total ₹75"): a small-caps
                        // label and the amount in serif, on one baseline.
                        ? Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: 'Total ',
                                  style: inkSectionLabel(
                                    context,
                                    null,
                                  )?.copyWith(fontSize: 13),
                                ),
                                inkAmountSpan(
                                  Fmt.money(
                                    widget.fare + widget.tip,
                                    widget.currency,
                                  ),
                                  size: 44,
                                  color: theme.colorScheme.onSurface,
                                ),
                              ],
                            ),
                          )
                        : Text(
                            'Total ${Fmt.money(widget.fare + widget.tip, widget.currency)}',
                            style: theme.textTheme.titleMedium?.tabular(),
                          ),
                  ),
                  Text(
                    _open ? 'Hide' : 'Details',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: AppColors.accentText,
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    _open
                        ? PhosphorIconsRegular.caretUp
                        : PhosphorIconsRegular.caretDown,
                    size: 20,
                    color: AppColors.accentText,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_open) ...[
          if (InkPaper.on)
            const Padding(
              padding: EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.md,
                right: AppSpacing.sm,
              ),
              child: TearLine(),
            )
          else
            Divider(height: AppSpacing.md, color: theme.dividerColor),
          if (breakdown != null)
            FareBreakdownRows(
              breakdown: breakdown,
              currency: widget.currency ?? Market.current.currency,
              showTip: false,
              style: theme.textTheme.bodyMedium,
            )
          else
            _ReceiptRow(
              label: 'Fare',
              value: widget.fare,
              currency: widget.currency,
            ),
          if (widget.tip > 0)
            _ReceiptRow(
              label: 'Tip',
              value: widget.tip,
              currency: widget.currency,
            ),
          const SizedBox(height: AppSpacing.xs),
        ],
      ],
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  const _ReceiptRow({required this.label, required this.value, this.currency});
  final String label;
  final double value;

  /// The receipt's currency; the market's when the receipt has none yet.
  final String? currency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Same size as the itemised lines it sits among in the expander.
    final style = theme.textTheme.bodyMedium;
    // THEME=ink: a printed line with a dotted leader, like the fare lines.
    if (InkPaper.on) {
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: LeaderLine(
          label: label,
          value: Fmt.money(value, currency),
          style: style,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: style),
          Text(Fmt.money(value, currency), style: style?.tabular()),
        ],
      ),
    );
  }
}

class _TipChip extends StatelessWidget {
  const _TipChip({required this.amount, required this.selected, this.onTap});
  final double amount;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null || selected;
    return Semantics(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            // THEME=ink: outlined chips on the paper, teal once chosen.
            color: InkPaper.on
                ? Colors.transparent
                : selected
                ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            border: Border.all(
              color: selected
                  ? _chosen
                  : (InkPaper.on
                        ? InkPaper.outline(isDark)
                        : theme.dividerColor),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap == null
                ? null
                : () {
                    AppHaptics.selection();
                    onTap!();
                  },
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              // Scales down rather than clipping at large text sizes; the
              // chosen amount carries a check, so it is never colour alone.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _ChipLabel(
                  text: Money.format(amount, wholeOnly: true),
                  selected: selected,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: selected
                        ? _chosen
                        : (enabled ? theme.colorScheme.onSurface : null),
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

/// A tip amount (or "Custom") with a check in front once it is the chosen
/// one — so the selection reads without relying on the accent colour.
class _ChipLabel extends StatelessWidget {
  const _ChipLabel({
    required this.text,
    required this.selected,
    required this.style,
  });
  final String text;
  final bool selected;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected) ...[
          Icon(PhosphorIconsRegular.check, size: 16, color: _chosen),
          const SizedBox(width: 4),
        ],
        Text(text, maxLines: 1, style: style),
      ],
    );
  }
}

/// A tip chip that lets the rider enter any amount, styled like [_TipChip].
class _CustomTipChip extends StatelessWidget {
  const _CustomTipChip({required this.selected, this.onTap});
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final enabled = onTap != null || selected;
    return Semantics(
      selected: selected,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            // THEME=ink: outlined chips on the paper, teal once chosen.
            color: InkPaper.on
                ? Colors.transparent
                : selected
                ? (isDark ? AppColors.accentSoftDark : AppColors.accentSoft)
                : theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            border: Border.all(
              color: selected
                  ? _chosen
                  : (InkPaper.on
                        ? InkPaper.outline(isDark)
                        : theme.dividerColor),
              width: selected ? 1.6 : 1,
            ),
          ),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppSpacing.radius),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: _ChipLabel(
                  text: 'Custom',
                  selected: selected,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: selected
                        ? _chosen
                        : (enabled ? theme.colorScheme.onSurface : null),
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

/// Prompt for a custom tip amount and submit it.
/// Ask for a custom tip amount. Returns the amount, or null if the rider
/// backed out — sending it is the caller's job, so the choice stays
/// changeable until they confirm.
Future<double?> _askCustomTip(BuildContext context) async {
  final controller = TextEditingController();
  final amount = await showDialog<double>(
    context: context,
    builder: (dialogCtx) {
      String? error;
      return StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add a tip'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
            ],
            decoration: InputDecoration(
              prefixText: '${Money.symbol()} ',
              hintText: '0.00',
              errorText: error,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final v = double.tryParse(controller.text.trim());
                if (v == null || v <= 0) {
                  setLocal(() => error = 'Enter an amount');
                  return;
                }
                if (v > Market.current.maxTip) {
                  setLocal(
                    () => error =
                        'Max ${Money.format(Market.current.maxTip, wholeOnly: true)}',
                  );
                  return;
                }
                Navigator.pop(dialogCtx, v);
              },
              child: const Text('Use amount'),
            ),
          ],
        ),
      );
    },
  );
  return amount;
}

/// Compliment chips shown after a positive rating (Uber-style). Multi-select;
/// every change re-submits the tag set with the existing star rating.
class _ComplimentTags extends StatefulWidget {
  const _ComplimentTags({required this.selected, required this.onChanged});
  final List<String> selected;
  final ValueChanged<List<String>> onChanged;

  static const List<String> options = [
    'Great conversation',
    'Clean car',
    'Safe driving',
    'Great navigation',
    'On time',
    'Cool music',
  ];

  @override
  State<_ComplimentTags> createState() => _ComplimentTagsState();
}

class _ComplimentTagsState extends State<_ComplimentTags> {
  late final Set<String> _selected = {...widget.selected};

  void _toggle(String tag) {
    setState(() {
      if (!_selected.add(tag)) _selected.remove(tag);
    });
    AppHaptics.selection();
    widget.onChanged(_selected.toList());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What went well?',
          style: inkSectionLabel(context, theme.textTheme.titleSmall),
        ),
        const SizedBox(height: AppSpacing.sm),
        // One left-aligned wrap: a centred wrap left the last, shorter row
        // centred under rows that read as left-aligned.
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          alignment: WrapAlignment.start,
          children: [
            for (final tag in _ComplimentTags.options)
              FilterChip(
                label: Text(tag),
                selected: _selected.contains(tag),
                onSelected: (_) => _toggle(tag),
                // The check says "chosen" without relying on the tint.
                showCheckmark: true,
                selectedColor: AppColors.accentSoft,
                side: BorderSide(
                  color: _selected.contains(tag)
                      ? AppColors.accent
                      : theme.dividerColor,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// --- Below the fold: what the sheet carries when pulled all the way up ------
//
// Owner (2026-09-25): a sheet dragged fully up "should look fully complete".
// At rest (75%) the sheet is the receipt, the rating and the tip; everything
// below the tip is the rest of the trip: its route and car, the ride back,
// the receipt and help, and the posters. Only real data — a line with no
// source (no distance on the trip, no driver) is left out, never filled in.

/// "economy" → "Economy", "xl" → "XL"; the estimate's own label when held.
String _completedTierLabel(TripState state) {
  final tier = (state.trip?.tier ?? state.selectedTier ?? '').trim();
  for (final t in state.estimate?.tiers ?? const <FareTier>[]) {
    if (t.tier == tier) return t.label;
  }
  if (tier.isEmpty) return 'Ride';
  if (tier.length <= 2) return tier.toUpperCase();
  return tier[0].toUpperCase() + tier.substring(1).replaceAll('_', ' ');
}

/// The trip's stops for a [RouteTimeline]: pickup, any stops, drop-off.
/// Null when either end has no address to show.
List<RouteTimelineStop>? _routeStops(TripState state) {
  final trip = state.trip;
  final from = state.pickupAddr ?? trip?.pickup.address;
  final to = state.dropoffAddr ?? trip?.dropoff.address;
  if (from == null || from.trim().isEmpty || to == null || to.trim().isEmpty) {
    return null;
  }
  final stops = trip?.stops.isNotEmpty == true ? trip!.stops : state.stops;
  return [
    RouteTimelineStop(label: 'Pickup', address: from),
    for (var i = 0; i < stops.length; i++)
      if (stops[i].address case final a? when a.trim().isNotEmpty)
        RouteTimelineStop(label: 'Stop ${i + 1}', address: a),
    RouteTimelineStop(label: 'Drop-off', address: to),
  ];
}

/// Opens the existing pre-book flow from [pickup] to [dropoff] (either may
/// be null: the page then asks for it), and confirms a booking with the same
/// snackbar as every other pre-book entry point.
Future<void> _preBookTrip(
  BuildContext context,
  TripState state, {
  GeoPoint? pickup,
  String? pickupAddr,
  GeoPoint? dropoff,
  String? dropoffAddr,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final booked = await Navigator.of(context).push<Trip>(
    MaterialPageRoute(
      builder: (_) => PreBookPage(
        repository: sl<TripRepository>(),
        pickup: pickup,
        pickupAddr: pickupAddr,
        initialDropoff: dropoff,
        initialDropoffAddr: dropoffAddr,
        paymentMode: state.trip?.paymentMode ?? state.paymentMode,
        payments: sl.isRegistered<PaymentsRemoteDataSource>()
            ? sl<PaymentsRemoteDataSource>()
            : null,
      ),
    ),
  );
  if (booked == null) return;
  final when = booked.scheduledAt;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      _completionSnackBar(
        when == null
            ? 'Ride scheduled. Find it in Account › Scheduled rides.'
            : 'Ride scheduled for ${_formatSchedule(when)}. '
                  'Find it in Account › Scheduled rides.',
      ),
    );
}

/// Everything under the tip section of [CompletedSheet].
class CompletedSheetExtras extends StatelessWidget {
  const CompletedSheetExtras({super.key, required this.state});

  final TripState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = state.trip;
    final route = _routeStops(state);
    final from = trip?.pickup.point ?? state.pickup;
    final fromAddr = state.pickupAddr ?? trip?.pickup.address;
    final to = trip?.dropoff.point ?? state.dropoff;
    final toAddr = state.dropoffAddr ?? trip?.dropoff.address;
    final canPreBook = sl.isRegistered<TripRepository>();
    final canReceipt =
        trip != null && sl.isRegistered<PaymentsRemoteDataSource>();
    final canHelp = sl.isRegistered<SupportRemoteDataSource>();
    final posters =
        homePosters(
              onOffers: () => RiderTabScaffold.goTo(context, RiderTab.offers),
              onSchedule: () =>
                  _preBookTrip(context, state, pickup: to, pickupAddr: toAddr),
              onSafety: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => EmergencyContactsPage(
                    safety: sl<SafetyRemoteDataSource>(),
                  ),
                ),
              ),
              onRide: () {},
            )
            // Sharing a live trip is for a ride under way, not one just ended;
            // emergency contacts need the safety API registered.
            .where(
              (p) =>
                  p.id != 'poster-share' &&
                  (p.id != 'poster-safety' ||
                      sl.isRegistered<SafetyRemoteDataSource>()),
            )
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.xl),
        // --- The trip -------------------------------------------------------
        Text(
          'Your trip',
          style: inkSectionLabel(context, theme.textTheme.titleMedium),
        ),
        const SizedBox(height: AppSpacing.sm),
        _CompletedTripCard(state: state, route: route),

        // --- Where next -----------------------------------------------------
        if (canPreBook && (to != null || from != null)) ...[
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Where next?',
            style: inkSectionLabel(context, theme.textTheme.titleMedium),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (to != null)
            _NextActionTile(
              icon: PhosphorIconsRegular.arrowsLeftRight,
              title: 'Plan your return',
              subtitle: fromAddr == null
                  ? 'Pre-book a pickup from here'
                  : 'Pre-book a ride back to $fromAddr',
              onTap: () => _preBookTrip(
                context,
                state,
                pickup: to,
                pickupAddr: toAddr,
                dropoff: from,
                dropoffAddr: fromAddr,
              ),
            ),
          if (from != null && to != null) ...[
            const SizedBox(height: AppSpacing.sm),
            _NextActionTile(
              icon: PhosphorIconsRegular.arrowClockwise,
              title: 'Book this trip again',
              subtitle: 'Same pickup and drop-off, at a time you choose',
              onTap: () => _preBookTrip(
                context,
                state,
                pickup: from,
                pickupAddr: fromAddr,
                dropoff: to,
                dropoffAddr: toAddr,
              ),
            ),
          ],
        ],

        // --- Receipt / help -------------------------------------------------
        if (canReceipt || canHelp) ...[
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              if (canReceipt)
                Expanded(
                  child: SecondaryButton(
                    label: 'Receipt',
                    icon: PhosphorIconsRegular.receipt,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ReceiptPage(
                          payments: sl<PaymentsRemoteDataSource>(),
                          trip: trip,
                        ),
                      ),
                    ),
                  ),
                ),
              if (canReceipt && canHelp) const SizedBox(width: AppSpacing.sm),
              if (canHelp)
                Expanded(
                  child: SecondaryButton(
                    label: 'Get help',
                    icon: PhosphorIconsRegular.question,
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            SupportPage(support: sl<SupportRemoteDataSource>()),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],

        // --- Posters --------------------------------------------------------
        if (posters.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.xl),
          // The posters are fixed-height art: cap their type so a large
          // Dynamic Type setting cannot push the copy out of the card.
          MediaQuery.withClampedTextScaling(
            maxScaleFactor: 1.5,
            child: PromoCarousel(posters, padding: EdgeInsets.zero),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }
}

/// The finished trip at a glance: the car it was in, who drove, the route,
/// and the distance and time the trip record carries.
class _CompletedTripCard extends StatelessWidget {
  const _CompletedTripCard({required this.state, required this.route});

  final TripState state;
  final List<RouteTimelineStop>? route;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = state.trip;
    final driver = state.driver;
    final tier = trip?.tier ?? state.selectedTier;
    final vehicle =
        RideDetailsContent.vehicleLine(driver) ?? trip?.driverVehicleLabel;
    final driverName = driver?.name ?? trip?.driverName;
    final plate = driver?.plate ?? trip?.driverPlate;
    final distanceM = trip?.distanceM;
    final durationS = trip?.durationS;
    final muted = theme.brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              VehicleGlyph(tier: tier ?? 'comfort', width: 76),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _completedTierLabel(state),
                      style: theme.textTheme.titleMedium,
                    ),
                    if (driverName != null && driverName.trim().isNotEmpty)
                      Text(
                        'with $driverName'
                        '${driver != null ? ' · ★ ${driver.rating.toStringAsFixed(1)}' : ''}',
                        style: theme.textTheme.bodyMedium,
                      ),
                    if (vehicle != null || (plate?.trim().isNotEmpty ?? false))
                      Text(
                        [
                          ?vehicle,
                          if (plate != null && plate.trim().isNotEmpty)
                            Market.current.formatPlate(plate),
                        ].join(' · '),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: muted,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (distanceM != null || durationS != null) ...[
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                if (distanceM != null)
                  _TripStatPill(
                    icon: PhosphorIconsRegular.ruler,
                    text: Fmt.distance(distanceM),
                  ),
                if (durationS != null)
                  _TripStatPill(
                    icon: PhosphorIconsRegular.clock,
                    text: Fmt.duration(durationS),
                  ),
                _TripStatPill(
                  icon: (trip?.paymentMode ?? state.paymentMode) == 'cash'
                      ? PhosphorIconsRegular.money
                      : PhosphorIconsRegular.creditCard,
                  text: (trip?.paymentMode ?? state.paymentMode) == 'cash'
                      ? 'Cash'
                      : (state.receipt?.cardLabel ?? 'Card'),
                ),
              ],
            ),
          ],
          if (route != null) ...[
            Divider(height: AppSpacing.xl, color: theme.dividerColor),
            RouteTimeline(stops: route!),
          ],
        ],
      ),
    );
  }
}

class _TripStatPill extends StatelessWidget {
  const _TripStatPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.iconNeutralFor(dark)),
          const SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(text, style: theme.textTheme.labelLarge?.tabular()),
          ),
        ],
      ),
    );
  }
}

/// A tappable "what next" row: icon, title, one line of context, chevron.
class _NextActionTile extends StatelessWidget {
  const _NextActionTile({
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
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: dark ? AppColors.accentSoftDark : AppColors.accentSoft,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 20, color: AppColors.accentText),
          ),
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
          Icon(
            PhosphorIconsRegular.caretRight,
            size: 20,
            color: AppColors.iconNeutralFor(dark),
          ),
        ],
      ),
    );
  }
}
