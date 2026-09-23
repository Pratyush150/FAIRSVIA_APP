import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Turn-by-turn hand-off to the phone's navigation apps (what Uber Driver's
/// "Navigate" button does): tries the installed apps in order and falls back
/// to the universal Google Maps directions URL.
///
/// iOS: Google Maps → Waze → Apple Maps (always present).
/// Android: Google Maps navigation intent → Waze → web fallback.
List<Uri> navigationCandidates({
  required double lat,
  required double lng,
  TargetPlatform? platform,
  List<({double lat, double lng})> via = const [],
}) {
  final p = platform ?? defaultTargetPlatform;
  final dest = '$lat,$lng';
  if (via.isNotEmpty) return _viaCandidates(dest, via, p);
  final web = Uri.parse(
    'https://www.google.com/maps/dir/?api=1&destination=$dest&travelmode=driving',
  );
  switch (p) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return [
        Uri.parse('comgooglemaps://?daddr=$dest&directionsmode=driving'),
        Uri.parse('waze://?ll=$dest&navigate=yes'),
        Uri.parse('maps://?daddr=$dest&dirflg=d'),
        web,
      ];
    case TargetPlatform.android:
      return [
        Uri.parse('google.navigation:q=$dest&mode=d'),
        Uri.parse('waze://?ll=$dest&navigate=yes'),
        web,
      ];
    default:
      return [web];
  }
}

/// With stops on the way: only Google Maps takes waypoints (Android's
/// navigation intent does not, so it gets the directions URL). Waze and Apple
/// Maps cannot, so they are sent to the NEXT stop — the right place to drive
/// to — rather than straight to the destination past the stops.
List<Uri> _viaCandidates(
  String dest,
  List<({double lat, double lng})> via,
  TargetPlatform p,
) {
  final next = '${via.first.lat},${via.first.lng}';
  final points = via.map((w) => '${w.lat},${w.lng}');
  final web = Uri.https('www.google.com', '/maps/dir/', {
    'api': '1',
    'destination': dest,
    'waypoints': points.join('|'),
    'travelmode': 'driving',
  });
  switch (p) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return [
        Uri.parse(
            'comgooglemaps://?daddr=${[...points, dest].join('+to:')}&directionsmode=driving'),
        web,
        Uri.parse('waze://?ll=$next&navigate=yes'),
        Uri.parse('maps://?daddr=$next&dirflg=d'),
      ];
    case TargetPlatform.android:
      return [
        web,
        Uri.parse('waze://?ll=$next&navigate=yes'),
      ];
    default:
      return [web];
  }
}

/// Opens the first navigation app that can handle the destination. Returns
/// false when nothing could be launched.
Future<bool> openTurnByTurn({
  required double lat,
  required double lng,
  List<({double lat, double lng})> via = const [],
  TargetPlatform? platform,
  Future<bool> Function(Uri uri)? canLaunch,
  Future<bool> Function(Uri uri)? launch,
}) async {
  final can = canLaunch ?? canLaunchUrl;
  final go = launch ??
      (Uri u) => launchUrl(u, mode: LaunchMode.externalNonBrowserApplication)
          .catchError((_) => launchUrl(u, mode: LaunchMode.externalApplication));
  for (final uri
      in navigationCandidates(lat: lat, lng: lng, via: via, platform: platform)) {
    try {
      if (await can(uri) && await go(uri)) return true;
    } catch (_) {
      // try the next candidate
    }
  }
  return false;
}
