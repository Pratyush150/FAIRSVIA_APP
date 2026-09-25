import 'package:design_system/design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const at = LatLng(18.52, 73.86);

  test('a heat spot is a wide faint halo and a denser core', () {
    final layers = AppMap.heatLayers(
        const MapHeatSpot(point: at, intensity: 1, radiusM: 500));
    expect(layers, hasLength(2));
    final (haloR, haloA) = layers[0];
    final (coreR, coreA) = layers[1];
    expect(haloR, greaterThan(coreR));
    expect(coreA, greaterThan(haloA));
    // Capped low so street names stay readable through the shading.
    expect(coreA, lessThan(0.25));
  });

  test('intensity scales opacity, is clamped, and 0 draws nothing', () {
    final quiet = AppMap.heatLayers(const MapHeatSpot(point: at, intensity: 0.25));
    final busy = AppMap.heatLayers(const MapHeatSpot(point: at, intensity: 1));
    expect(quiet[1].$2, lessThan(busy[1].$2));
    expect(AppMap.heatLayers(const MapHeatSpot(point: at, intensity: 7)), busy);
    expect(AppMap.heatLayers(const MapHeatSpot(point: at, intensity: 0)), isEmpty);
  });
}
