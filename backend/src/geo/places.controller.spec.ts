import { BadRequestException } from '@nestjs/common';
import { PlacesController } from './places.controller';
import { GeoProvider, RouteResult } from './geo-provider.interface';

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

function geoStub(route: RouteResult): GeoProvider {
  return {
    autocomplete: jest.fn(),
    placeDetails: jest.fn(),
    reverse: jest.fn(),
    route: jest.fn(async () => route),
  } as unknown as GeoProvider;
}

describe('PlacesController.route', () => {
  const sample: RouteResult = {
    distanceM: 1234,
    durationS: 300,
    polyline: 'abc123',
  };

  it('delegates valid coordinates to geo.route and returns the result', async () => {
    const geo = geoStub(sample);
    const controller = new PlacesController(geo);
    const res = await controller.route('18.5', '73.7', '18.52', '73.72');
    expect(res).toEqual(sample);
    expect(geo.route).toHaveBeenCalledWith(
      { lat: 18.5, lng: 73.7 },
      { lat: 18.52, lng: 73.72 },
    );
  });

  it('rejects non-numeric coordinates before calling the provider', () => {
    const geo = geoStub(sample);
    const controller = new PlacesController(geo);
    expect(() => controller.route('nope', '73.7', '18.52', '73.72')).toThrow(
      BadRequestException,
    );
    expect(geo.route).not.toHaveBeenCalled();
  });

  it('rejects a missing coordinate', () => {
    const geo = geoStub(sample);
    const controller = new PlacesController(geo);
    expect(() => controller.route('18.5', '73.7', '18.52', '')).toThrow(
      BadRequestException,
    );
  });
});

describe('PlacesController.reverse (label/detail)', () => {
  function ctrlWith(details: unknown) {
    const geo = {
      reverse: jest.fn(async () => details),
    } as unknown as GeoProvider;
    return new PlacesController(geo);
  }

  it('passes provider label/detail through and keeps the full address', async () => {
    const res = await ctrlWith({
      placeId: 'p',
      address: '204, Mote Mangal Karyalay Rd, Dattwadi, Pune, Maharashtra 411011, India',
      location: { lat: 18.5, lng: 73.8 },
      label: 'Mote Mangal Karyalay Rd',
      detail: 'Dattwadi, Pune',
    }).reverse('18.5', '73.8');
    expect(res).toEqual({
      placeId: 'p',
      address: '204, Mote Mangal Karyalay Rd, Dattwadi, Pune, Maharashtra 411011, India',
      location: { lat: 18.5, lng: 73.8 },
      label: 'Mote Mangal Karyalay Rd',
      detail: 'Dattwadi, Pune',
    });
  });

  it('derives label/detail from the address when the provider set none', async () => {
    const res = await ctrlWith({
      placeId: 'p',
      address: '192, Sathe Colony, Shukrawar Peth, Pune, Maharashtra 411002, India',
      location: { lat: 18.5, lng: 73.8 },
    }).reverse('18.5', '73.8');
    expect(res.label).toBe('Sathe Colony');
    expect(res.detail).toBe('Shukrawar Peth, Pune');
    expect(res.address).toContain('192, Sathe Colony');
  });

  it('bad coordinates → generic label without calling the provider', async () => {
    const res = await ctrlWith(null).reverse('x', '73.8');
    expect(res).toMatchObject({ address: 'Current location', label: 'Current location', detail: '' });
  });
});
