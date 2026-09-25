import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// The in-trip driver sheet, pull-up edition: the collapsed [child] is the
/// sheet exactly as before; a drag up (or a tap on the handle) reveals
/// [extras] underneath it, a drag down (or tap) hides them again.
class TripPullUpSheet extends StatefulWidget {
  const TripPullUpSheet({
    super.key,
    required this.child,
    required this.extras,
    this.stageKey,
    this.initiallyExpanded = false,
  });

  final Widget child;
  final Widget extras;

  /// Collapses again when this changes (a new trip phase).
  final Object? stageKey;
  final bool initiallyExpanded;

  @override
  State<TripPullUpSheet> createState() => _TripPullUpSheetState();
}

class _TripPullUpSheetState extends State<TripPullUpSheet> {
  late bool _expanded = widget.initiallyExpanded;
  double _drag = 0;

  @override
  void didUpdateWidget(TripPullUpSheet old) {
    super.didUpdateWidget(old);
    if (old.stageKey != widget.stageKey) _expanded = false;
  }

  void _set(bool v) {
    if (v != _expanded) setState(() => _expanded = v);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: (_) => _drag = 0,
      onVerticalDragUpdate: (d) => _drag += d.delta.dy,
      onVerticalDragEnd: (d) {
        final v = d.primaryVelocity ?? 0;
        if (_drag < -24 || v < -300) _set(true);
        if (_drag > 24 || v > 300) _set(false);
      },
      child: AppSheet(
        onHandleTap: () => _set(!_expanded),
        handleLabel: _expanded ? 'Collapse trip details' : 'Expand trip details',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            widget.child,
            AnimatedSize(
              duration: AppMotion.of(context, AppMotion.normal),
              curve: AppMotion.standard,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      key: const ValueKey('trip-extras'),
                      padding: const EdgeInsets.only(top: AppSpacing.lg),
                      child: widget.extras,
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

enum TripExtrasStage { toPickup, waiting, onTrip }

/// Everything below the fold of an active trip, all from the trip itself:
/// who, where, how much and how it's paid, how far, safety, and a tip.
class DriverTripExtras extends StatelessWidget {
  const DriverTripExtras({
    super.key,
    required this.stage,
    required this.trip,
    this.riderName,
    this.remainingMeters,
    this.onNavigate,
    this.onSafety,
    this.onShare,
    this.onMessage,
  });

  final TripExtrasStage stage;
  final Trip trip;
  final String? riderName;

  /// Metres left to the current target (pickup / drop-off), when known.
  final double? remainingMeters;
  final VoidCallback? onNavigate;
  final VoidCallback? onSafety;
  final VoidCallback? onShare;
  final VoidCallback? onMessage;

  @override
  Widget build(BuildContext context) {
    final t = trip;
    final passenger = t.passenger;
    final name = passenger?.displayName ??
        _orNull(riderName) ??
        _orNull(t.riderName) ??
        'Your rider';
    return Column(
      key: const ValueKey('driver-trip-extras'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RiderCard(
          name: name,
          bookedForSomeone: passenger != null,
          tier: t.tier,
          note: stage == TripExtrasStage.toPickup ? null : t.pickupNote,
        ),
        const SizedBox(height: AppSpacing.md),
        _Section(
          title: 'Route',
          child: RouteTimeline(stops: [
            RouteTimelineStop(
                label: 'Pickup',
                address: _orNull(t.pickup.address) ?? 'Pinned location'),
            for (var i = 0; i < t.stops.length; i++)
              RouteTimelineStop(
                  label: 'Stop ${i + 1}',
                  address: _orNull(t.stops[i].address) ?? 'Pinned location'),
            RouteTimelineStop(
                label: 'Drop-off',
                address: _orNull(t.dropoff.address) ?? 'Pinned location'),
          ]),
        ),
        if (_progress(context) case final p?) ...[
          const SizedBox(height: AppSpacing.md),
          p,
        ],
        const SizedBox(height: AppSpacing.md),
        _FareCard(trip: t),
        const SizedBox(height: AppSpacing.md),
        _Toolkit(
          onSafety: onSafety,
          onShare: onShare,
          onMessage: onMessage,
          onNavigate: onNavigate,
          navigateLabel:
              stage == TripExtrasStage.onTrip ? 'To drop-off' : 'To pickup',
        ),
        const SizedBox(height: AppSpacing.md),
        DriverTipPoster(tip: _tipFor(stage)),
      ],
    );
  }

  Widget? _progress(BuildContext context) {
    final theme = Theme.of(context);
    final total = trip.distanceM;
    final dur = trip.durationS;
    final lines = <String>[];
    double? fraction;
    final rem = remainingMeters;
    switch (stage) {
      case TripExtrasStage.onTrip:
        if (rem != null) {
          lines.add('${Market.current.legDistance(rem.round())} to drop-off');
          if (total != null && total > 0) {
            fraction = (1 - rem / total).clamp(0.0, 1.0);
            if (dur != null) {
              lines.add('About ${Fmt.duration((dur * rem / total).round())} left');
            }
          }
        } else if (total != null) {
          lines.add('Trip ${Market.current.legDistance(total)}'
              '${dur != null ? ' · ${Fmt.duration(dur)}' : ''}');
        }
      case TripExtrasStage.toPickup:
      case TripExtrasStage.waiting:
        if (stage == TripExtrasStage.toPickup && rem != null) {
          lines.add('${Market.current.legDistance(rem.round())} to pickup');
        }
        if (total != null) {
          lines.add('Then ${Market.current.legDistance(total)} to drop-off'
              '${dur != null ? ' · about ${Fmt.duration(dur)}' : ''}');
        }
    }
    if (lines.isEmpty) return null;
    return _Section(
      title: stage == TripExtrasStage.onTrip ? 'Trip progress' : 'Trip length',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (fraction != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 6,
                color: AppColors.accent,
                backgroundColor: AppColors.accentSoft,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          for (final l in lines) Text(l, style: theme.textTheme.bodyMedium),
        ],
      ),
    );
  }
}

String _tipFor(TripExtrasStage s) => switch (s) {
      TripExtrasStage.toPickup =>
        'Stop where it is safe and legal. Riders find you faster when you stay close to the pin.',
      TripExtrasStage.waiting =>
        'Confirm the start code before the rider gets in. It keeps both of you on the right trip.',
      TripExtrasStage.onTrip =>
        'Smooth braking and a steady speed earn the best ratings. Keep your eyes on the road.',
    };

String? _orNull(String? s) {
  final t = s?.trim();
  return (t == null || t.isEmpty) ? null : t;
}

String _tierLabel(String tier) =>
    tier.isEmpty ? tier : '${tier[0].toUpperCase()}${tier.substring(1)}';

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: theme.textTheme.labelLarge),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

class _RiderCard extends StatelessWidget {
  const _RiderCard({
    required this.name,
    required this.bookedForSomeone,
    required this.tier,
    this.note,
  });
  final String name;
  final bool bookedForSomeone;
  final String tier;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      outlined: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AppAvatar(name: name, size: 44),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: theme.textTheme.titleMedium),
                    Text(
                      bookedForSomeone
                          ? 'Booked by someone else · ${_tierLabel(tier)}'
                          : '${_tierLabel(tier)} ride',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_orNull(note) case final n?) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(PhosphorIconsRegular.note,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                    child: Text('Pickup note · $n',
                        style: theme.textTheme.bodyMedium)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _FareCard extends StatelessWidget {
  const _FareCard({required this.trip});
  final Trip trip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fare = trip.fareDisplay;
    final cash = trip.paymentMode == 'cash';
    return _Section(
      title: trip.fareFinal != null ? 'Fare' : 'Fare estimate',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fare != null ? Fmt.money(fare, trip.currency) : 'Set at the end of the trip',
                  style: fare != null
                      ? theme.textTheme.headlineSmall
                      : theme.textTheme.bodyMedium,
                ),
              ),
              Icon(cash ? PhosphorIconsRegular.money : PhosphorIconsRegular.creditCard,
                  size: 20,
                  color: AppColors.iconNeutralFor(
                      theme.brightness == Brightness.dark)),
              const SizedBox(width: AppSpacing.xs),
              Text(cash ? 'Cash' : 'Card', style: theme.textTheme.titleSmall),
            ],
          ),
          if (trip.promoDiscount > 0) ...[
            const SizedBox(height: 2),
            Text('Includes a ${Fmt.money(trip.promoDiscount, trip.currency)} rider promo',
                style: theme.textTheme.bodySmall),
          ],
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: (cash ? AppColors.warning : AppColors.accent)
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Text(
              cash
                  ? 'Collect cash from the rider at the drop-off. The final amount shows when you complete the trip.'
                  : 'Paid by card in the app. No cash to collect.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _Toolkit extends StatelessWidget {
  const _Toolkit({
    this.onSafety,
    this.onShare,
    this.onMessage,
    this.onNavigate,
    required this.navigateLabel,
  });
  final VoidCallback? onSafety;
  final VoidCallback? onShare;
  final VoidCallback? onMessage;
  final VoidCallback? onNavigate;
  final String navigateLabel;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      if (onSafety != null)
        _Tile(icon: PhosphorIconsRegular.shieldCheck, label: 'Safety & SOS', onTap: onSafety!),
      if (onShare != null)
        _Tile(icon: PhosphorIconsRegular.export, label: 'Share trip', onTap: onShare!),
      if (onMessage != null)
        _Tile(icon: PhosphorIconsRegular.chatCircle, label: 'Message', onTap: onMessage!),
      if (onNavigate != null)
        _Tile(icon: PhosphorIconsRegular.navigationArrow, label: navigateLabel, onTap: onNavigate!),
    ];
    if (tiles.isEmpty) return const SizedBox.shrink();
    return _Section(
      title: 'Tools',
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: tiles,
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: AppColors.accentSoft,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20, color: AppColors.accentInk),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Text(label,
                      style: theme.textTheme.labelLarge
                          ?.copyWith(color: AppColors.accentInk)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A small region-neutral "driver tip" poster: a gradient card with a glyph.
class DriverTipPoster extends StatelessWidget {
  const DriverTipPoster({super.key, required this.tip});
  final String tip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.accent, AppColors.accentPressed],
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(PhosphorIconsRegular.star, color: Colors.white, size: 28),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Driver tip',
                    style: theme.textTheme.labelLarge
                        ?.copyWith(color: Colors.white)),
                const SizedBox(height: 2),
                Text(tip,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: Colors.white)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Below the fold of the trip-complete sheet: this trip's fare (read back
/// from the server), today's total, the quests, and a break reminder.
class DriverCompletedExtras extends StatefulWidget {
  const DriverCompletedExtras({
    super.key,
    this.loadTrip,
    this.todayTotal,
    this.quests,
  });

  final Future<Trip> Function()? loadTrip;
  final double? todayTotal;
  final Widget? quests;

  @override
  State<DriverCompletedExtras> createState() => _DriverCompletedExtrasState();
}

class _DriverCompletedExtrasState extends State<DriverCompletedExtras> {
  late final Future<Trip>? _trip = widget.loadTrip?.call();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('driver-completed-extras'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_trip != null)
          FutureBuilder<Trip>(
            future: _trip,
            builder: (context, snap) {
              final t = snap.data;
              if (t == null) {
                if (snap.hasError) return const SizedBox.shrink();
                return const Padding(
                  padding: EdgeInsets.only(bottom: AppSpacing.md),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              final fare = t.fareDisplay;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
                child: _Section(
                  title: 'This trip',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (fare != null)
                        Text('Fare · ${Fmt.money(fare, t.currency)}'
                            ' · ${t.paymentMode == 'cash' ? 'Cash' : 'Card'}',
                            style: theme.textTheme.titleMedium),
                      if (t.distanceM != null || t.durationS != null)
                        Text(
                          [
                            if (t.distanceM != null)
                              Market.current.legDistance(t.distanceM!),
                            if (t.durationS != null) Fmt.duration(t.durationS!),
                          ].join(' · '),
                          style: theme.textTheme.bodySmall,
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      RouteTimeline(stops: [
                        RouteTimelineStop(
                            label: 'Pickup',
                            address: _orNull(t.pickup.address) ?? 'Pinned location'),
                        RouteTimelineStop(
                            label: 'Drop-off',
                            address: _orNull(t.dropoff.address) ?? 'Pinned location'),
                      ]),
                    ],
                  ),
                ),
              );
            },
          ),
        if (widget.todayTotal != null) ...[
          _Section(
            title: 'Today so far',
            child: Text(Fmt.money(widget.todayTotal!),
                style: theme.textTheme.headlineSmall),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        ?widget.quests,
        const SizedBox(height: AppSpacing.md),
        const DriverTipPoster(
          tip: 'A short stretch and some water between trips keeps you sharp for the next one.',
        ),
      ],
    );
  }
}
