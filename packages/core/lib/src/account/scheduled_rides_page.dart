import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

import '../network/api_exception.dart';
import '../trip/trip_remote_data_source.dart';
import 'format.dart';
import 'widgets/async_content.dart';

/// The rider's upcoming scheduled rides (`GET /trips/scheduled`). Each can be
/// cancelled before its time; the list reloads after a cancellation.
class ScheduledRidesPage extends StatefulWidget {
  const ScheduledRidesPage({super.key, required this.trips});

  final TripRemoteDataSource trips;

  @override
  State<ScheduledRidesPage> createState() => _ScheduledRidesPageState();
}

class _ScheduledRidesPageState extends State<ScheduledRidesPage> {
  // Bump to force AsyncContent to reload after a cancellation.
  int _reloadKey = 0;

  // In-flight guard: a second tap while the POST is pending is ignored.
  bool _cancelling = false;

  Future<void> _cancel(Trip trip) async {
    if (_cancelling) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this scheduled ride?'),
        content: Text(
          trip.scheduledAt != null
              ? 'Your ride on ${Fmt.dateTime(trip.scheduledAt!)} will be '
                  'removed from your schedule.'
              : 'This ride will be removed from your schedule.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep ride'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel ride'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted || _cancelling) return;
    setState(() => _cancelling = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.trips.cancel(trip.id, reason: 'Cancelled by rider');
      messenger.showSnackBar(
        const SnackBar(content: Text('Scheduled ride cancelled')),
      );
      if (mounted) setState(() => _reloadKey++);
    } on ApiException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _cancelling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Depend on the theme: the ink colours below must follow a light/dark
    // switch made while the app is open.
    Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scheduled rides')),
      body: AsyncContent<List<Trip>>(
        key: ValueKey(_reloadKey),
        load: widget.trips.scheduled,
        isEmpty: (list) => list.isEmpty,
        emptyIcon: Icons.event_available_outlined,
        emptyTitle: 'No scheduled rides',
        emptyMessage: 'Rides you book for later will appear here.',
        builder: (context, list, _) => ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          itemCount: list.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final trip = list[i];
            return ListTile(
              leading: CircleAvatar(
                backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                child: Icon(Icons.schedule, color: AppColors.accent),
              ),
              title: Text(
                trip.dropoff.address ?? 'Destination',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [
                  if (trip.scheduledAt != null)
                    Fmt.dateTime(trip.scheduledAt!)
                  else
                    'Scheduled',
                  Fmt.status(trip.tier),
                  if (trip.fareEstimate != null)
                    '${Fmt.money(trip.fareEstimate!, trip.currency)} est.',
                ].join(' · '),
                maxLines: 2,
              ),
              trailing: TextButton(
                onPressed: _cancelling ? null : () => _cancel(trip),
                child: const Text('Cancel'),
              ),
            );
          },
        ),
      ),
    );
  }
}
