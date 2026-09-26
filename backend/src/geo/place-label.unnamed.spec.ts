import {
  formatFreeTextAddress,
  formatGoogleReverse,
  googleReverseAddress,
  isUnnamedRoad,
  stripUnnamedRoad,
} from './place-label';

// Shape of a real Google Geocoding reverse response for an Indian point on an
// unnamed segment: result[0] is a street_address/route "Unnamed Road".
const comp = (long_name: string, ...types: string[]) => ({
  long_name,
  short_name: long_name,
  types,
});
const area = [
  comp('Dattwadi', 'political', 'sublocality', 'sublocality_level_2'),
  comp('Kasba Peth', 'political', 'sublocality', 'sublocality_level_1'),
  comp('Pune', 'locality', 'political'),
  comp('Maharashtra', 'administrative_area_level_1', 'political'),
  comp('India', 'country', 'political'),
  comp('411030', 'postal_code'),
];
const unnamedFirst = {
  formatted_address: 'Unnamed Road, Dattwadi, Kasba Peth, Pune, Maharashtra 411030, India',
  types: ['route'],
  address_components: [comp('Unnamed Road', 'route'), ...area],
};
const plus = {
  formatted_address: 'GV44+X4 Pune, Maharashtra, India',
  types: ['plus_code'],
  address_components: [comp('GV44+X4', 'plus_code')],
};
const namedRoad = {
  formatted_address: 'Sinhagad Rd, Dattwadi, Pune, Maharashtra 411030, India',
  types: ['route'],
  address_components: [comp('Sinhagad Road', 'route'), ...area],
};
const poi = {
  formatted_address: 'Mhatre Bridge, Dattwadi, Pune, Maharashtra 411030, India',
  types: ['establishment', 'point_of_interest'],
  address_components: [
    comp('Mhatre Bridge', 'establishment', 'point_of_interest'),
    ...area,
  ],
};
const sublocality = {
  formatted_address: 'Dattwadi, Pune, Maharashtra 411030, India',
  types: ['political', 'sublocality', 'sublocality_level_2'],
  address_components: area,
};

describe('Unnamed Road handling', () => {
  it('isUnnamedRoad / stripUnnamedRoad', () => {
    expect(isUnnamedRoad('Unnamed Road')).toBe(true);
    expect(isUnnamedRoad(' unnamed road ')).toBe(true);
    expect(isUnnamedRoad('Unnamed Road, Pune')).toBe(false);
    expect(stripUnnamedRoad('Unnamed Road, Dattwadi, Pune')).toBe('Dattwadi, Pune');
    expect(stripUnnamedRoad('Unnamed road')).toBe('');
    expect(stripUnnamedRoad('Sinhagad Rd, Pune')).toBe('Sinhagad Rd, Pune');
  });

  it('uses a later named road when result[0] is Unnamed Road', () => {
    const r = formatGoogleReverse([unnamedFirst, plus, namedRoad]);
    // result[0] has no POI → first named road from later results wins
    expect(r).toEqual({ label: 'Sinhagad Road', detail: 'Dattwadi, Pune' });
  });

  it('prefers a POI on result[0] over any road', () => {
    const withPoi = {
      ...unnamedFirst,
      address_components: [
        comp('Mhatre Bridge', 'establishment', 'point_of_interest'),
        ...unnamedFirst.address_components,
      ],
    };
    expect(formatGoogleReverse([withPoi, poi])!.label).toBe('Mhatre Bridge');
  });

  it('falls back to sublocality + city when no named road exists', () => {
    const r = formatGoogleReverse([unnamedFirst, plus, sublocality]);
    expect(r).toEqual({ label: 'Dattwadi', detail: 'Kasba Peth, Pune' });
    expect(`${r!.label} ${r!.detail}`).not.toMatch(/unnamed/i);
  });

  it('address never starts with Unnamed Road', () => {
    expect(googleReverseAddress([unnamedFirst, plus, namedRoad])).toBe(
      'Sinhagad Rd, Dattwadi, Pune, Maharashtra 411030, India',
    );
    expect(googleReverseAddress([unnamedFirst])).toBe(
      'Dattwadi, Kasba Peth, Pune, Maharashtra 411030, India',
    );
    expect(googleReverseAddress([namedRoad])).toBe(namedRoad.formatted_address);
  });

  it('free text drops a leading Unnamed Road', () => {
    expect(formatFreeTextAddress('Unnamed Road, Dattwadi, Pune, India')).toEqual({
      label: 'Dattwadi',
      detail: 'Pune',
    });
    expect(formatFreeTextAddress('Unnamed Road').label).toBe('');
  });
});

describe('flat / wing codes are never the label', () => {
  it('drops "A1/18" and "B-204" like a house number', () => {
    const { formatFreeTextAddress } = jest.requireActual('./place-label');
    const label = formatFreeTextAddress('A1/18, Yashodhan Society, Pune, Maharashtra 411037, India');
    expect(JSON.stringify(label)).not.toContain('A1/18');
    const label2 = formatFreeTextAddress('B-204, Sai Heights, Baner, Pune');
    expect(JSON.stringify(label2)).not.toContain('B-204');
  });
});
