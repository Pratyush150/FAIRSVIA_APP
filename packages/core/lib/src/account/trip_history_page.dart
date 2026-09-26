import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:shared_models/shared_models.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../trip/payments_remote_data_source.dart';
import '../trip/trip_remote_data_source.dart';
import 'format.dart';
import 'receipt_page.dart';
import 'widgets/async_content.dart';

/// Rates a past trip; resolves to the stars saved, or null when the rider
/// backed out. The app supplies the sheet (it owns the ratings API).
typedef RateTrip = Future<int?> Function(BuildContext context, Trip trip);

/// Past trips for the signed-in rider or driver (`GET /trips/history`),
/// grouped by day, newest first, with an All · Completed · Cancelled filter.
/// Tapping a completed trip opens its [ReceiptPage].
///
/// Each row: the ride type's car art, the destination, the time and the
/// ride's length, who drove (the rider's name on the driver's own rows), and
/// on the right the fare. A status chip shows only for rides that did not
/// complete — a completed ride needs no badge.
class TripHistoryPage extends StatelessWidget {
  const TripHistoryPage({
    super.key,
    required this.trips,
    required this.payments,
    this.isDriver = false,
    this.onRate,
    this.onBookRide,
    this.now,
  });

  final TripRemoteDataSource trips;
  final PaymentsRemoteDataSource payments;
  final bool isDriver;

  /// When set, an unrated completed trip shows a "Rate" button.
  final RateTrip? onRate;

  /// When set (rider only), the empty state offers "Book a ride".
  final VoidCallback? onBookRide;

  /// The clock the day headings are measured against (tests pin it).
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Your trips')),
      body: AsyncContent<List<Trip>>(
        load: trips.history,
        skeleton: const _TripListSkeleton(),
        builder: (context, list, _) => _TripList(
          trips: list,
          isDriver: isDriver,
          onRate: onRate,
          onBookRide: isDriver ? null : onBookRide,
          now: now?.call() ?? DateTime.now(),
          onOpen: (trip) => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ReceiptPage(
                payments: payments,
                trip: trip,
                showPayout: isDriver,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum _Filter { all, completed, cancelled }

/// When a trip is remembered: a scheduled ride by when it was booked for,
/// a finished one by when it ended.
DateTime? _when(Trip t) => t.completedAt ?? t.scheduledAt ?? t.requestedAt;

bool _isCancelled(TripStatus s) =>
    s == TripStatus.cancelled ||
    s == TripStatus.expired ||
    s == TripStatus.noDrivers;

class _TripList extends StatefulWidget {
  const _TripList({
    required this.trips,
    required this.isDriver,
    required this.onRate,
    required this.onBookRide,
    required this.now,
    required this.onOpen,
  });

  final List<Trip> trips;
  final bool isDriver;
  final RateTrip? onRate;
  final VoidCallback? onBookRide;
  final DateTime now;
  final ValueChanged<Trip> onOpen;

  @override
  State<_TripList> createState() => _TripListState();
}

class _TripListState extends State<_TripList> {
  _Filter _filter = _Filter.all;

  /// Stars given from this page, so the row updates without a reload.
  final Map<String, int> _rated = {};

  Future<void> _rate(Trip trip) async {
    final stars = await widget.onRate!(context, trip);
    if (stars != null && mounted) setState(() => _rated[trip.id] = stars);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.trips.isEmpty) {
      return _EmptyTrips(
        isDriver: widget.isDriver,
        onBookRide: widget.onBookRide,
      );
    }
    final shown = widget.trips.where((t) {
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.completed:
          return t.status == TripStatus.completed;
        case _Filter.cancelled:
          return _isCancelled(t.status);
      }
    }).toList()
      ..sort((a, b) {
        final wa = _when(a), wb = _when(b);
        if (wa == null || wb == null) return wa == null ? 1 : -1;
        return wb.compareTo(wa);
      });

    // Day headings, in order, each followed by its trips.
    final items = <Object>[];
    String? day;
    for (final t in shown) {
      final w = _when(t);
      final label = w == null ? 'Earlier' : Fmt.dayLabel(w, now: widget.now);
      if (label != day) {
        items.add(label);
        day = label;
      }
      items.add(t);
    }

    return ListView(
      // Always scrollable so pull-to-refresh works on a short list.
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
      children: [
        _FilterRow(
          value: _filter,
          onChanged: (f) => setState(() => _filter = f),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
            child: Text(
              _filter == _Filter.completed
                  ? 'No completed trips yet'
                  : 'No cancelled trips',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: _muted(context),
                  ),
            ),
          ),
        for (final item in items)
          if (item is String)
            _DayHeading(item)
          else
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TripRow(
                trip: item as Trip,
                isDriver: widget.isDriver,
                rating: _rated[item.id] ?? item.myRating,
                onTap: item.status == TripStatus.completed
                    ? () => widget.onOpen(item)
                    : null,
                onRate: widget.onRate == null
                    ? null
                    : () => _rate(item),
              ),
            ),
      ],
    );
  }
}

Color _muted(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
        ? AppColors.textSecondaryDark
        : AppColors.textSecondaryLight;

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.value, required this.onChanged});

  final _Filter value;
  final ValueChanged<_Filter> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final on = theme.colorScheme.onSurface;
    final rim = dark ? AppColors.borderDark : AppColors.borderLight;
    Widget pill(_Filter f, String label) {
      final selected = f == value;
      return Padding(
        padding: const EdgeInsets.only(right: AppSpacing.sm),
        child: Semantics(
          selected: selected,
          button: true,
          label: '$label trips',
          excludeSemantics: true,
          child: InkWell(
            onTap: () => onChanged(f),
            customBorder: const StadiumBorder(),
            // 48 dp tall hit area around a 36 dp pill.
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: AnimatedContainer(
                duration: AppMotion.fast,
                constraints: const BoxConstraints(minHeight: 36),
                padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg, vertical: 8),
                decoration: ShapeDecoration(
                  color: selected ? on : Colors.transparent,
                  shape: StadiumBorder(
                    side: BorderSide(color: selected ? on : rim),
                  ),
                ),
                child: Text(
                  label,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: selected ? theme.colorScheme.surface : on,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xs),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            pill(_Filter.all, 'All'),
            pill(_Filter.completed, 'Completed'),
            pill(_Filter.cancelled, 'Cancelled'),
          ],
        ),
      ),
    );
  }
}

class _DayHeading extends StatelessWidget {
  const _DayHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.xs, AppSpacing.lg, 0, AppSpacing.sm),
      child: Semantics(
        header: true,
        child: Text(
          label,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: _muted(context),
              ),
        ),
      ),
    );
  }
}

/// The first part of an address — "Pune Railway Station" of "Pune Railway
/// Station, Agarkar Nagar, Pune".
String _shortPlace(String? address, String fallback) {
  final a = cleanPlaceLabel(address);
  if (a.isEmpty) return fallback;
  final first = a.split(',').first.trim();
  return first.isEmpty ? a : first;
}

String? _firstName(String? name) {
  final n = name?.trim();
  if (n == null || n.isEmpty) return null;
  return n.split(RegExp(r'\s+')).first;
}

/// The chip for a ride that did not end normally; null for a completed one.
({String label, StatusTone tone})? _chipFor(TripStatus s) {
  switch (s) {
    case TripStatus.completed:
      return null;
    case TripStatus.cancelled:
      return (label: 'Cancelled', tone: StatusTone.neutral);
    case TripStatus.expired:
    case TripStatus.noDrivers:
      return (label: 'No drivers', tone: StatusTone.neutral);
    case TripStatus.paymentFailed:
      return (label: 'Payment failed', tone: StatusTone.warning);
    case TripStatus.scheduled:
      return (label: 'Scheduled', tone: StatusTone.info);
    default:
      return (label: 'In progress', tone: StatusTone.accent);
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({
    required this.trip,
    required this.isDriver,
    required this.rating,
    required this.onTap,
    required this.onRate,
  });

  final Trip trip;
  final bool isDriver;
  final int? rating;
  final VoidCallback? onTap;
  final VoidCallback? onRate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final muted = _muted(context);
    final completed = trip.status == TripStatus.completed;
    // A cancelled ride was never charged its estimate; only show an amount if
    // a final fare (cancellation fee) was actually settled.
    final fare = _isCancelled(trip.status) ? trip.fareFinal : trip.fareDisplay;
    final fareText = fare == null ? null : Fmt.money(fare, trip.currency);
    final chip = _chipFor(trip.status);
    final place = _shortPlace(trip.dropoff.address, 'Destination');

    // Line 2: when, and how long the ride was (when the backend kept it).
    final when = _when(trip);
    final meta = [
      Fmt.time(when),
      if (completed && trip.distanceM != null && trip.distanceM! > 0)
        Fmt.distance(trip.distanceM!),
      if (completed && trip.durationS != null && trip.durationS! > 0)
        Fmt.duration(trip.durationS!),
    ].join(' · ');

    // Line 3: who — the driver (and car) for a rider, the rider for a driver.
    final who = isDriver
        ? _firstName(trip.passenger?.name ?? trip.riderName)
        : _firstName(trip.driverName);
    final people = [
      if (who != null) 'with $who',
      if (!isDriver && trip.driverVehicleLabel != null)
        trip.driverVehicleLabel!,
      if (!isDriver && trip.driverPlate != null)
        Market.current.formatPlate(trip.driverPlate!),
    ].join(' · ');

    final canRate =
        completed && rating == null && onRate != null && trip.hasMyRatingField;
    final status = completed ? 'completed' : (chip?.label.toLowerCase() ?? '');
    final sentence = [
      'Trip to $place',
      if (when != null) Fmt.time(when),
      ?fareText,
      status,
      if (who != null) 'with $who',
      if (rating != null) 'you rated $rating stars',
    ].join(', ');

    final right = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (chip != null) ...[
          // What a ride that did not complete settled (e.g. a cancel fee):
          // stated, but quieter than a fare.
          if (fareText != null)
            Text(fareText,
                style: theme.textTheme.titleSmall
                    ?.copyWith(color: muted)
                    .tabular()),
        ] else if (fareText != null)
          Text(
            fareText,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700)
                .tabular(),
          ),
        if (completed && rating != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(PhosphorIconsFill.star,
                  size: 14, color: AppColors.star),
              const SizedBox(width: 3),
              Text('$rating',
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: muted, fontWeight: FontWeight.w600)),
            ],
          ),
        ] else if (canRate)
          TextButton(
            onPressed: onRate,
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 36),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              foregroundColor: AppColors.accentTextFor(dark),
              visualDensity: VisualDensity.compact,
            ),
            child: const Text('Rate'),
          ),
      ],
    );

    final content = Padding(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 56,
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: dark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(AppSpacing.radius),
            ),
            child: ExcludeSemantics(
              child: Opacity(
                // A ride that never happened reads quieter.
                opacity: completed ? 1 : 0.55,
                child: VehicleGlyph(tier: trip.tier, width: 52),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  place,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            theme.textTheme.bodyMedium?.copyWith(color: muted),
                      ),
                    ),
                    // Only a ride that did not complete carries a status.
                    if (chip != null) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        // The chip gets the larger share; the time is short.
                        flex: 2,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: AppStatusChip(
                              label: chip.label, tone: chip.tone),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                if (people.isNotEmpty)
                  Text(
                    people,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(color: muted),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // The fare / chip column never squeezes the destination to nothing:
          // at large text it scales down instead of overflowing.
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 128),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: right,
            ),
          ),
        ],
      ),
    );

    // One sentence for a screen reader; "Rate" stays reachable as an action.
    return Semantics(
      container: true,
      button: onTap != null,
      label: sentence,
      hint: onTap != null ? 'Opens the receipt' : null,
      onTap: onTap,
      customSemanticsActions: canRate
          ? {const CustomSemanticsAction(label: 'Rate this trip'): onRate!}
          : null,
      excludeSemantics: true,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: AppCard(
          padding: EdgeInsets.zero,
          onTap: onTap,
          child: content,
        ),
      ),
    );
  }
}

class _EmptyTrips extends StatelessWidget {
  const _EmptyTrips({required this.isDriver, required this.onBookRide});

  final bool isDriver;
  final VoidCallback? onBookRide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A ListView (not a Column) so pull-to-refresh still works when empty.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xl, vertical: AppSpacing.huge),
      children: [
        const Center(child: LottieMoment.emptyBox(size: 140)),
        const SizedBox(height: AppSpacing.lg),
        Text(
          'No trips yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          isDriver
              ? 'Trips you complete will show up here.'
              : 'Your rides will show up here, with receipts.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(color: _muted(context)),
        ),
        if (onBookRide != null) ...[
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: 'Book a ride', onPressed: onBookRide),
        ],
      ],
    );
  }
}

/// The loading placeholder: the real row shape, skeletonised.
class _TripListSkeleton extends StatelessWidget {
  const _TripListSkeleton();

  @override
  Widget build(BuildContext context) {
    final fake = Trip(
      id: 'skeleton',
      status: TripStatus.completed,
      tier: 'economy',
      pickup: const TripEndpoint(point: GeoPoint(0, 0)),
      dropoff: const TripEndpoint(
          point: GeoPoint(0, 0), address: 'A realistic place name'),
      fareFinal: 100,
      requestedAt: DateTime(2026),
      driverName: 'Someone Driving',
    );
    return Skeletonizer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
        children: [
          const _DayHeading('Today'),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: _TripRow(
                trip: fake,
                isDriver: false,
                rating: null,
                onTap: null,
                onRate: null,
              ),
            ),
        ],
      ),
    );
  }
}
