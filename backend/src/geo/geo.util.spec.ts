import { encodePolyline, haversineMeters } from './geo.util';

describe('geo.util', () => {
  describe('haversineMeters', () => {
    it('measures ~111.3km per degree of longitude at the equator', () => {
      const d = haversineMeters({ lat: 0, lng: 0 }, { lat: 0, lng: 1 });
      expect(d).toBeGreaterThan(111000);
      expect(d).toBeLessThan(111600);
    });

    it('is zero for identical points', () => {
      expect(haversineMeters({ lat: 12.97, lng: 77.59 }, { lat: 12.97, lng: 77.59 }))
        .toBeCloseTo(0, 5);
    });
  });

  describe('encodePolyline', () => {
    it('matches the canonical Google example', () => {
      const points = [
        { lat: 38.5, lng: -120.2 },
        { lat: 40.7, lng: -120.95 },
        { lat: 43.252, lng: -126.453 },
      ];
      expect(encodePolyline(points)).toBe('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    });

    it('returns empty string for no points', () => {
      expect(encodePolyline([])).toBe('');
    });
  });
});
