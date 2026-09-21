import { GoogleGeoProvider } from './google-geo.provider';
import { PLACES_BIAS_RADIUS_M } from './geo-provider.interface';

/** Google Places autocomplete with the rider's position as a soft bias. The
 *  HTTP layer is mocked; assertions are on the request URL and the mapping. */
describe('GoogleGeoProvider.autocomplete', () => {
  const originalFetch = global.fetch;
  let lastUrl: URL | undefined;

  function mockGoogle(predictions: unknown[]) {
    global.fetch = jest.fn(async (url: URL) => {
      lastUrl = url;
      return {
        ok: true,
        json: async () => ({ status: 'OK', predictions }),
      } as Response;
    }) as unknown as typeof fetch;
  }

  afterEach(() => {
    global.fetch = originalFetch;
    lastUrl = undefined;
  });

  it('sends location + ~20 km radius + origin when a bias is given, and maps distance_meters', async () => {
    mockGoogle([
      {
        place_id: 'g1',
        description: 'Main St, Miami, FL',
        structured_formatting: { main_text: 'Main St', secondary_text: 'Miami, FL' },
        distance_meters: 1234.6,
      },
      { place_id: 'g2', description: 'Main St, Ohio' }, // no distance from Google
    ]);
    const geo = new GoogleGeoProvider('key');
    const preds = await geo.autocomplete('main', 'sess', { lat: 25.77, lng: -80.19 });

    expect(lastUrl!.searchParams.get('location')).toBe('25.77,-80.19');
    expect(lastUrl!.searchParams.get('radius')).toBe(String(PLACES_BIAS_RADIUS_M));
    expect(PLACES_BIAS_RADIUS_M).toBe(20000);
    expect(lastUrl!.searchParams.get('origin')).toBe('25.77,-80.19');
    expect(lastUrl!.searchParams.get('sessiontoken')).toBe('sess');
    expect(preds[0]).toEqual({
      placeId: 'g1',
      primaryText: 'Main St',
      secondaryText: 'Miami, FL',
      description: 'Main St, Miami, FL',
      distanceM: 1235,
    });
    expect(preds[1]).not.toHaveProperty('distanceM');
  });

  it('sends no bias parameters when none is given', async () => {
    mockGoogle([]);
    await new GoogleGeoProvider('key').autocomplete('main');
    expect(lastUrl!.searchParams.has('location')).toBe(false);
    expect(lastUrl!.searchParams.has('radius')).toBe(false);
    expect(lastUrl!.searchParams.has('origin')).toBe(false);
  });
});
