import 'dart:async';

import 'package:design_system/design_system.dart';
import 'package:flutter/material.dart';

import 'location_stream.dart';

/// Opens the OS page that fixes a given [LocationAccess] problem.
typedef LocationFixOpener = Future<bool> Function(LocationAccess access);

/// FAIRSVIA's own explanation, shown BEFORE the OS location dialog (audit
/// 3.6). A driver who meets the bare system prompt cold is more likely to
/// refuse it — and a driver without location never gets a ride offer.
///
/// What it says is what the app actually does: `requestPermission` asks for
/// "while using the app" (the manifest's background permission is only asked
/// for once that is granted, and this app never takes that second step), and
/// the online GPS stream keeps running in the background through Android's
/// foreground-service notification / iOS's background location mode, which
/// work on the while-in-use grant. Nothing is sent to the server while
/// offline (`DriverCubit.sendLocation` drops fixes then).
///
/// Pops with the [LocationAccess] of the last request, or null when the
/// driver left with "Not now" without being asked.
class LocationPrimingPage extends StatefulWidget {
  const LocationPrimingPage({
    super.key,
    this.request = checkLocationAccess,
    this.recheck = currentLocationAccess,
    this.openFix = openLocationFix,
  });

  /// Asks the OS (shows its dialog when access is undecided).
  final LocationAccessCheck request;

  /// Reads access without asking — used when the app returns from Settings.
  final LocationAccessCheck recheck;

  final LocationFixOpener openFix;

  static Route<LocationAccess?> route() => MaterialPageRoute<LocationAccess?>(
    fullscreenDialog: true,
    builder: (_) => const LocationPrimingPage(),
  );

  @override
  State<LocationPrimingPage> createState() => _LocationPrimingPageState();
}

class _LocationPrimingPageState extends State<LocationPrimingPage>
    with WidgetsBindingObserver {
  LocationAccess? _issue;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from Settings with location allowed: carry on without another tap.
    if (state == AppLifecycleState.resumed && _issue != null && !_asking) {
      unawaited(_recheck());
    }
  }

  Future<void> _recheck() async {
    final access = await widget.recheck();
    if (!mounted) return;
    if (access == LocationAccess.granted) {
      Navigator.of(context).pop(access);
    } else {
      setState(() => _issue = access);
    }
  }

  Future<void> _allow() async {
    setState(() => _asking = true);
    final access = await widget.request();
    if (!mounted) return;
    if (access == LocationAccess.granted) {
      Navigator.of(context).pop(access);
      return;
    }
    setState(() {
      _asking = false;
      _issue = access;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final issue = _issue;
    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xl,
                  AppSpacing.lg,
                  AppSpacing.lg,
                ),
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: FairsviaMark(size: 56, driver: true),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Allow location to get ride offers',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'FAIRSVIA needs your location while you are online. '
                    'On the next screen, choose "While using the app" and '
                    'keep Precise location on.',
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const _Reason(
                    icon: PhosphorIconsRegular.broadcast,
                    title: 'Ride offers near you',
                    body:
                        'Requests are sent to drivers close to the '
                        'rider. Without your location you get none.',
                  ),
                  const _Reason(
                    icon: PhosphorIconsRegular.path,
                    title: 'Riders see you coming',
                    body:
                        'Your rider follows the car to the pickup, and '
                        'the trip is measured along the road you drive.',
                  ),
                  const _Reason(
                    icon: PhosphorIconsRegular.navigationArrow,
                    title: 'Keeps working while you navigate',
                    body:
                        'While you are online, location keeps updating when '
                        'you switch to a maps app or lock the screen. Your '
                        'phone shows a notification or location indicator '
                        'the whole time.',
                  ),
                  const _Reason(
                    icon: PhosphorIconsRegular.shieldCheck,
                    title: 'Only while you are online',
                    body:
                        'When you go offline, FAIRSVIA stops sending your '
                        'location.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.sm,
                AppSpacing.lg,
                AppSpacing.lg,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Pinned above the buttons, not in the scrolling text, so
                  // it is on screen the moment the OS dialog closes.
                  if (issue != null) ...[
                    LocationAccessBanner(
                      access: issue,
                      onOpenSettings: () => unawaited(widget.openFix(issue)),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  PrimaryButton(
                    label: issue == null ? 'Continue' : 'Try again',
                    loading: _asking,
                    onPressed: _asking ? null : _allow,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextButton(
                    onPressed: _asking
                        ? null
                        : () => Navigator.of(context).pop(issue),
                    style: TextButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                    ),
                    child: const Text('Not now'),
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

class _Reason extends StatelessWidget {
  const _Reason({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The one 40 px icon container (audit 2.1).
          AppIconBadge(icon: icon),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 2),
                Text(body, style: theme.textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Persistent notice that location is blocked, with the one button that fixes
/// it. Used on the priming screen and on the offline home sheet.
class LocationAccessBanner extends StatelessWidget {
  const LocationAccessBanner({
    super.key,
    required this.access,
    required this.onOpenSettings,
  });

  final LocationAccess access;
  final VoidCallback onOpenSettings;

  static String titleFor(LocationAccess access) {
    switch (access) {
      case LocationAccess.servicesOff:
        return 'Location is turned off on this phone';
      case LocationAccess.reduced:
        return 'Precise location is off';
      case LocationAccess.deniedForever:
      case LocationAccess.denied:
      case LocationAccess.granted:
        return 'Location is not allowed for FAIRSVIA';
    }
  }

  static String bodyFor(LocationAccess access) {
    switch (access) {
      case LocationAccess.servicesOff:
        return 'Turn on location in Settings to go online and get ride '
            'offers.';
      case LocationAccess.reduced:
        return 'Turn on Precise location for FAIRSVIA in Settings, so riders '
            'can find you and trips are measured correctly.';
      case LocationAccess.deniedForever:
        return 'Your phone will not ask again. Open Settings, tap Location '
            'and choose "While using the app" to go online.';
      case LocationAccess.denied:
      case LocationAccess.granted:
        return 'You cannot go online without it. Allow location in Settings, '
            'or tap Go online to be asked again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: dark ? AppColors.errorSoftDark : AppColors.errorSoft,
          borderRadius: BorderRadius.circular(AppSpacing.radius),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Icon(
                PhosphorIconsRegular.gpsSlash,
                size: 20,
                color: AppColors.error,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titleFor(access), style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(bodyFor(access), style: theme.textTheme.bodySmall),
                  const SizedBox(height: AppSpacing.xs),
                  TextButton(
                    onPressed: onOpenSettings,
                    style: TextButton.styleFrom(
                      padding: EdgeInsets.zero,
                      minimumSize: const Size(44, 44),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      alignment: Alignment.centerLeft,
                    ),
                    child: const Text('Open Settings'),
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
