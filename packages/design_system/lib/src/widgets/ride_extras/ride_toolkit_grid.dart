import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_spacing.dart';

/// One tile in a [RideToolkitGrid]: an icon over a short label.
class RideToolkitAction {
  const RideToolkitAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.danger = false,
    this.key,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Draws the icon in the error colour (SOS / emergency).
  final bool danger;
  final Key? key;
}

/// A row of equal square-ish action tiles (safety toolkit, trip shortcuts):
/// up to [perRow] per row, wrapping onto more rows beyond that. Labels wrap
/// to two lines rather than clip, so large text stays readable.
class RideToolkitGrid extends StatelessWidget {
  const RideToolkitGrid({super.key, required this.actions, this.perRow = 4});

  final List<RideToolkitAction> actions;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < actions.length; i += perRow) {
      final slice = actions.sublist(
          i, i + perRow > actions.length ? actions.length : i + perRow);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: AppSpacing.sm));
      rows.add(IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var j = 0; j < perRow; j++) ...[
              if (j > 0) const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: j < slice.length
                    ? _ToolkitTile(action: slice[j])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      ));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

class _ToolkitTile extends StatelessWidget {
  const _ToolkitTile({required this.action});

  final RideToolkitAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final a = action;
    return Semantics(
      button: true,
      label: a.label,
      excludeSemantics: true,
      child: Material(
        key: a.key,
        color: dark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radius),
          onTap: a.onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 76),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (a.danger)
                    _DangerPulse(
                      child: Icon(a.icon, size: 24, color: AppColors.error),
                    )
                  else
                    Icon(a.icon,
                        size: 24, color: theme.colorScheme.onSurface),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    a.label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A red ring that ripples out from the SOS icon a few times when the tile
/// appears, so the emergency action is found at a glance. A bounded number
/// of pulses (not an endless loop), so it never keeps a test from settling
/// or nags through a whole ride; nothing under Reduce Motion.
class _DangerPulse extends StatefulWidget {
  const _DangerPulse({required this.child});

  final Widget child;

  static const pulses = 4;

  @override
  State<_DangerPulse> createState() => _DangerPulseState();
}

class _DangerPulseState extends State<_DangerPulse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (!reduce) {
      _c.repeat(count: _DangerPulse.pulses).whenCompleteOrCancel(() {
        if (mounted) _c.value = 0;
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 24,
      height: 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final t = _c.value;
              if (t == 0) return const SizedBox.shrink();
              return IgnorePointer(
                child: Container(
                  key: const ValueKey('toolkit-danger-pulse'),
                  width: 24 + 28 * t,
                  height: 24 + 28 * t,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.error.withValues(alpha: 0.28 * (1 - t)),
                  ),
                ),
              );
            },
          ),
          widget.child,
        ],
      ),
    );
  }
}
