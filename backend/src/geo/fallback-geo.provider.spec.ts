import { FallbackGeoProvider } from './fallback-geo.provider';
import {
  GeoProvider,
  PlaceDetails,
  RouteResult,
} from './geo-provider.interface';

const okRoute = (tag: string): RouteResult => ({
  distanceM: 1,
  durationS: 1,
  polyline: tag,
});
const okPlace = (tag: string): PlaceDetails => ({
  placeId: tag,
  address: tag,
  location: { lat: 0, lng: 0 },
});

function provider(tag: string, fail = false): jest.Mocked<GeoProvider> {
  const boom = async () => {
    throw new Error(`${tag} down`);
  };
  return {
    autocomplete: jest.fn(fail ? boom : async () => [
      { placeId: tag, primaryText: tag, secondaryText: '', description: tag },
    ]),
    placeDetails: jest.fn(fail ? boom : async () => okPlace(tag)),
    reverse: jest.fn(fail ? boom : async () => okPlace(tag)),
    route: jest.fn(fail ? boom : async () => okRoute(tag)),
  } as unknown as jest.Mocked<GeoProvider>;
}

describe('FallbackGeoProvider', () => {
  const A = { lat: 1, lng: 1 };
  const B = { lat: 2, lng: 2 };

  it('uses the primary when it succeeds and never calls the secondary', async () => {
    const primary = provider('google');
    const secondary = provider('osm');
    const fb = new FallbackGeoProvider(primary, secondary);

    expect((await fb.route(A, B)).polyline).toBe('google');
    expect((await fb.reverse(A)).address).toBe('google');
    expect((await fb.autocomplete('x'))[0].description).toBe('google');
    expect(secondary.route).not.toHaveBeenCalled();
    expect(secondary.reverse).not.toHaveBeenCalled();
    expect(secondary.autocomplete).not.toHaveBeenCalled();
  });

  it('falls back to the secondary when the primary throws', async () => {
    const primary = provider('google', true);
    const secondary = provider('osm');
    const fb = new FallbackGeoProvider(primary, secondary);

    expect((await fb.route(A, B)).polyline).toBe('osm');
    expect((await fb.reverse(A)).address).toBe('osm');
    expect((await fb.autocomplete('x'))[0].description).toBe('osm');
    expect(secondary.route).toHaveBeenCalledTimes(1);
  });

  it('rejects when both providers fail', async () => {
    const fb = new FallbackGeoProvider(
      provider('google', true),
      provider('osm', true),
    );
    await expect(fb.route(A, B)).rejects.toThrow('osm down');
  });
});
