import { OsmGeoProvider } from './osm-geo.provider';

/** Build a fake fetch that returns `body` as JSON, asserting on the URL. */
function fakeFetch(body: unknown, ok = true, status = 200) {
  return jest.fn(async (input: URL | string) => {
    lastUrl = input.toString();
    return {
      ok,
      status,
      json: async () => body,
    } as Response;
  });
}

let lastUrl = '';

describe('OsmGeoProvider', () => {
  const geo = new OsmGeoProvider(
    'http://osrm:5000/',
    'http://nominatim:8080/',
  );

  afterEach(() => {
    (global as any).fetch = undefined;
    lastUrl = '';
  });

  it('maps Nominatim search results to predictions and hits /search', async () => {
    (global as any).fetch = fakeFetch([
      {
        name: 'Brickell City Centre',
        display_name: 'Brickell City Centre, Miami, FL, USA',
        lat: '25.7657',
        lon: '-80.1936',
      },
    ]);
    const preds = await geo.autocomplete('brickell');
    expect(lastUrl).toContain('/search');
    expect(lastUrl).toContain('q=brickell');
    expect(preds).toHaveLength(1);
    expect(preds[0].primaryText).toBe('Brickell City Centre');
    expect(preds[0].secondaryText).toBe('Miami, FL, USA');
    expect(preds[0].placeId).toMatch(/^osm:/);
  });

  it('round-trips location + address through placeDetails without a 2nd call', async () => {
    (global as any).fetch = fakeFetch([
      {
        name: 'Bayfront Park',
        display_name: 'Bayfront Park, Miami, FL, USA',
        lat: '25.7753',
        lon: '-80.1860',
      },
    ]);
    const preds = await geo.autocomplete('bayfront');
    (global as any).fetch = jest.fn(); // must NOT be called by placeDetails
    const details = await geo.placeDetails(preds[0].placeId);
    expect(details.location.lat).toBeCloseTo(25.7753, 4);
    expect(details.location.lng).toBeCloseTo(-80.186, 4);
    expect(details.address).toBe('Bayfront Park, Miami, FL, USA');
    expect((global as any).fetch).not.toHaveBeenCalled();
  });

  it('rejects an unknown placeId', async () => {
    await expect(geo.placeDetails('not-an-osm-id')).rejects.toThrow();
  });

  it('returns the OSRM road polyline, distance, and duration', async () => {
    (global as any).fetch = fakeFetch({
      code: 'Ok',
      routes: [
        { distance: 2453.7, duration: 412.9, geometry: 'ab_cD~fghApR' },
      ],
    });
    const route = await geo.route(
      { lat: 25.766, lng: -80.1955 },
      { lat: 25.7657, lng: -80.1936 },
    );
    // OSRM path format is lng,lat;lng,lat.
    expect(lastUrl).toContain('/route/v1/driving/-80.1955,25.766;-80.1936,25.7657');
    expect(lastUrl).toContain('geometries=polyline');
    expect(route.distanceM).toBe(2454);
    expect(route.durationS).toBe(413);
    expect(route.polyline).toBe('ab_cD~fghApR');
  });

  it('throws when OSRM cannot route', async () => {
    (global as any).fetch = fakeFetch({ code: 'NoRoute', routes: [] });
    await expect(
      geo.route({ lat: 25.7, lng: -80.1 }, { lat: 25.8, lng: -80.2 }),
    ).rejects.toThrow();
  });

  it('surfaces upstream HTTP errors as a bad gateway', async () => {
    (global as any).fetch = fakeFetch({}, false, 503);
    await expect(geo.autocomplete('x')).rejects.toThrow();
  });

  it('reverse returns display_name as address plus a short label/detail', async () => {
    const { NOMINATIM_SHANIWAR_WADA } = await import('./place-label.fixtures');
    (global as any).fetch = fakeFetch(NOMINATIM_SHANIWAR_WADA);
    const r = await geo.reverse({ lat: 18.5196, lng: 73.8553 });
    expect(lastUrl).toContain('/reverse');
    expect(r.address).toBe(NOMINATIM_SHANIWAR_WADA.display_name);
    expect(r.label).toBe('Shaniwar Wada');
    expect(r.detail).toBe('Kasba Peth, Pune');
  });
});
