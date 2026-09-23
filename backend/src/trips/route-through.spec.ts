import { routeThrough } from './route-through';
import { decodePolyline, encodePolyline } from '../geo/geo.util';
import { GeoProvider, LatLng } from '../geo/geo-provider.interface';

const A = { lat: 41.3, lng: 69.2 };
const B = { lat: 41.31, lng: 69.21 };
const C = { lat: 41.32, lng: 69.23 };

/** A provider whose "roads" bend through a midpoint, unlike a straight line. */
function bendyGeo(): GeoProvider {
  return {
    route: jest.fn(async (a: LatLng, b: LatLng) => {
      const bend = { lat: a.lat, lng: b.lng };
      return { distanceM: 1000, durationS: 100, polyline: encodePolyline([a, bend, b]) };
    }),
  } as unknown as GeoProvider;
}

describe('routeThrough', () => {
  it('returns the provider route unchanged for a direct trip', async () => {
    const geo = bendyGeo();
    const r = await routeThrough(geo, [A, B]);
    expect(decodePolyline(r.polyline)).toHaveLength(3);
  });

  it('joins each leg\'s road geometry through the stops, not straight lines', async () => {
    const r = await routeThrough(bendyGeo(), [A, B, C]);
    const path = decodePolyline(r.polyline);
    // A, bend1, B, bend2, C — the shared joint B kept once.
    expect(path).toHaveLength(5);
    expect(path[1].lat).toBeCloseTo(A.lat);
    expect(path[1].lng).toBeCloseTo(B.lng);
    expect(r.distanceM).toBe(2000);
    expect(r.durationS).toBe(200);
  });

  it('falls back to a straight segment only for a leg with no geometry', async () => {
    const geo = {
      route: jest.fn(async (a: LatLng, b: LatLng) => ({
        distanceM: 500,
        durationS: 50,
        polyline: a === A ? '' : encodePolyline([a, { lat: a.lat, lng: b.lng }, b]),
      })),
    } as unknown as GeoProvider;
    const path = decodePolyline((await routeThrough(geo, [A, B, C])).polyline);
    expect(path).toHaveLength(4); // A, B (straight), bend2, C
  });
});
