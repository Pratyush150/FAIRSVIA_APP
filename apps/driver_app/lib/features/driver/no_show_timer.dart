import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// The rider no-show wait on the "Confirm rider" sheet (Uber / Careem / Rapido
/// all run one — see docs/plans/driver-app-benchmark.md). Counts down from
/// the moment the driver arrived; once the wait is over it offers
/// "Rider didn't show", which cancels the trip and charges the rider the
/// cancellation fee (the driver's compensation). The server re-checks the
/// wait against its own arrival stamp, so a skewed phone clock can only make
/// the button appear early and be refused, never charge a rider early.
class NoShowTimer extends StatefulWidget {
  const NoShowTimer({
    super.key,
    required this.arrivedAt,
    required this.waitSec,
    required this.onNoShow,
    this.fee,
    this.busy = false,
    this.now = DateTime.now,
  });

  final DateTime arrivedAt;
  final int waitSec;

  /// What the rider is charged (and the driver paid, less the platform's
  /// share). Null keeps the wording generic.
  final double? fee;
  final bool busy;
  final Future<void> Function() onNoShow;

  /// Injectable clock for tests.
  final DateTime Function() now;

  /// Seconds left of the wait (never negative).
  static int secondsLeft(DateTime arrivedAt, int waitSec, DateTime now) {
    final waited = now.difference(arrivedAt).inSeconds;
    return (waitSec - waited).clamp(0, waitSec);
  }

  /// "4:05".
  static String clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  State<NoShowTimer> createState() => _NoShowTimerState();
}

class _NoShowTimerState extends State<NoShowTimer> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_left == 0) _tick?.cancel();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _left =>
      NoShowTimer.secondsLeft(widget.arrivedAt, widget.waitSec, widget.now());

  Future<void> _confirm() async {
    final fee = widget.fee;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Rider didn't show?"),
        content: Text(
          fee != null
              ? 'The trip is cancelled and the rider is charged the '
                  '${Fmt.money(fee)} no-show fee — your share goes to your '
                  'earnings.'
              : 'The trip is cancelled and the rider is charged the '
                  'no-show fee — your share goes to your earnings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep waiting'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Cancel trip'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.onNoShow();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final left = _left;
    final done = left == 0;
    final progress = widget.waitSec <= 0 ? 1.0 : 1 - left / widget.waitSec;

    if (!done) {
      return Semantics(
        container: true,
        label: 'Waiting for the rider. No-show option in '
            '${(left / 60).ceil()} ${left > 60 ? 'minutes' : 'minute'}.',
        child: ExcludeSemantics(
          child: Row(
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 3,
                  backgroundColor:
                      dark ? AppColors.borderDark : AppColors.borderLight,
                  valueColor: AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text('Waiting for rider',
                    style: theme.textTheme.bodyMedium),
              ),
              Text(
                NoShowTimer.clock(left),
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          liveRegion: true,
          child: Text(
            widget.fee != null
                ? "Rider hasn't come? You can cancel and get the "
                    '${Fmt.money(widget.fee!)} no-show fee.'
                : "Rider hasn't come? You can cancel with a no-show fee.",
            style: theme.textTheme.bodyMedium,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SecondaryButton(
          label: "Rider didn't show",
          icon: PhosphorIconsRegular.userMinus,
          onPressed: widget.busy ? null : _confirm,
        ),
      ],
    );
  }
}
