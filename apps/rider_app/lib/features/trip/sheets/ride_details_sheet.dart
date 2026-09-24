part of 'ride_sheets.dart';

/// "Details" for the ride that is actually happening — the fare, the car and
/// where it is going, reachable at every point of the ride.

/// "Details" for the ride that is actually happening: what it costs, which car
/// is coming, and where it is going. Before this, the fare was visible only on
/// the tier picker and after arrival — a rider mid-ride had no way to check the
/// number they had agreed to, and the car's plate was only on the pickup sheet.
Future<void> showRideDetailsSheet(BuildContext context, TripState state) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetCtx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.lg),
        child: RideDetailsContent(state: state),
      ),
    ),
  );
}

/// Body of the live-ride details sheet (its own widget so it can be tested
/// without driving a whole booking flow).
class RideDetailsContent extends StatelessWidget {
  const RideDetailsContent({super.key, required this.state});

  final TripState state;

  /// Shown in place of an amount when no source has priced the ride yet.
  static const String unknownFare = 'Not priced yet';

  /// "White Toyota Camry", skipping whatever the payload didn't carry.
  static String? vehicleLine(AssignedDriver? driver) {
    if (driver == null) return null;
    final parts = [driver.vehicleColor, driver.vehicleMake, driver.vehicleModel]
        .whereType<String>()
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    return parts.isEmpty ? null : parts.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trip = state.trip;
    final driver = state.driver;
    final fare = state.displayFare;
    final breakdown = state.fareBreakdown;
    final distanceM = trip?.distanceM ?? state.estimate?.distanceM;
    final surge = state.estimate?.surge ?? 1.0;
    final paymentMode = trip?.paymentMode ?? state.paymentMode;
    final vehicle = vehicleLine(driver);

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Ride details', style: theme.textTheme.titleLarge),
          const SizedBox(height: AppSpacing.lg),

          // --- Fare -------------------------------------------------------
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      state.fareIsFinal ? 'Total fare' : 'Estimated fare',
                      style: theme.textTheme.titleMedium,
                    ),
                    Text(
                      fare == null
                          ? unknownFare
                          : Fmt.money(fare, trip?.currency),
                      style: theme.textTheme.titleMedium?.tabular(),
                    ),
                  ],
                ),
                if (!state.fareIsFinal) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'The final fare is metered on the distance actually '
                      'driven.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
                if (breakdown != null) ...[
                  Divider(height: AppSpacing.lg, color: theme.dividerColor),
                  FareBreakdownRows(
                    breakdown: breakdown,
                    currency: state.receipt?.currency ?? trip?.currency ?? Market.current.currency,
                    showTip: false,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),

          // --- Car + driver -----------------------------------------------
          if (driver != null) ...[
            const SizedBox(height: AppSpacing.md),
            AppCard(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: AppSpacing.md,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      AppAvatar(name: driver.name, size: 44),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(driver.name,
                                style: theme.textTheme.titleMedium),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(PhosphorIconsFill.star,
                                    size: 16, color: AppColors.star),
                                const SizedBox(width: 3),
                                Text(driver.rating.toStringAsFixed(1),
                                    style: theme.textTheme.labelLarge),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (vehicle != null)
                    _RideDetailRow(
                      icon: PhosphorIconsRegular.car,
                      label: 'Vehicle',
                      value: vehicle,
                    ),
                  if (driver.plate case final plate?
                      when plate.trim().isNotEmpty)
                    _RideDetailRow(
                      icon: PhosphorIconsRegular.ticket,
                      label: 'Plate',
                      value: plate,
                      spokenValue: AppA11y.spell(plate),
                    ),
                ],
              ),
            ),
          ],

          // --- Route + payment ---------------------------------------------
          const SizedBox(height: AppSpacing.md),
          AppCard(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            child: Column(
              children: [
                _RideDetailRow(
                  icon: PhosphorIconsRegular.record,
                  label: 'Pickup',
                  // After a cold start mid-ride the cubit's own addresses may
                  // not be populated; the trip row always has them.
                  value: state.pickupAddr ?? trip?.pickup.address ?? '—',
                ),
                _RideDetailRow(
                  icon: PhosphorIconsRegular.mapPin,
                  label: 'Dropoff',
                  value: state.dropoffAddr ?? trip?.dropoff.address ?? '—',
                ),
                if (distanceM != null)
                  _RideDetailRow(
                    icon: PhosphorIconsRegular.ruler,
                    label: 'Distance',
                    value: Fmt.distance(distanceM),
                  ),
                if (_tripEtaLine(state) case final eta?)
                  _RideDetailRow(
                    icon: PhosphorIconsRegular.clock,
                    label: 'Arrival',
                    value: eta,
                  ),
                _RideDetailRow(
                  icon: paymentMode == 'cash'
                      ? PhosphorIconsRegular.money
                      : PhosphorIconsRegular.creditCard,
                  label: 'Payment',
                  value: paymentMode == 'cash'
                      ? 'Cash to your driver'
                      : (state.receipt?.cardLabel ?? 'Card'),
                ),
                if (surge > 1.0)
                  _RideDetailRow(
                    icon: PhosphorIconsRegular.trendUp,
                    label: 'Surge',
                    value: Fmt.surge(surge),
                  ),
                if (trip?.promoCode case final code? when code.isNotEmpty)
                  _RideDetailRow(
                    icon: PhosphorIconsRegular.tag,
                    label: 'Promo',
                    value: code,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RideDetailRow extends StatelessWidget {
  const _RideDetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.spokenValue,
  });

  final IconData icon;
  final String label;
  final String value;

  /// What a screen reader says for [value] when it differs (a plate, spelled
  /// out character by character).
  final String? spokenValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Label glyphs, not meaning: neutral, 20 px (audit 2.1 rules 2/4).
          Icon(icon,
              size: 20,
              color: AppColors.iconNeutralFor(
                  theme.brightness == Brightness.dark)),
          const SizedBox(width: AppSpacing.sm),
          Text(label, style: theme.textTheme.bodyMedium),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    final spoken = spokenValue;
    if (spoken == null) return row;
    return Semantics(
      label: '$label: $spoken',
      excludeSemantics: true,
      child: row,
    );
  }
}

/// The "Details" affordance carried by the live-ride sheets.
class RideDetailsButton extends StatelessWidget {
  const RideDetailsButton({super.key, required this.state});

  final TripState state;

  @override
  Widget build(BuildContext context) {
    return SecondaryButton(
      label: 'Details',
      icon: PhosphorIconsRegular.receipt,
      onPressed: () => showRideDetailsSheet(context, state),
    );
  }
}
