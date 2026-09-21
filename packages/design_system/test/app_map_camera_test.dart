import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

/// The rider's live-tracking camera rules, tested as pure functions so they
/// don't need a live Google Maps controller.
void main() {
  // A 1x1 degree viewport. With the default 0.28 margin the quiet middle band
  // is 0.28..0.72 on both axes.
  const sw = LatLng(0, 0);
  const ne = LatLng(1, 1);

  group('needsEdgePan', () {
    test('leaves the camera alone while the car sits in the middle band', () {
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.5), sw, ne), isFalse);
      expect(AppMap.needsEdgePan(const LatLng(0.3, 0.7), sw, ne), isFalse);
      expect(AppMap.needsEdgePan(const LatLng(0.71, 0.29), sw, ne), isFalse);
    });

    test('pans once the car crosses into a margin, on either axis', () {
      // Past the top edge.
      expect(AppMap.needsEdgePan(const LatLng(0.9, 0.5), sw, ne), isTrue);
      // Past the bottom edge.
      expect(AppMap.needsEdgePan(const LatLng(0.1, 0.5), sw, ne), isTrue);
      // Comfortable north/south, but hard against the right edge — the case
      // that used to let the car drive off screen unnoticed.
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.95), sw, ne), isTrue);
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.05), sw, ne), isTrue);
    });

    test('pans when the car is already outside the viewport entirely', () {
      expect(AppMap.needsEdgePan(const LatLng(2, 2), sw, ne), isTrue);
      expect(AppMap.needsEdgePan(const LatLng(-1, 0.5), sw, ne), isTrue);
    });

    test('holds still when the viewport is not measurable', () {
      // Zero span (controller not laid out yet) and an inverted box (a view
      // straddling the antimeridian) both mean "nothing to compare against".
      expect(AppMap.needsEdgePan(const LatLng(0.5, 0.5), sw, sw), isFalse);
      expect(
        AppMap.needsEdgePan(const LatLng(0.5, 0.5), ne, sw),
        isFalse,
      );
    });

    test('a wider margin makes the camera more eager to follow', () {
      const car = LatLng(0.8, 0.5);
      expect(AppMap.needsEdgePan(car, sw, ne, margin: 0.05), isFalse);
      expect(AppMap.needsEdgePan(car, sw, ne, margin: 0.28), isTrue);
    });
  });

  group('lookAhead', () {
    test('aims past the car in its direction of travel', () {
      // Heading due north from the middle of the viewport.
      final aimed = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne);
      expect(aimed.latitude, greaterThan(0.5)); // moved north
      expect(aimed.longitude, closeTo(0.5, 1e-9)); // not sideways
      // Due east.
      final east = AppMap.lookAhead(const LatLng(0.5, 0.5), 90, sw, ne);
      expect(east.longitude, greaterThan(0.5));
      expect(east.latitude, closeTo(0.5, 1e-9));
    });

    test('the lead stays inside the viewport', () {
      // A full half-span would put the aim point on the edge; the default
      // fraction must keep it comfortably short of that.
      final aimed = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne);
      expect(aimed.latitude - 0.5, lessThan(0.5));
      expect(aimed.latitude - 0.5, closeTo(0.5 * AppMap.lookAheadFraction, 1e-9));
    });

    test('a bigger fraction leads further ahead', () {
      final near = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne,
          fraction: 0.1);
      final far = AppMap.lookAhead(const LatLng(0.5, 0.5), 0, sw, ne,
          fraction: 0.4);
      expect(far.latitude, greaterThan(near.latitude));
    });

    test('an unknown heading leads nowhere', () {
      // Leading in a direction we are only guessing at is worse than centring.
      const car = LatLng(0.5, 0.5);
      expect(AppMap.lookAhead(car, null, sw, ne), car);
    });

    test('an unmeasurable viewport leads nowhere', () {
      const car = LatLng(0.5, 0.5);
      expect(AppMap.lookAhead(car, 45, sw, sw), car);
      expect(AppMap.lookAhead(car, 45, ne, sw), car);
    });

    test('south-west travel leads south and west', () {
      final aimed = AppMap.lookAhead(const LatLng(0.5, 0.5), 225, sw, ne);
      expect(aimed.latitude, lessThan(0.5));
      expect(aimed.longitude, lessThan(0.5));
    });
  });

  group('glideFor', () {
    test('stretches the glide to match the gap between fixes', () {
      expect(
        AppMap.glideFor(const Duration(milliseconds: 1200)),
        const Duration(milliseconds: 1200),
      );
    });

    test('floors a burst so the marker cannot strobe', () {
      expect(
        AppMap.glideFor(const Duration(milliseconds: 50)),
        const Duration(milliseconds: 400),
      );
      expect(AppMap.glideFor(Duration.zero),
          const Duration(milliseconds: 400));
    });

    test('caps a stalled stream so the car cannot crawl indefinitely', () {
      expect(
        AppMap.glideFor(const Duration(seconds: 30)),
        const Duration(milliseconds: 2500),
      );
    });
  });
}
