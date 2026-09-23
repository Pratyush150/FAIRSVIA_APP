import 'package:core/core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS prefers Google Maps, then Waze, then Apple Maps, then web', () {
    final c = navigationCandidates(
        lat: 25.776, lng: -80.188, platform: TargetPlatform.iOS);
    expect(c.map((u) => u.scheme).toList(),
        ['comgooglemaps', 'waze', 'maps', 'https']);
    expect(c.first.toString(), contains('daddr=25.776,-80.188'));
    expect(c[2].toString(), contains('dirflg=d'));
  });

  test('Android uses the navigation intent first', () {
    final c = navigationCandidates(
        lat: 1, lng: 2, platform: TargetPlatform.android);
    expect(c.first.toString(), 'google.navigation:q=1.0,2.0&mode=d');
    expect(c.last.scheme, 'https');
  });

  test('openTurnByTurn launches the first app that can handle the URL',
      () async {
    final tried = <String>[];
    final ok = await openTurnByTurn(
      lat: 1,
      lng: 2,
      platform: TargetPlatform.iOS,
      canLaunch: (u) async {
        tried.add(u.scheme);
        return u.scheme == 'maps' || u.scheme == 'https';
      },
      launch: (u) async => true,
    );
    expect(ok, isTrue);
    // Never reaches the web fallback when a native app accepted the URL.
    expect(tried, isNot(contains('https')));
  });

  group('with stops on the way', () {
    const via = [(lat: 41.32, lng: 69.25), (lat: 41.33, lng: 69.26)];

    test('Android opens Google Maps directions with the stops as waypoints', () {
      final c = navigationCandidates(
          lat: 41.35, lng: 69.28, via: via, platform: TargetPlatform.android);
      expect(c.first.host, 'www.google.com');
      expect(c.first.queryParameters['waypoints'], '41.32,69.25|41.33,69.26');
      expect(c.first.queryParameters['destination'], '41.35,69.28');
      // No bare navigation intent: it would skip the stops.
      expect(c.any((u) => u.scheme == 'google.navigation'), isFalse);
    });

    test('iOS Google Maps gets every stop; Waze and Apple Maps the next one', () {
      final c = navigationCandidates(
          lat: 41.35, lng: 69.28, via: via, platform: TargetPlatform.iOS);
      expect(c.first.toString(),
          contains('daddr=41.32,69.25+to:41.33,69.26+to:41.35,69.28'));
      final waze = c.firstWhere((u) => u.scheme == 'waze');
      final apple = c.firstWhere((u) => u.scheme == 'maps');
      expect(waze.toString(), contains('ll=41.32,69.25'));
      expect(apple.toString(), contains('daddr=41.32,69.25'));
    });
  });
}
