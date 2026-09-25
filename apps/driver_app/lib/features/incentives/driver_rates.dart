import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Acceptance and cancellation rates on the Account profile card, with a
/// one-line explanation. Neutral by default; amber (text + icon, never colour
/// alone) when acceptance is under 70% or cancellation over 10%.
class DriverRates extends StatefulWidget {
  const DriverRates({super.key, required this.load});

  final Future<DriverStats> Function() load;

  @override
  State<DriverRates> createState() => _DriverRatesState();
}

class _DriverRatesState extends State<DriverRates> {
  DriverStats? _stats;
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget
        .load()
        .then((s) {
          if (mounted) setState(() => (_stats = s, _loading = false));
        })
        .catchError((Object _) {
          if (mounted) setState(() => (_failed = true, _loading = false));
        });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_failed) {
      return Text(
        'Rates unavailable right now',
        style: theme.textTheme.bodySmall,
      );
    }
    final s = _stats;
    const pending = '…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: _Rate(
                  label: 'Acceptance',
                  value: _loading
                      ? pending
                      : DriverStats.percent(s?.acceptanceRate),
                  warn: s?.acceptanceLow ?? false,
                ),
              ),
              const VerticalDivider(width: AppSpacing.xl),
              Expanded(
                child: _Rate(
                  label: 'Cancellation',
                  value: _loading
                      ? pending
                      : DriverStats.percent(s?.cancellationRate),
                  warn: s?.cancellationHigh ?? false,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          _explain(s),
          key: const Key('rates-explainer'),
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }

  static String _explain(DriverStats? s) {
    if (s == null) return 'Last 7 days of trip offers.';
    if (s.offers == 0) {
      return 'No trip offers in the last 7 days yet — rates appear once you get some.';
    }
    final parts = <String>[
      'Last 7 days: accepted ${s.accepted} of ${s.offers} offers',
      if (s.accepted > 0) 'cancelled ${s.cancelled} of ${s.accepted} trips',
    ];
    final tip = s.acceptanceLow
        ? ' Keep acceptance above 70% to stay first in line.'
        : s.cancellationHigh
        ? ' Try to keep cancellations under 10%.'
        : '';
    return '${parts.join(', ')}. Rider no-shows never count against you.$tip';
  }
}

class _Rate extends StatelessWidget {
  const _Rate({required this.label, required this.value, required this.warn});

  final String label;
  final String value;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final warnColor = AppColors.warningTextOf(context);
    return Semantics(
      container: true,
      label: '$label rate: $value${warn ? ', needs attention' : ''}',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (warn) ...[
                Icon(PhosphorIconsRegular.warning, size: 16, color: warnColor),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                value,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: warn ? warnColor : null,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(label, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
