import 'dart:async';

import 'package:core/core.dart';
import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Fatigue limit on the driver's online / offline sheet.
///
/// - always: "Online today: 9h 40m of 12h"
/// - within the warning window: an amber banner ("20m left before a 6h rest")
/// - locked out (offline inside the required break): a rest card with a live
///   countdown; tapping it opens [DriverRestPage].
///
/// Reads `GET /drivers/me/fatigue` on build, every [refreshEvery], and at
/// once on the server's fatigue socket events. A `driver:break_reminder`
/// (every 4 h online) shows a non-blocking snackbar.
class FatigueStatusBar extends StatefulWidget {
  const FatigueStatusBar({
    super.key,
    required this.load,
    this.events = const [],
    this.reminders,
    this.refreshEvery = const Duration(minutes: 1),
    this.onLocked,
  });

  final Future<FatigueStatus> Function() load;

  /// Server events that should trigger a re-read (warning, lock, status).
  final List<Stream<Map<String, dynamic>>> events;

  /// `driver:break_reminder` — soft "take a short break" nudges.
  final Stream<Map<String, dynamic>>? reminders;

  final Duration refreshEvery;

  /// Called once when the status turns into "resting" (show the rest screen).
  final void Function(FatigueStatus status)? onLocked;

  @override
  State<FatigueStatusBar> createState() => _FatigueStatusBarState();
}

class _FatigueStatusBarState extends State<FatigueStatusBar> {
  FatigueStatus? _status;
  Timer? _poll;
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _poll = Timer.periodic(widget.refreshEvery, (_) => unawaited(_refresh()));
    for (final s in widget.events) {
      _subs.add(s.listen((_) => unawaited(_refresh())));
    }
    final r = widget.reminders;
    if (r != null) _subs.add(r.listen(_onReminder));
  }

  @override
  void dispose() {
    _poll?.cancel();
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final s = await widget.load();
      if (!mounted) return;
      final wasResting = _status?.resting ?? false;
      setState(() => _status = s);
      if (s.resting && !wasResting) widget.onLocked?.call(s);
    } catch (_) {
      // Display-only: keep the last figure.
    }
  }

  void _onReminder(Map<String, dynamic> data) {
    if (!mounted) return;
    final secs = (data['sessionSeconds'] as num?)?.round() ?? 0;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          "You've been online ${FatigueStatus.hm(secs)} straight. "
          'A short break helps you stay sharp.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    if (s == null || s.limitSeconds <= 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.resting)
            FatigueRestCard(
              status: s,
              onTap: widget.onLocked == null ? null : () => widget.onLocked!(s),
              onDone: () => unawaited(_refresh()),
            )
          else ...[
            Semantics(
              label:
                  'Online today ${FatigueStatus.hm(s.onlineSeconds)} '
                  'of ${FatigueStatus.hm(s.limitSeconds)}',
              excludeSemantics: true,
              child: Row(
                children: [
                  const Icon(PhosphorIconsRegular.hourglass, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Text(
                      'Online today: ${FatigueStatus.hm(s.onlineSeconds)} '
                      'of ${FatigueStatus.hm(s.limitSeconds)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (s.onlineSeconds / s.limitSeconds).clamp(0.0, 1.0),
                minHeight: 4,
                color: s.nearLimit || s.overLimit
                    ? AppColors.warning
                    : AppColors.accent,
              ),
            ),
            if (s.nearLimit || s.overLimit) ...[
              const SizedBox(height: AppSpacing.sm),
              FatigueWarningBanner(status: s),
            ],
          ],
        ],
      ),
    );
  }
}

/// Amber banner in the last stretch before the limit (or over it, mid-trip).
class FatigueWarningBanner extends StatelessWidget {
  const FatigueWarningBanner({super.key, required this.status});

  final FatigueStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final rest = FatigueStatus.hm(status.restBreakSeconds);
    final title = status.overLimit
        ? 'Driving limit reached'
        : '${FatigueStatus.hm(status.remainingSeconds)} left before a $rest rest';
    final body = status.overLimit
        ? "No new trips. You'll go offline when this trip ends, then rest $rest."
        : "At ${FatigueStatus.hm(status.limitSeconds)} online you'll stop "
              'getting trips and must rest $rest.';
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: dark ? 0.22 : 0.12),
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              PhosphorIconsRegular.warning,
              size: 20,
              color: dark ? AppColors.warningDark : AppColors.warningText,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "hh:mm:ss" (or "mm:ss" under an hour) for a countdown.
String restClock(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final sec = s % 60;
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

/// Ticks a countdown from [FatigueStatus.restSecondsLeft] once a second.
mixin _RestCountdown<T extends StatefulWidget> on State<T> {
  late int left;
  Timer? _timer;
  VoidCallback? get onDone;

  void startCountdown(int seconds) {
    left = seconds;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => left = left > 0 ? left - 1 : 0);
      if (left == 0) {
        _timer?.cancel();
        onDone?.call();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The rest card on the offline sheet while going online is refused.
class FatigueRestCard extends StatefulWidget {
  const FatigueRestCard({
    super.key,
    required this.status,
    this.onTap,
    this.onDone,
  });

  final FatigueStatus status;
  final VoidCallback? onTap;
  final VoidCallback? onDone;

  @override
  State<FatigueRestCard> createState() => _FatigueRestCardState();
}

class _FatigueRestCardState extends State<FatigueRestCard>
    with _RestCountdown<FatigueRestCard> {
  @override
  VoidCallback? get onDone => widget.onDone;

  @override
  void initState() {
    super.initState();
    startCountdown(widget.status.restSecondsLeft);
  }

  @override
  void didUpdateWidget(covariant FatigueRestCard old) {
    super.didUpdateWidget(old);
    if (old.status.restSecondsLeft != widget.status.restSecondsLeft) {
      startCountdown(widget.status.restSecondsLeft);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      button: widget.onTap != null,
      label: 'Rest required. ${restClock(left)} left before you can go online.',
      excludeSemantics: true,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color: AppColors.warning.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
          child: Row(
            children: [
              const Icon(PhosphorIconsRegular.hourglass, size: 24),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Rest required', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      'You can go online in ${restClock(left)}',
                      key: const ValueKey('fatigue-rest-countdown'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-screen rest screen: why, a big countdown, and when it ends.
class DriverRestPage extends StatefulWidget {
  const DriverRestPage({super.key, required this.status});

  final FatigueStatus status;

  @override
  State<DriverRestPage> createState() => _DriverRestPageState();
}

class _DriverRestPageState extends State<DriverRestPage>
    with _RestCountdown<DriverRestPage> {
  @override
  VoidCallback? get onDone => null;

  @override
  void initState() {
    super.initState();
    startCountdown(widget.status.restSecondsLeft);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.status;
    final until = s.restUntil;
    final done = left <= 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Time to rest')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              const Icon(PhosphorIconsRegular.hourglass, size: 56),
              const SizedBox(height: AppSpacing.lg),
              Text(
                done ? 'Break complete' : 'Rest before your next ride',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "You've been online ${FatigueStatus.hm(s.onlineSeconds)}. "
                'For your safety and your riders\', RideVela needs a '
                '${FatigueStatus.hm(s.restBreakSeconds)} break after '
                '${FatigueStatus.hm(s.limitSeconds)} online.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xl),
              Semantics(
                liveRegion: false,
                label: done
                    ? 'You can go online now'
                    : '${restClock(left)} left',
                excludeSemantics: true,
                child: Text(
                  done ? 'You can go online' : restClock(left),
                  key: const ValueKey('rest-page-countdown'),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              if (until != null && !done) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Back online from '
                  '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(until))}',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
              ],
              const Spacer(),
              PrimaryButton(
                label: 'OK',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
