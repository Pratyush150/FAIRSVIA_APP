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
    final total = r.fare + r.tip;
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Text(Fmt.dateTime(trip.completedAt ?? trip.requestedAt),
            style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.xs),
        _Trip(trip: trip),
        const SizedBox(height: AppSpacing.lg),
        _row(context, 'Fare', Fmt.money(r.fare, r.currency)),
        if (r.tip > 0) _row(context, 'Tip', Fmt.money(r.tip, r.currency)),
        const Divider(height: AppSpacing.xl),
        _row(context, 'Total', Fmt.money(total, r.currency), bold: true),
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
