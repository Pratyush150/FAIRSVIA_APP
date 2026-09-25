import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import '../driver/driver_cubit.dart';
import '../incentives/driver_rates.dart';
import '../incentives/quests.dart';

/// Today's real figures (GET /drivers/me/earnings?range=today): earned,
/// trips, online time and average per trip. Tapping opens the dashboard.
class DriverTodaySection extends StatefulWidget {
  const DriverTodaySection({super.key, required this.load, this.onOpen});

  final Future<DriverEarnings> Function() load;
  final VoidCallback? onOpen;

  @override
  State<DriverTodaySection> createState() => _DriverTodaySectionState();
}

class _DriverTodaySectionState extends State<DriverTodaySection> {
  late Future<DriverEarnings> _future = widget.load();

  static String _hours(int? s) {
    if (s == null) return '—';
    final h = s ~/ 3600;
    final m = (s % 3600) ~/ 60;
    return h > 0 ? '${h}h ${m}m' : '${m}m';
  }

  @override
  Widget build(BuildContext context) {
    return DriverExtraSection(
      title: 'Today',
      actionLabel: widget.onOpen == null ? null : 'Earnings',
      onAction: widget.onOpen,
      child: FutureBuilder<DriverEarnings>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return DriverInfoList(items: [
              DriverInfoItem(
                icon: PhosphorIconsRegular.arrowClockwise,
                title: "Couldn't load today's figures",
                detail: 'Tap to try again',
                onTap: () => setState(() => _future = widget.load()),
              ),
            ]);
          }
          final e = snap.data;
          final loading = e == null;
          return DriverStatGrid(
            onTap: widget.onOpen,
            stats: [
              DriverStat(
                  label: 'Earned',
                  value: loading ? '…' : Fmt.money(e.total),
                  icon: PhosphorIconsRegular.wallet),
              DriverStat(
                  label: 'Trips',
                  value: loading ? '…' : '${e.trips}',
                  icon: PhosphorIconsRegular.car),
              DriverStat(
                  label: 'Online',
                  value: loading ? '…' : _hours(e.onlineSeconds),
                  icon: PhosphorIconsRegular.clock),
              DriverStat(
                  label: 'Per trip',
                  value: loading
                      ? '…'
                      : (e.trips == 0 ? '—' : Fmt.money((e.total / e.trips).roundToDouble())),
                  icon: PhosphorIconsRegular.chartLineUp),
            ],
          );
        },
      ),
    );
  }
}

/// The busiest nearby areas from the live demand cells (GET
/// /drivers/me/demand), strongest first, with the straight-line distance.
class DriverBusyAreasSection extends StatelessWidget {
  const DriverBusyAreasSection({super.key, required this.cells, this.from});

  final List<DemandCell> cells;
  final LatLng? from;

  @override
  Widget build(BuildContext context) {
    final top = [...cells]..sort((a, b) => b.intensity.compareTo(a.intensity));
    final items = <DriverInfoItem>[
      for (final c in top.take(3))
        DriverInfoItem(
          icon: PhosphorIconsRegular.lightning,
          title: c.intensity >= 0.66
              ? 'Very busy area'
              : c.intensity >= 0.33
                  ? 'Busy area'
                  : 'Some requests',
          detail: c.count == 1
              ? '1 recent request'
              : '${c.count} recent requests',
          trailing: from == null
              ? null
              : '${(distanceMeters(from!, LatLng(c.lat, c.lng)) / 1000).toStringAsFixed(1)} km',
        ),
    ];
    return DriverExtraSection(
      title: 'Busy areas nearby',
      child: DriverInfoList(
        items: items.isNotEmpty
            ? items
            : const [
                DriverInfoItem(
                  icon: PhosphorIconsRegular.mapTrifold,
                  title: 'No hotspots right now',
                  detail:
                      'Busy areas are shaded on the map while you are online.',
                ),
              ],
      ),
    );
  }
}

/// Explains a feature in a small bottom sheet (the posters' tap target).
Future<void> showDriverExplainer(
  BuildContext context, {
  required IconData icon,
  required String title,
  required List<String> points,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.x20, 0, AppSpacing.x20, AppSpacing.x20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              AppIconBadge(icon: icon),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(title,
                    style: Theme.of(context).textTheme.titleLarge),
              ),
            ]),
            const SizedBox(height: AppSpacing.lg),
            for (final p in points)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(PhosphorIconsRegular.check, size: 18),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text(p)),
                  ],
                ),
              ),
            const SizedBox(height: AppSpacing.md),
            PrimaryButton(
              label: 'Got it',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Region-neutral tips and feature explainers for drivers.
List<DriverPoster> driverTipPosters(
  BuildContext context, {
  required VoidCallback onQuests,
}) {
  return [
    DriverPoster(
      title: 'Complete quests for bonuses',
      body: 'Finish the trip targets on your quests and the bonus is added '
          'to your earnings automatically.',
      cta: 'See quests',
      icon: PhosphorIconsRegular.star,
      image: 'packages/design_system/assets/promo/city_night.jpg',
      tint: const Color(0xFF123A5A),
      onTap: onQuests,
    ),
    DriverPoster(
      title: 'Take a break — safety first',
      body: 'Rest regularly. After your online-time limit the app pauses '
          'new requests so you can recharge.',
      cta: 'How breaks work',
      icon: PhosphorIconsRegular.moonStars,
      image: 'packages/design_system/assets/promo/safety_ride.webp',
      tint: const Color(0xFF1D4A3A),
      onTap: () => showDriverExplainer(
        context,
        icon: PhosphorIconsRegular.moonStars,
        title: 'Breaks and online time',
        points: const [
          'Your online time today is shown at the top of this sheet.',
          'You get a reminder to take a break before the limit.',
          'At the limit, new requests pause until your rest period ends.',
          'Rest time counts down on its own — no need to keep the app open.',
        ],
      ),
    ),
    DriverPoster(
      title: 'Heading home? Use go-home mode',
      body: 'Set a destination and only get trips that take you '
          'towards it.',
      cta: 'How it works',
      icon: PhosphorIconsRegular.house,
      image: 'packages/design_system/assets/promo/city_day.jpg',
      tint: const Color(0xFF4A2E12),
      onTap: () => showDriverExplainer(
        context,
        icon: PhosphorIconsRegular.house,
        title: 'Go-home mode',
        points: const [
          'Go online, then tap "Go home" on this sheet.',
          'Pick your home or any destination.',
          'You are matched only with trips heading your way.',
          'Turn it off any time from the same sheet.',
        ],
      ),
    ),
  ];
}

/// The pulled-up part of the offline / online sheets. Each section is shown
/// only when its data source is registered (a widget test's slim DI hides
/// them rather than faking figures).
List<Widget> driverWaitingExtras(
  BuildContext context,
  DriverState state,
  LatLng? myLocation,
) {
  final hasDriver = sl.isRegistered<DriverRemoteDataSource>();
  final hasIncentives = sl.isRegistered<IncentivesRemoteDataSource>();
  void openEarnings() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            DriverEarningsPage(driver: sl<DriverRemoteDataSource>()),
      ));
  void openQuests() => Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) =>
            QuestsPage(load: sl<IncentivesRemoteDataSource>().quests),
      ));
  return [
    if (hasDriver)
      DriverTodaySection(
        load: () => sl<DriverRemoteDataSource>().earnings(range: 'today'),
        onOpen: openEarnings,
      ),
    DriverBusyAreasSection(cells: state.demand, from: myLocation),
    if (hasIncentives)
      DriverExtraSection(
        title: 'Your rates',
        child: DriverRates(load: sl<IncentivesRemoteDataSource>().stats),
      ),
    DriverExtraSection(
      title: 'Tips for drivers',
      child: DriverPosterCarousel(
        posters: driverTipPosters(
          context,
          onQuests: hasIncentives
              ? openQuests
              : () => showDriverExplainer(
                    context,
                    icon: PhosphorIconsRegular.star,
                    title: 'Quests',
                    points: const [
                      'Quests are trip targets with a bonus.',
                      'Progress shows on this sheet while a quest is live.',
                    ],
                  ),
        ),
      ),
    ),
    if (sl.isRegistered<SupportRemoteDataSource>())
      DriverExtraSection(
        title: 'Help',
        child: DriverInfoList(items: [
          DriverInfoItem(
            icon: PhosphorIconsRegular.headset,
            title: 'Driver support',
            detail: 'Payments, trips, account questions',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => SupportPage(
                  support: sl<SupportRemoteDataSource>(), isDriver: true),
            )),
          ),
          if (hasDriver)
            DriverInfoItem(
              icon: PhosphorIconsRegular.receipt,
              title: 'Earnings and payouts',
              detail: 'Daily and weekly breakdown',
              onTap: openEarnings,
            ),
        ]),
      ),
  ];
}
