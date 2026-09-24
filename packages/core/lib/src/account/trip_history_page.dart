import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../trip/payments_remote_data_source.dart';
import '../trip/trip_remote_data_source.dart';
import 'format.dart';
import 'receipt_page.dart';
import 'widgets/async_content.dart';

/// Past trips for the signed-in rider or driver (`GET /trips/history`).
/// Tapping a completed trip opens its [ReceiptPage].
class TripHistoryPage extends StatelessWidget {
  const TripHistoryPage({
    super.key,
    required this.trips,
    required this.payments,
    this.isDriver = false,
  });

  final TripRemoteDataSource trips;
  final PaymentsRemoteDataSource payments;
  final bool isDriver;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your trips')),
      body: AsyncContent<List<Trip>>(
        load: trips.history,
        isEmpty: (list) => list.isEmpty,
        emptyIcon: PhosphorIconsRegular.receipt,
        emptyTitle: 'No trips yet',
        emptyMessage: isDriver
            ? 'Trips you complete will show up here.'
            : 'Your ride history will appear here.',
        builder: (context, list, _) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) => _TripTile(
            trip: list[i],
            isDriver: isDriver,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReceiptPage(
                  payments: payments,
                  trip: list[i],
                  showPayout: isDriver,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TripTile extends StatelessWidget {
  const _TripTile({
    required this.trip,
    required this.isDriver,
    required this.onTap,
  });

  final Trip trip;
  final bool isDriver;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final completed = trip.status == TripStatus.completed;
    // A cancelled ride was never charged its estimate; only show an amount if
    // a final fare (cancellation fee) was actually settled.
    final fare = trip.status == TripStatus.cancelled
        ? trip.fareFinal
        : trip.fareDisplay;
    return ListTile(
      onTap: completed ? onTap : null,
      leading: AppIconBadge(
          icon: _statusIcon(trip.status), tone: _statusTone(trip.status)),
      title: Text(
        trip.dropoff.address ?? 'Destination',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        // A scheduled ride is remembered by when it was booked for, not by
        // the moment the rider tapped Schedule.
        '${Fmt.dateTime(trip.completedAt ?? trip.scheduledAt ?? trip.requestedAt)} · '
        '${Fmt.status(_snake(trip.status))}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (fare != null)
            Text(Fmt.money(fare, trip.currency),
                style: theme.textTheme.titleMedium),
          if (completed)
            Text('Receipt',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: AppColors.accent)),
        ],
      ),
    );
  }

  String _snake(TripStatus s) {
    switch (s) {
      case TripStatus.inProgress:
        return 'in_progress';
      case TripStatus.noDrivers:
        return 'no_drivers';
      case TripStatus.paymentFailed:
        return 'payment_failed';
      default:
        return s.name;
    }
  }

  IconData _statusIcon(TripStatus s) {
    switch (s) {
      case TripStatus.completed:
        return PhosphorIconsRegular.check;
      case TripStatus.cancelled:
      case TripStatus.expired:
      case TripStatus.noDrivers:
        return PhosphorIconsRegular.x;
      default:
        return PhosphorIconsRegular.car;
    }
  }

  AppIconBadgeTone _statusTone(TripStatus s) {
    switch (s) {
      case TripStatus.completed:
        return AppIconBadgeTone.success;
      case TripStatus.cancelled:
      case TripStatus.expired:
      case TripStatus.noDrivers:
      case TripStatus.paymentFailed:
        return AppIconBadgeTone.danger;
      default:
        return AppIconBadgeTone.warning;
    }
  }
}
