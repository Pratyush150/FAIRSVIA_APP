import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../trip/payments_remote_data_source.dart';
import 'format.dart';
import 'widgets/async_content.dart';

/// Standalone receipt for a single trip (`GET /payments/:id/receipt`).
/// Opened from trip history. Shows the fare breakdown and, for drivers, the
/// payout split.
class ReceiptPage extends StatelessWidget {
  const ReceiptPage({
    super.key,
    required this.payments,
    required this.trip,
    this.showPayout = false,
  });

  final PaymentsRemoteDataSource payments;
  final Trip trip;

  /// Driver view shows platform fee + payout; rider view hides them.
  final bool showPayout;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Receipt')),
      body: AsyncContent<Receipt>(
        load: () => payments.receipt(trip.id),
        builder: (context, r, _) => _body(context, r),
      ),
    );
  }

  Widget _body(BuildContext context, Receipt r) {
    final theme = Theme.of(context);
    final children = <Widget>[
        _ReceiptHeader(trip: trip, showPayout: showPayout),
        Divider(height: AppSpacing.xl, color: theme.dividerColor),
        // Itemised lines first (when the backend recorded them), then the
        // authoritative fare — a clamp/minimum can move it off the sum.
        if (r.breakdown != null) ...[
          FareBreakdownRows(
            breakdown: r.breakdown!,
            currency: r.currency,
            showTip: false,
            style: theme.textTheme.bodyMedium,
          ),
          Divider(height: AppSpacing.md, color: theme.dividerColor),
        ],
        _row(context, 'Fare', Fmt.money(r.chargedAmount ?? r.fare, r.currency)),
        if (r.tip > 0) _row(context, 'Tip', Fmt.money(r.tip, r.currency)),
        // Refund sits above the divider so "Total" is what was actually paid.
        if (r.isRefunded)
          _row(
            context,
            'Refunded',
            '- ${Fmt.money(r.refundedAmount, r.currency)}',
          ),
        if (InkPaper.on)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
            child: TearLine(),
          )
        else
          const Divider(height: AppSpacing.xl),
        _row(context, 'Total', Fmt.money(r.total, r.currency), bold: true),
        if (r.isCash || r.cardLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  r.isCash ? PhosphorIconsRegular.money : PhosphorIconsRegular.creditCard,
                  size: 16,
                  color: AppColors.iconNeutralFor(
                      theme.brightness == Brightness.dark),
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  r.isCash ? 'Paid in cash' : 'Paid with ${r.cardLabel}',
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        if (showPayout && r.driverPayout != null) ...[
          const SizedBox(height: AppSpacing.lg),
          Text('Payout', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.sm),
          if (r.platformFee != null)
            _row(context, 'Platform fee',
                '- ${Fmt.money(r.platformFee!, r.currency)}'),
          _row(context, 'You earn', Fmt.money(r.driverPayout!, r.currency),
              bold: true),
        ],
        const SizedBox(height: AppSpacing.lg),
        if (r.status != null)
          Align(
            alignment: Alignment.centerLeft,
            child: AppStatusChip(
              label: 'Payment ${Fmt.status(r.status!).toLowerCase()}',
              // Success green text on its tint is under 4.5:1; only a
              // failure earns colour.
              tone: r.status == 'failed'
                  ? StatusTone.warning
                  : StatusTone.neutral,
            ),
          ),
    ];
    // THEME=ink (Plan E): the receipt is printed on a paper ticket.
    if (InkPaper.on) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.xl, AppSpacing.lg, AppSpacing.lg),
        children: [
          TicketPaper(
            // White on the paper page (the sheet version is paper on white).
            fill: theme.colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: children,
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false}) {
    if (InkPaper.on) return _inkRow(context, label, value, bold: bold);
    final style = bold
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyLarge;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [Text(label, style: style), Text(value, style: style)],
      ),
    );
  }
}

/// THEME=ink (Plan E): receipt lines with dotted leaders; the bold row (the
/// total, the payout) as a small-caps label and a serif amount.
Widget _inkRow(BuildContext context, String label, String value,
    {bool bold = false}) {
  final theme = Theme.of(context);
  if (!bold) {
    return LeaderLine(
        label: label, value: value, style: theme.textTheme.bodyLarge);
  }
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Expanded(
            child: Text(label, style: inkSectionLabel(context, null)
                ?.copyWith(fontSize: 13))),
        Text.rich(inkAmountSpan(value,
            size: 44, color: theme.colorScheme.onSurface)),
      ],
    ),
  );
}

/// The itemised lines of a [FareBreakdown]: Base fare, Distance, Time,
/// Booking fee, then Surge (only when > 1×), Promo (−, only when > 0) and Tip
/// (only when > 0 and [showTip]). Base fare, Time and Booking fee are left out
/// when they are zero — a metered auto or bike fare is distance only, and
/// three "₹0" lines above it would only be noise. Shared by the receipt page and the rider's
/// trip-complete sheet so both read the same way.
class FareBreakdownRows extends StatelessWidget {
  const FareBreakdownRows({
    super.key,
    required this.breakdown,
    this.currency,
    this.showTip = true,
    this.style,
  });

  final FareBreakdown breakdown;

  /// The trip's currency; the build's market currency when unknown.
  final String? currency;

  /// Off when the caller already renders a tip line of its own.
  final bool showTip;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final b = breakdown;
    final textStyle = style ?? Theme.of(context).textTheme.bodyMedium;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (b.baseFare != 0)
          _line('Base fare', Fmt.money(b.baseFare, currency), textStyle),
        _line('Distance', Fmt.money(b.distanceFare, currency), textStyle),
        if (b.timeFare != 0)
          _line('Time', Fmt.money(b.timeFare, currency), textStyle),
        if (b.bookingFee != 0)
          _line('Booking fee', Fmt.money(b.bookingFee, currency), textStyle),
        if (b.hasMinimumFare)
          _line('Minimum fare', Fmt.money(b.minimumFareAdjustment, currency),
              textStyle),
        // The quote bounded the metered fare (lifted to 0.8x or capped at
        // 1.5x of it) — never labelled a "minimum fare".
        if (b.hasFareAdjustment)
          _line(
              b.fareAdjustment > 0
                  ? 'Up-front price adjustment'
                  : 'Capped at up-front price',
              b.fareAdjustment > 0
                  ? Fmt.money(b.fareAdjustment, currency)
                  : '−${Fmt.money(-b.fareAdjustment, currency)}',
              textStyle),
        if (b.hasSurge) _line('Surge', Fmt.surge(b.surgeMultiplier), textStyle),
        if (b.hasPromo)
          _line('Promo', '−${Fmt.money(b.promoDiscount, currency)}', textStyle),
        if (showTip && b.hasTip) _line('Tip', Fmt.money(b.tip, currency), textStyle),
        if (b.basisNote != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Text(b.basisNote!,
                style: Theme.of(context).textTheme.bodySmall),
          ),
      ],
    );
  }

  Widget _line(String label, String value, TextStyle? style) => InkPaper.on
      // THEME=ink: a printed receipt line with a dotted leader.
      ? LeaderLine(label: label, value: value, style: style)
      : Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: style),
            Text(value, style: style?.tabular()),
          ],
        ),
      );
}

/// The top of the receipt: the day and time, the route as two dots joined by
/// a line (pickup hollow, destination filled), and who drove in which car.
class _ReceiptHeader extends StatelessWidget {
  const _ReceiptHeader({required this.trip, required this.showPayout});
  final Trip trip;

  /// The driver's own receipt names the rider instead of the driver.
  final bool showPayout;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = dark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final ink = theme.colorScheme.onSurface;
    final when = trip.completedAt ?? trip.scheduledAt ?? trip.requestedAt;
    String? first(String? n) {
      final t = n?.trim();
      return (t == null || t.isEmpty) ? null : t.split(RegExp(r'\s+')).first;
    }

    final who = showPayout
        ? first(trip.passenger?.name ?? trip.riderName)
        : first(trip.driverName);
    final people = [
      if (who != null) 'with $who',
      if (!showPayout && trip.driverVehicleLabel != null)
        trip.driverVehicleLabel!,
      if (!showPayout && trip.driverPlate != null)
        Market.current.formatPlate(trip.driverPlate!),
    ].join(' · ');
    final meta = [
      if (trip.distanceM != null && trip.distanceM! > 0)
        Fmt.distance(trip.distanceM!),
      if (trip.durationS != null && trip.durationS! > 0)
        Fmt.duration(trip.durationS!),
    ].join(' · ');

    Widget stop(String text, {required bool end}) => Text(
          text,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: end ? FontWeight.w600 : FontWeight.w400,
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                when == null
                    ? 'Trip'
                    : '${Fmt.dayLabel(when)} · ${Fmt.time(when)}',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            ExcludeSemantics(child: VehicleGlyph(tier: trip.tier, width: 64)),
          ],
        ),
        if (meta.isNotEmpty)
          Text(meta,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        const SizedBox(height: AppSpacing.md),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 16,
                child: Column(
                  children: [
                    const SizedBox(height: 6),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: ink, width: 2),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        width: 2,
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        color: muted.withValues(alpha: 0.4),
                      ),
                    ),
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: ink,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      label: 'From',
                      child: stop(trip.pickup.address ?? 'Pickup', end: false),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Semantics(
                      label: 'To',
                      child: stop(trip.dropoff.address ?? 'Destination',
                          end: true),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        if (people.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          Text(people,
              style: theme.textTheme.bodyMedium?.copyWith(color: muted)),
        ],
      ],
    );
  }
}
