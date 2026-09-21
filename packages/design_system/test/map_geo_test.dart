import 'package:design_system/src/widgets/map_geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // A straight 1 km stretch north along Biscayne Blvd, in 4 segments.
  final route = [
    const LatLng(25.7700, -80.1880),
    const LatLng(25.7725, -80.1880),
    const LatLng(25.7750, -80.1880),
    const LatLng(25.7775, -80.1880),
    const LatLng(25.7790, -80.1880),
  ];

  test('routeLengthMeters sums the segments', () {
    expect(routeLengthMeters(route), closeTo(1000, 15));
  });

  test('remaining distance shrinks as the car moves along the route', () {
    final atStart = routeRemainingMeters(route, route.first);
    final midway = routeRemainingMeters(route, const LatLng(25.7745, -80.1880));
    final nearEnd = routeRemainingMeters(route, const LatLng(25.7788, -80.1880));
    expect(atStart, closeTo(1000, 15));
    expect(midway, closeTo(500, 20));
    expect(nearEnd, lessThan(40));
    expect(routeRemainingMeters(route, route.last), closeTo(0, 1));
  });

  test('a car slightly off the road is projected onto it', () {
    // 20 m east of the midpoint: remaining should still be ~500 m.
    final off = routeRemainingMeters(route, const LatLng(25.7745, -80.1878));
    expect(off, closeTo(500, 25));
  });

  test('degenerate routes return zero', () {
    expect(routeRemainingMeters(const [], const LatLng(0, 0)), 0);
    expect(routeRemainingMeters([route.first], route.first), 0);
  });

  test('routeRemainingPath starts at the projected car and keeps the tail', () {
    final rest = routeRemainingPath(route, const LatLng(25.7745, -80.1878));
    expect(rest.first.latitude, closeTo(25.7745, 0.0001));
    expect(rest.first.longitude, closeTo(-80.1880, 0.0001));
    expect(rest.last, route.last);
    expect(rest.length, 4); // projection + 3 remaining vertices
  });
}
