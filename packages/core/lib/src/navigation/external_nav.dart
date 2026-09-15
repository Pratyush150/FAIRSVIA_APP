import 'package:url_launcher/url_launcher.dart';

/// Hand off turn-by-turn navigation to the device's own maps app — the standard
/// rideshare pattern (Uber's driver "Navigate" button) for apps without a built
/// in navigation SDK. Tries Google Maps' direct navigation intent first, then a
/// universal Google Maps directions URL (opens the Maps app, or the browser as a
/// last resort). Returns true if something opened.
Future<bool> openExternalNavigation(double lat, double lng) async {
  final targets = <String>[
    // Android: opens straight into Google Maps turn-by-turn driving nav.
    'google.navigation:q=$lat,$lng&mode=d',
    // iOS Google Maps app scheme.
    'comgooglemaps://?daddr=$lat,$lng&directionsmode=driving',
    // Universal fallback — Google Maps app if installed, else the browser.
    'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
  ];
  for (final t in targets) {
    try {
      if (await launchUrl(
        Uri.parse(t),
        mode: LaunchMode.externalApplication,
      )) {
        return true;
      }
    } catch (_) {
      // Try the next candidate.
    }
  }
  return false;
}
