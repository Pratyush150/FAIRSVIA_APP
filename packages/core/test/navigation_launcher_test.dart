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
}
