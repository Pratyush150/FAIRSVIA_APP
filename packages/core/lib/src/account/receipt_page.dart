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
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(Fmt.dateTime(trip.completedAt ?? trip.requestedAt),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        _Trip(trip: trip),
        const SizedBox(height: AppSpacing.lg),
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
        const Divider(height: AppSpacing.xl),
        _row(context, 'Total', Fmt.money(r.total, r.currency), bold: true),
        if (r.isCash || r.cardLabel != null)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.xs),
            child: Row(
              children: [
                Icon(
                  r.isCash ? Icons.payments_outlined : Icons.credit_card,
                  size: 16,
                  color: AppColors.textSecondaryLight,
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
            child: Chip(label: Text('Payment: ${Fmt.status(r.status!)}')),
          ),
      ],
    );
  }

  Widget _row(BuildContext context, String label, String value,
      {bool bold = false}) {
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

/// The itemised lines of a [FareBreakdown]: Base fare, Distance, Time,
/// Booking fee, then Surge (only when > 1×), Promo (−, only when > 0) and Tip
/// (only when > 0 and [showTip]). Shared by the receipt page and the rider's
/// trip-complete sheet so both read the same way.
class FareBreakdownRows extends StatelessWidget {
  const FareBreakdownRows({
    super.key,
    required this.breakdown,
    this.currency = 'USD',
    this.showTip = true,
    this.style,
  });

  final FareBreakdown breakdown;
  final String currency;

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
        _line('Base fare', Fmt.money(b.baseFare, currency), textStyle),
        _line('Distance', Fmt.money(b.distanceFare, currency), textStyle),
        _line('Time', Fmt.money(b.timeFare, currency), textStyle),
        _line('Booking fee', Fmt.money(b.bookingFee, currency), textStyle),
        if (b.hasMinimumFare)
          _line('Minimum fare', Fmt.money(b.minimumFareAdjustment, currency),
              textStyle),
        if (b.hasSurge) _line('Surge', Fmt.surge(b.surgeMultiplier), textStyle),
        if (b.hasPromo)
          _line('Promo', '−${Fmt.money(b.promoDiscount, currency)}', textStyle),
        if (showTip && b.hasTip) _line('Tip', Fmt.money(b.tip, currency), textStyle),
      ],
    );
  }

  Widget _line(String label, String value, TextStyle? style) => Padding(
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

class _Trip extends StatelessWidget {
  const _Trip({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _point(theme, Icons.trip_origin, trip.pickup.address ?? 'Pickup'),
        const SizedBox(height: AppSpacing.xs),
        _point(theme, Icons.location_on, trip.dropoff.address ?? 'Destination'),
      ],
    );
  }

  Widget _point(ThemeData theme, IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: AppColors.accent),
        const SizedBox(width: AppSpacing.sm),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium)),
      ],
    );
  }
}
