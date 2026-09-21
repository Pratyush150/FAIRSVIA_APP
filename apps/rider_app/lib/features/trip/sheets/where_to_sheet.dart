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
  });

  final VoidCallback onTap;
  final List<SavedPlace> savedPlaces;
  final ValueChanged<SavedPlace> onPickSaved;
  final LocationIssue? locationIssue;
  final VoidCallback? onFixLocation;

  IconData _iconFor(String label) {
    final l = label.toLowerCase();
    if (l == 'home') return Icons.home_outlined;
    if (l == 'work') return Icons.work_outline;
    return Icons.place_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final issue = locationIssue;
    if (issue != null) {
      return _LocationRequiredGate(issue: issue, onFix: onFixLocation);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Where to?', style: theme.textTheme.headlineMedium),
        const SizedBox(height: AppSpacing.lg),
        // Search pill.
        Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceMutedDark
                  : AppColors.surfaceMutedLight,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              border: Border.all(
                color: isDark ? AppColors.borderDark : AppColors.borderLight,
              ),
            ),
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppSpacing.radius),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: AppSpacing.lg,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search_rounded,
                        color: AppColors.accent, size: 22),
                    const SizedBox(width: AppSpacing.md),
                    Text('Enter your destination',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurface,
                        )),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (savedPlaces.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          for (final place in savedPlaces) ...[
            _QuickDestination(
              icon: _iconFor(place.label),
              label: place.label,
              subtitle: place.address,
              onTap: () => onPickSaved(place),
            ),
            if (place != savedPlaces.last)
              Divider(height: 1, color: theme.dividerColor),
          ],
        ],
      ],
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
            const Icon(Icons.location_off_rounded,
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
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceMutedDark
                    : AppColors.surfaceMutedLight,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: theme.colorScheme.onSurface),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: theme.textTheme.titleSmall),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
