import {
  decodePolyline,
  encodePolyline,
  haversineMeters,
  remainingAlongPolyline,
} from './geo.util';

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

describe('decodePolyline', () => {
  it('round-trips encodePolyline to 1e-5 precision', () => {
    const pts = [
      { lat: 25.7743, lng: -80.1937 },
      { lat: 25.79, lng: -80.2 },
      { lat: 25.8012, lng: -80.2101 },
    ];
    const back = decodePolyline(encodePolyline(pts));
    expect(back).toHaveLength(3);
    back.forEach((p, i) => {
      expect(Math.abs(p.lat - pts[i].lat)).toBeLessThan(1e-5);
      expect(Math.abs(p.lng - pts[i].lng)).toBeLessThan(1e-5);
    });
  });

  it('decodes Google\'s documented example', () => {
    const pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(pts).toEqual([
      { lat: 38.5, lng: -120.2 },
      { lat: 40.7, lng: -120.95 },
      { lat: 43.252, lng: -126.453 },
    ]);
  });
});

describe('remainingAlongPolyline', () => {
  const route = [
    { lat: 25.75, lng: -80.19 },
    { lat: 25.76, lng: -80.19 },
    { lat: 25.77, lng: -80.19 },
  ];
  const seg = haversineMeters(route[0], route[1]);

  it('is the full length at the start and ~0 at the end', () => {
    // Planar segment lengths vs. haversine suffix sums differ by well under 0.1%.
    expect(Math.abs(remainingAlongPolyline(route[0], route)! - 2 * seg)).toBeLessThan(2 * seg * 0.001);
    expect(remainingAlongPolyline(route[2], route)).toBe(0);
  });

  it('snaps an off-route point to the nearest segment', () => {
    // Halfway along the first segment, 300 m east of the line.
    const p = { lat: 25.755, lng: -80.187 };
    const r = remainingAlongPolyline(p, route)!;
    expect(Math.abs(r - 1.5 * seg)).toBeLessThan(seg * 0.05);
  });

  it('returns null for a degenerate route', () => {
    expect(remainingAlongPolyline(route[0], [route[0]])).toBeNull();
    expect(remainingAlongPolyline(route[0], [])).toBeNull();
  });
});
