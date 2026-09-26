import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:shared_models/shared_models.dart';

/// The driver's facts on the Account profile card (audit 3.12): rating,
/// trips and plate — each from data the app really has:
///
/// * rating — `ratingAvg` / `ratingCount` on the signed-in user (`/users/me`);
/// * trips — completed trips in the **last 7 days** from
///   `/drivers/me/earnings?range=week` (no endpoint returns a lifetime count,
///   so the label says what the number is);
/// * plate — `plateNumber` from `/drivers/me`, printed the market's way.
///
/// Rendered inside the shared `AccountMenuPage` through its
/// `profileDetails` slot, so the rider's page is untouched.
class DriverProfileStats extends StatefulWidget {
  const DriverProfileStats({
    super.key,
    required this.ratingAvg,
    required this.ratingCount,
    required this.loadProfile,
    required this.loadWeek,
  });

  final double ratingAvg;
  final int ratingCount;
  final Future<DriverProfile> Function() loadProfile;
  final Future<DriverEarnings> Function() loadWeek;

  @override
  State<DriverProfileStats> createState() => _DriverProfileStatsState();
}

class _DriverProfileStatsState extends State<DriverProfileStats> {
  bool _loading = true;
  String? _plate;
  int? _trips;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Independent: a failed earnings call must not hide the plate.
    final results = await Future.wait<Object?>([
      widget.loadProfile().then<Object?>((p) => p).catchError((_) => null),
      widget.loadWeek().then<Object?>((e) => e).catchError((_) => null),
    ]);
    if (!mounted) return;
    final profile = results[0] as DriverProfile?;
    final week = results[1] as DriverEarnings?;
    setState(() {
      _loading = false;
      final plate = profile?.plateNumber.trim() ?? '';
      _plate = plate.isEmpty ? null : Market.current.formatPlate(plate);
      _trips = week?.trips;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rated = widget.ratingCount > 0;
    const pending = '…';
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _Stat(
              label: rated
                  ? '${widget.ratingCount} '
                        '${widget.ratingCount == 1 ? 'rating' : 'ratings'}'
                  : 'Rating',
              value: rated ? widget.ratingAvg.toStringAsFixed(1) : 'New',
              leading: rated
                  ? const Icon(
                      PhosphorIconsFill.star,
                      size: 16,
                      color: AppColors.star,
                    )
                  : null,
            ),
          ),
          const VerticalDivider(width: AppSpacing.xl),
          Expanded(
            child: _Stat(
              label: 'Trips · 7 days',
              value: _loading ? pending : (_trips?.toString() ?? '—'),
            ),
          ),
          const VerticalDivider(width: AppSpacing.xl),
          Expanded(
            flex: 2,
            child: _Stat(
              label: 'Plate',
              value: _loading ? pending : (_plate ?? 'Not added'),
              plate: _plate != null,
            ),
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.leading,
    this.plate = false,
  });

  final String label;
  final String value;
  final Widget? leading;
  final bool plate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: plate ? FontWeight.w700 : null,
      letterSpacing: plate ? 0.6 : null,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Semantics(
      container: true,
      // A plate is spelled out ("M H 1 2 …"), not read as words.
      label: '$label: ${plate ? AppA11y.spell(value) : value}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        // Top-aligned with a fixed-height value row, so the three columns
        // share one baseline even when the plate is scaled down to fit.
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          SizedBox(
            height: 24,
            child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leading != null) ...[
                  leading!,
                  const SizedBox(width: AppSpacing.xs),
                ],
                Text(value, maxLines: 1, style: valueStyle),
              ],
            ),
          ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
