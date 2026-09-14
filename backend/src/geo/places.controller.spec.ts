import { PlacesController } from './places.controller';
import { GeoProvider } from './geo-provider.interface';

/** Search bias: the rider's position is threaded to the provider and
 *  malformed coordinates are ignored rather than rejected. */
describe('PlacesController.autocomplete', () => {
  function make() {
    const geo = {
      autocomplete: jest.fn().mockResolvedValue([
        { placeId: 'p1', primaryText: 'Main St', secondaryText: 'Miami', description: 'Main St, Miami', distanceM: 420 },
      ]),
    } as unknown as GeoProvider;
    return { ctrl: new PlacesController(geo), geo: geo as unknown as { autocomplete: jest.Mock } };
  }

  it('passes lat/lng as a bias point and returns distanceM per prediction', async () => {
    const { ctrl, geo } = make();
    const res = await ctrl.autocomplete('main', 'tok', '25.77', '-80.19');
    expect(geo.autocomplete).toHaveBeenCalledWith('main', 'tok', { lat: 25.77, lng: -80.19 });
    expect(res).toEqual({
      predictions: [expect.objectContaining({ placeId: 'p1', distanceM: 420 })],
    });
  });

  it('omits the bias when coordinates are missing or malformed', async () => {
    const { ctrl, geo } = make();
    await ctrl.autocomplete('main');
    await ctrl.autocomplete('main', undefined, '25.77'); // lng missing
    await ctrl.autocomplete('main', undefined, 'abc', '-80.19');
    await ctrl.autocomplete('main', undefined, '95', '-80.19'); // out of range
    for (const call of geo.autocomplete.mock.calls) {
      expect(call[2]).toBeUndefined();
    }
  });

  it('short queries short-circuit without hitting the provider', async () => {
    const { ctrl, geo } = make();
    await expect(ctrl.autocomplete('a', undefined, '25.77', '-80.19')).toEqual({ predictions: [] });
    expect(geo.autocomplete).not.toHaveBeenCalled();
  });
});
