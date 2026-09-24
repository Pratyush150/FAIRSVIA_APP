part of 'ride_sheets.dart';

/// The idle sheet: "Where to?", saved-place quick picks, and the gate shown
/// when no real position is known.

class _WhereToCard extends StatelessWidget {
  const _WhereToCard({
    required this.onTap,
    this.savedPlaces = const [],
    required this.onPickSaved,
    this.locationIssue,
    this.onFixLocation,
    this.onSchedule,
  });

  final VoidCallback onTap;

  /// Opens pre-booking; null hides the "Later" chip.
  final VoidCallback? onSchedule;
  final List<SavedPlace> savedPlaces;
  final ValueChanged<SavedPlace> onPickSaved;
  final LocationIssue? locationIssue;
  final VoidCallback? onFixLocation;

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return PhosphorIconsRegular.house;
    if (l == 'work') return PhosphorIconsRegular.briefcase;
    return PhosphorIconsRegular.mapPin;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final issue = locationIssue;
    if (issue != null) {
      return _LocationRequiredGate(issue: issue, onFix: onFixLocation);
    }
    final muted = isDark ? AppColors.surfaceMutedDark : AppColors.surfaceMutedLight;
    // One big pill is the whole call to action: "Where to?" on the left,
    // a "Later" chip on the right to book ahead.
    final pill = Semantics(
          container: true,
          button: true,
          label: 'Where to?',
          child: Material(
            // Plan F: the pill *is* glass (drawn by _FloatingWhereTo).
            color: AppGlass.enabled ? Colors.transparent : muted,
            shape: const StadiumBorder(),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(
                height: 56,
                child: Row(
                  children: [
                    const SizedBox(width: AppSpacing.lg),
                    Icon(PhosphorIconsRegular.magnifyingGlass,
                        color: theme.colorScheme.onSurface, size: 24),
                    const SizedBox(width: AppSpacing.md),
                    // Said once, by the pill's own label.
                    Expanded(
                      child: ExcludeSemantics(
                        child: Text('Where to?',
                            style: theme.textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                    ),
                    if (onSchedule != null)
                      Padding(
                        padding: const EdgeInsets.only(right: AppSpacing.sm),
                        child: _LaterChip(onTap: onSchedule!),
                      )
                    else
                      const SizedBox(width: AppSpacing.lg),
                  ],
                ),
              ),
            ),
          ),
        );
    final saved = [
      for (final place in savedPlaces) ...[
        _QuickDestination(
          icon: _iconFor(place.label),
          label: place.label,
          subtitle: place.address,
          onTap: () => onPickSaved(place),
        ),
        if (place != savedPlaces.last)
          Padding(
            padding: const EdgeInsets.only(left: 56),
            child: Divider(height: 1, color: theme.dividerColor),
          ),
      ],
    ];
    // Plan F: the pill floats over the map by itself.
    if (AppGlass.enabled) {
      return _FloatingWhereTo(pill: pill, savedPlaces: saved);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        pill,
        if (savedPlaces.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.sm),
          ...saved,
        ],
      ],
    );
  }
}

/// "Later" — book a ride ahead, from inside the Where-to pill.
class _LaterChip extends StatelessWidget {
  const _LaterChip({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Drawn ~34 tall inside the 56 pill, but it takes taps across a 48-tall
    // band (Android's minimum target) without its ripple outgrowing it.
    return Semantics(
      container: true,
      button: true,
      label: 'Book for later',
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        excludeFromSemantics: true,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            widthFactor: 1,
            child: Material(
      color: theme.colorScheme.surface,
      shape: const StadiumBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const StadiumBorder(),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md, vertical: AppSpacing.sm),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIconsRegular.clock,
                  size: 16, color: theme.colorScheme.onSurface),
              const SizedBox(width: 6),
              Text('Later', style: theme.textTheme.labelMedium),
              Icon(PhosphorIconsRegular.caretDown,
                  size: 16, color: theme.colorScheme.onSurface),
            ],
          ),
        ),
      ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Booking gate shown in place of the destination search when no real
/// position is known. Without a real fix the pickup would be the city-centre
/// fallback, which sends the driver to the wrong place — so booking is
/// blocked outright rather than allowed to go wrong quietly.
class _LocationRequiredGate extends StatelessWidget {
  const _LocationRequiredGate({required this.issue, this.onFix});

  final LocationIssue issue;
  final VoidCallback? onFix;

  String get _message => switch (issue) {
        LocationIssue.servicesOff =>
          'Location Services are off, so we can\'t tell where to pick you '
              'up. Turn them on to book a ride.',
        LocationIssue.denied =>
          'We need your location to set your pickup point and send a driver '
              'to the right place.',
        LocationIssue.deniedForever =>
          'Location access is turned off for this app. Enable it in Settings '
              'to book a ride.',
        LocationIssue.error =>
          "We couldn't read your location. Try again to book a ride.",
      };

  String get _action => switch (issue) {
        LocationIssue.servicesOff => 'Turn on Location Services',
        LocationIssue.denied => 'Allow location',
        LocationIssue.deniedForever => 'Open Settings',
        LocationIssue.error => 'Try again',
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(PhosphorIconsRegular.gpsSlash,
                color: AppColors.warning, size: 24),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text('Location required',
                  style: theme.textTheme.headlineMedium),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(_message, style: theme.textTheme.bodyMedium),
        const SizedBox(height: AppSpacing.lg),
        PrimaryButton(label: _action, onPressed: onFix),
      ],
    );
  }
}

/// A saved-place row (Home / Work / …) shown under the search pill.
class _QuickDestination extends StatelessWidget {
  const _QuickDestination({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(
          children: [
            AppIconBadge(icon: icon, tone: AppIconBadgeTone.neutral),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleMedium),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
