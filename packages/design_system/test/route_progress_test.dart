import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A simple straight west→east route along the equator-ish latitude 0, from
  // lng 0 to lng 0.004 (~445m), in four 0.001° hops.
  final route = <LatLng>[
    const LatLng(0, 0.000),
    const LatLng(0, 0.001),
    const LatLng(0, 0.002),
    const LatLng(0, 0.003),
    const LatLng(0, 0.004),
  ];

  group('splitRouteAtPoint', () {
    test('car at the start: remaining is the whole route, nothing travelled',
        () {
      final s = splitRouteAtPoint(route, const LatLng(0, 0.0));
      expect(s.offRouteMeters, lessThan(1));
      // remaining spans start→end
      expect(s.remaining.first.longitude, closeTo(0.0, 1e-9));
      expect(s.remaining.last.longitude, closeTo(0.004, 1e-9));
      // travelled is just the start point (projected)
      expect(s.traveled.length, greaterThanOrEqualTo(1));
    });

    test('car halfway: remaining shrinks, starts at the car, reaches the end',
        () {
      final s = splitRouteAtPoint(route, const LatLng(0, 0.002));
      expect(s.offRouteMeters, lessThan(1));
      // The remaining line begins at the car's projected position (~0.002)…
      expect(s.remaining.first.longitude, closeTo(0.002, 1e-6));
      // …and still ends at the destination.
      expect(s.remaining.last.longitude, closeTo(0.004, 1e-9));
      // Remaining is shorter than the full route (the line has shrunk).
      expect(s.remaining.length, lessThan(route.length + 1));
    });

    test('car near the end: remaining is tiny', () {
      final s = splitRouteAtPoint(route, const LatLng(0, 0.00395));
      expect(s.remaining.first.longitude, closeTo(0.00395, 1e-5));
      expect(s.remaining.last.longitude, closeTo(0.004, 1e-9));
      // Only the last stub remains.
      expect(s.remaining.length, lessThanOrEqualTo(2));
    });

    test('car off the route reports a large offRouteMeters', () {
      // ~111m north of the route (0.001° latitude ≈ 111m).
      final s = splitRouteAtPoint(route, const LatLng(0.001, 0.002));
      expect(s.offRouteMeters, greaterThan(80));
      // Projection still lands on the nearest point (~0.002 lng).
      expect(s.remaining.first.longitude, closeTo(0.002, 1e-5));
    });

    test('degenerate route (<2 points) returns it unchanged, no throw', () {
      final s = splitRouteAtPoint(const [LatLng(1, 1)], const LatLng(0, 0));
      expect(s.remaining.length, 1);
      expect(s.offRouteMeters, 0);
    });
  });

  group('RerouteGate', () {
    final t0 = DateTime(2026, 1, 1, 12, 0, 0);
    const onRoute = LatLng(0, 0);
    const farAway = LatLng(0.5, 0.5);

    test('does not fire when the car is on the route', () {
      final gate = RerouteGate();
      expect(
        gate.shouldReroute(
            from: onRoute, offRouteMeters: 5, leg: 'approach', now: t0),
        isFalse,
      );
    });

    test('fires the first time the car is clearly off-route', () {
      final gate = RerouteGate();
      expect(
        gate.shouldReroute(
            from: onRoute, offRouteMeters: 200, leg: 'approach', now: t0),
        isTrue,
      );
    });

    test('suppresses a second fetch until interval + movement pass', () {
      final gate = RerouteGate(minInterval: const Duration(seconds: 6));
      expect(
        gate.shouldReroute(
            from: onRoute, offRouteMeters: 200, leg: 'approach', now: t0),
        isTrue,
      );
      gate.begin();
      // While a fetch is in flight, never fire.
      expect(
        gate.shouldReroute(
            from: farAway, offRouteMeters: 200, leg: 'approach', now: t0),
        isFalse,
      );
      gate.end(onRoute, now: t0);
      // Too soon after the last re-route.
      expect(
        gate.shouldReroute(
            from: farAway,
            offRouteMeters: 200,
            leg: 'approach',
            now: t0.add(const Duration(seconds: 2))),
        isFalse,
      );
      // Enough time AND movement later → fires again.
      expect(
        gate.shouldReroute(
            from: farAway,
            offRouteMeters: 200,
            leg: 'approach',
            now: t0.add(const Duration(seconds: 10))),
        isTrue,
      );
    });

    test('a new leg resets the throttle so it can fire immediately', () {
      final gate = RerouteGate();
      expect(
        gate.shouldReroute(
            from: onRoute, offRouteMeters: 200, leg: 'approach', now: t0),
        isTrue,
      );
      gate.begin();
      gate.end(onRoute, now: t0);
      // Same leg, right away → suppressed.
      expect(
        gate.shouldReroute(
            from: onRoute, offRouteMeters: 200, leg: 'approach', now: t0),
        isFalse,
      );
      // New leg → fires despite the recent re-route.
      expect(
        gate.shouldReroute(
            from: onRoute, offRouteMeters: 200, leg: 'trip', now: t0),
        isTrue,
      );
    });
  });

  group('distanceMeters', () {
    test('0.001° of latitude ≈ 111m', () {
      final d = distanceMeters(const LatLng(0, 0), const LatLng(0.001, 0));
      expect(d, closeTo(111, 3));
    });
  });
}
