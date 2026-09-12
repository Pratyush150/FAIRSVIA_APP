import { BadRequestException } from '@nestjs/common';
import { PlacesController } from './places.controller';
import { GeoProvider, RouteResult } from './geo-provider.interface';

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
