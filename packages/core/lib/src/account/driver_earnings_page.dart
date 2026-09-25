import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../driver/driver_remote_data_source.dart';
import 'format.dart';
import 'widgets/async_content.dart';

/// Driver earnings dashboard (`GET /drivers/me/earnings`), modelled on what
/// Uber / Ola / Careem drivers get (docs/plans/driver-app-benchmark.md):
/// today / this-week total, trips, online time and earnings per online hour,
/// a seven-day bar chart and the trips that made up the range.
class DriverEarningsPage extends StatefulWidget {
  const DriverEarningsPage({super.key, required this.driver});

  final DriverRemoteDataSource driver;

  @override
  State<DriverEarningsPage> createState() => _DriverEarningsPageState();
}

class _DriverEarningsPageState extends State<DriverEarningsPage> {
  String _range = 'today';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Earnings')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, 0),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'today', label: Text('Today')),
                  ButtonSegment(value: 'week', label: Text('This week')),
                ],
                selected: {_range},
                showSelectedIcon: false,
                onSelectionChanged: (s) => setState(() => _range = s.first),
              ),
            ),
          ),
          Expanded(
            child: AsyncContent<DriverEarnings>(
              // Keyed by range so switching reloads with a fresh future.
              key: ValueKey(_range),
              load: () => widget.driver.earnings(range: _range),
              builder: (context, e, reload) => RefreshIndicator(
                onRefresh: () async => reload(),
                child: EarningsDashboard(earnings: e, range: _range),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The dashboard body. Public so it can be widget-tested with fixed data.
class EarningsDashboard extends StatelessWidget {
  const EarningsDashboard({
    super.key,
    required this.earnings,
    required this.range,
  });

  final DriverEarnings earnings;
  final String range;

  /// "2 h 5 min" / "0 min" — online time reads as a duration, never "1 min"
  /// for a driver who hasn't been online at all.
  static String online(int seconds) =>
      seconds < 60 ? '0 min' : Fmt.duration(seconds);

  /// Earnings per online hour, or null when there's too little online time
  /// (under 10 min) for the rate to mean anything.
  static double? perHour(double total, int? onlineSeconds) {
    if (onlineSeconds == null || onlineSeconds < 600) return null;
    return total / (onlineSeconds / 3600);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final e = earnings;
    final today = range == 'today';
    final rate = perHour(e.total, e.onlineSeconds);
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        // Hero number: the one thing a driver opens this page for.
        Semantics(
          container: true,
          label: '${today ? "Today's earnings" : "This week's earnings"} '
              '${Fmt.money(e.total)}',
          child: ExcludeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(today ? "Today's earnings" : 'Last 7 days',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: AppSpacing.xs),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(Fmt.money(e.total),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      )),
                ),
                if (e.cancellationFees > 0)
                  Text(
                    'Includes ${Fmt.money(e.cancellationFees)} '
                    'in cancellation fees',
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(child: _Stat(label: 'Trips', value: '${e.trips}')),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Stat(
                label: 'Online',
                value: e.onlineSeconds == null ? '—' : online(e.onlineSeconds!),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: _Stat(
                label: rate != null ? 'Per hour' : 'Per trip',
                value: rate != null
                    ? Fmt.money(rate.roundToDouble())
                    : (e.trips > 0 ? Fmt.money(e.total / e.trips) : '—'),
              ),
            ),
          ],
        ),
        if (e.days.length >= 2) ...[
          const SizedBox(height: AppSpacing.xl),
          Text('Last 7 days', style: theme.textTheme.titleMedium),
          const SizedBox(height: AppSpacing.md),
          WeekBars(days: e.days),
        ],
        const SizedBox(height: AppSpacing.xl),
        Text(today ? "Today's trips" : "This week's trips",
            style: theme.textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        if (e.recentTrips.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Column(
              children: [
                const LottieMoment.emptyBox(size: 96),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  today
                      ? 'No trips yet today. Go online to start earning.'
                      : 'No trips in the last 7 days.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
            ),
          )
        else
          for (final t in e.recentTrips)
            _TripRow(trip: t, showDay: !today),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label: $value',
      child: ExcludeSemantics(
        child: AppCard(
          padding: const EdgeInsets.all(AppSpacing.md),
          outlined: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value,
                    maxLines: 1,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    )),
              ),
              const SizedBox(height: 2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seven daily bars, oldest first, today last. A single series, so one hue:
/// today in the brand ink, the other days in its soft tint; thin bars with
/// rounded tops sitting on a hairline baseline. Each bar is a tooltip and a
/// labelled semantics node (the chart's "table view" for screen readers);
/// only today's value is printed, to keep the chart quiet.
class WeekBars extends StatelessWidget {
  const WeekBars({super.key, required this.days, this.height = 120});

  final List<EarningsDay> days;
  final double height;

  static const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _weekdayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final max = days.fold<double>(0, (m, d) => d.total > m ? d.total : m);
    final baseline = dark ? AppColors.borderDark : AppColors.borderLight;
    return SizedBox(
      height: height + 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final (i, d) in days.indexed)
            Expanded(
              child: Padding(
                // 2 px surface gap either side keeps adjacent bars distinct.
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _bar(context, d, i == days.length - 1, max, baseline),
              ),
            ),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context, EarningsDay d, bool isToday, double max,
      Color baseline) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final frac = max <= 0 ? 0.0 : d.total / max;
    // A day with any earnings keeps a visible 4 px stub.
    final h = d.total > 0 ? (frac * height).clamp(4.0, height) : 0.0;
    final name = _weekdayNames[d.date.weekday - 1];
    final label = '${isToday ? 'Today' : name}: ${Fmt.money(d.total)}, '
        '${d.trips} ${d.trips == 1 ? 'trip' : 'trips'}';
    return Semantics(
      container: true,
      label: label,
      child: ExcludeSemantics(
        child: Tooltip(
          message: label,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              SizedBox(
                height: 18,
                child: isToday && d.total > 0
                    ? FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(Fmt.money(d.total),
                            style: theme.textTheme.labelSmall),
                      )
                    : null,
              ),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 28),
                child: Container(
                  height: h,
                  decoration: BoxDecoration(
                    color: isToday ? AppColors.accent : AppColors.softFor(dark),
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ),
              ),
              Container(height: 1, color: baseline),
              const SizedBox(height: AppSpacing.xs),
              Text(
                _weekdays[d.date.weekday - 1],
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: isToday ? FontWeight.w700 : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TripRow extends StatelessWidget {
  const _TripRow({required this.trip, required this.showDay});
  final EarnedTrip trip;
  final bool showDay;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = trip.pickupAddr ?? 'Pickup';
    final to = trip.dropoffAddr ?? 'Drop-off';
    final when = trip.completedAt == null
        ? ''
        : showDay
            ? '${Fmt.dayLabel(trip.completedAt!)} · ${Fmt.time(trip.completedAt)}'
            : Fmt.time(trip.completedAt);
    final meta = [
      if (when.isNotEmpty) when,
      if (trip.distanceM != null) Fmt.distance(trip.distanceM!),
      if (trip.paymentMode == 'cash') 'Cash',
      if (trip.tip > 0) 'Tip ${Fmt.money(trip.tip)}',
    ].join(' · ');
    return Semantics(
      container: true,
      label: '$from to $to. $meta. Earned ${Fmt.money(trip.earned)}',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$from → $to',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 2),
                    Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(Fmt.money(trip.earned),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
