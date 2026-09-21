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
