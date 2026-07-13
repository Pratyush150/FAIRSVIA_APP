import { StubGeoProvider } from './stub-geo.provider';

describe('StubGeoProvider', () => {
  const geo = new StubGeoProvider();

  it('returns 4 predictions echoing the query', async () => {
    const preds = await geo.autocomplete('MG');
    expect(preds).toHaveLength(4);
    expect(preds[0].primaryText).toContain('MG');
    expect(preds[0].placeId).toMatch(/^stub:/);
  });

  it('round-trips coordinates through placeDetails', async () => {
    const preds = await geo.autocomplete('Koramangala');
    const details = await geo.placeDetails(preds[1].placeId);
    expect(details.location.lat).toBeCloseTo(
      Number(preds[1].placeId.slice(5).split(',')[0]),
      5,
    );
  });

  it('rejects an unknown placeId', async () => {
    await expect(geo.placeDetails('not-a-stub-id')).rejects.toThrow();
  });

  it('produces a route with detour distance, sane duration, and a polyline', async () => {
    const route = await geo.route(
      { lat: 12.9611, lng: 77.6387 },
      { lat: 12.9674, lng: 77.5904 },
    );
    expect(route.distanceM).toBeGreaterThan(0);
    expect(route.durationS).toBeGreaterThanOrEqual(60);
    expect(route.polyline.length).toBeGreaterThan(0);
  });
});
