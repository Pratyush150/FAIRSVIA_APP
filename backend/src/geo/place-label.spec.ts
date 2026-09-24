import {
  formatFreeTextAddress,
  formatGoogleReverse,
  formatNominatimReverse,
} from './place-label';
import * as F from './place-label.fixtures';

/** Neither field may carry a house number, postcode, plus code or country. */
function expectClean(r: { label: string; detail: string } | null) {
  expect(r).not.toBeNull();
  const all = `${r!.label}, ${r!.detail}`;
  expect(r!.label).not.toMatch(/^\d/);
  expect(all).not.toMatch(/\b\d{6}\b/); // PIN code
  expect(all).not.toMatch(/\+/); // plus code
  expect(all).not.toMatch(/India|Maharashtra/);
  const parts = all.split(',').map((p) => p.trim().toLowerCase());
  expect(new Set(parts).size).toBe(parts.length); // no repeats
}

describe('formatGoogleReverse (real Pune payloads)', () => {
  it("the audit's example: road first, Dattwadi once, no number/PIN/country", () => {
    const r = formatGoogleReverse(F.GOOGLE_KASBA_PETH);
    expect(r).toEqual({
      label: 'Mote Mangal Karyalay Rd',
      detail: 'Dattwadi, Pune',
    });
    expectClean(r);
  });

  it('house-number-only result[0] borrows the nearest road from the next results', () => {
    // result[0] is "192, Sathe Colony, Shukrawar Peth, Pune…" — no route.
    const r = formatGoogleReverse(F.GOOGLE_SHUKRAWAR_PETH);
    expect(r).toEqual({
      label: 'Shukrawar Peth - Mahatma Gandhi Road',
      detail: 'Sathe Colony, Pune',
    });
    expectClean(r);
  });

  it('a named building at the point wins over the road', () => {
    const r = formatGoogleReverse(F.GOOGLE_POLICE_COLONY);
    expect(r).toEqual({
      label: 'Police Colony Block-9',
      detail: 'Police Colony, Pune',
    });
    expectClean(r);
  });

  it("outvotes Google's wrong locality on result[0] (Chennai for a Pune point)", () => {
    const r = formatGoogleReverse(F.GOOGLE_SHIVAJINAGAR_WRONG_CITY);
    expect(r!.detail).toBe('Shivaji Nagar, Pune');
    expect(r!.label).toBe('University Road');
    expect(JSON.stringify(r)).not.toContain('Chennai');
    expectClean(r);
  });

  it('never uses a plus code as the label', () => {
    const plusOnly = [F.GOOGLE_KASBA_PETH[1]];
    expect(formatGoogleReverse(plusOnly)).toBeNull();
  });

  it('falls back to the locality when there is no building or road', () => {
    const r = formatGoogleReverse([
      {
        formatted_address: 'Bhukum, Maharashtra 412115, India',
        types: ['locality', 'political'],
        address_components: [
          { long_name: 'Bhukum', types: ['locality', 'political'] },
          { long_name: 'Maharashtra', types: ['administrative_area_level_1', 'political'] },
          { long_name: 'India', types: ['country', 'political'] },
          { long_name: '412115', types: ['postal_code'] },
        ],
      },
    ]);
    expect(r).toEqual({ label: 'Bhukum', detail: '' });
  });

  it('empty / missing results → null (caller falls back to the address)', () => {
    expect(formatGoogleReverse([])).toBeNull();
    expect(formatGoogleReverse(undefined)).toBeNull();
  });
});

describe('formatNominatimReverse (real self-hosted Nominatim payloads)', () => {
  it('POI name first, then locality + city', () => {
    const r = formatNominatimReverse(F.NOMINATIM_SHANIWAR_WADA);
    expect(r).toEqual({ label: 'Shaniwar Wada', detail: 'Kasba Peth, Pune' });
    expectClean(r);
  });

  it('a named bus stop is a landmark', () => {
    expect(formatNominatimReverse(F.NOMINATIM_BUS_STOP)).toEqual({
      label: 'Simla Office Shivajinagar',
      detail: 'Shivajinagar, Pune',
    });
  });

  it('unnamed road → locality as label, city as detail (no county/PIN)', () => {
    const r = formatNominatimReverse(F.NOMINATIM_UNNAMED_ROAD);
    expect(r).toEqual({ label: 'Shukrawar Peth', detail: 'Pune' });
    expect(JSON.stringify(r)).not.toContain('Subdistrict');
  });

  it('neighbourhood label with suburb caption', () => {
    expect(formatNominatimReverse(F.NOMINATIM_NEIGHBOURHOOD)).toEqual({
      label: 'Ex-Servicemen Colony',
      detail: 'Erandwane, Pune',
    });
  });

  it('road with a house number: road is the label, never the number', () => {
    const r = formatNominatimReverse({
      name: null,
      addresstype: 'building',
      display_name:
        '204, Mote Mangal Karyalay Road, Dattwadi, Kasba Peth, Pune, Pune City Subdistrict, 411011, India',
      address: {
        house_number: '204',
        road: 'Mote Mangal Karyalay Road',
        neighbourhood: 'Dattwadi',
        suburb: 'Kasba Peth',
        city: 'Pune',
        postcode: '411011',
        country: 'India',
      },
    });
    expect(r).toEqual({
      label: 'Mote Mangal Karyalay Road',
      detail: 'Dattwadi, Pune',
    });
  });

  it('null payload → null', () => {
    expect(formatNominatimReverse(null)).toBeNull();
  });
});

describe('formatFreeTextAddress', () => {
  it('the raw audit string: drops number, repeats, state+PIN and country', () => {
    expect(
      formatFreeTextAddress(
        '204, Mote Mangal Karyalay Rd, Dattwadi, Shobhapur, Dattwadi, Kasba Peth, Pune, Maharashtra 411011, India',
      ),
    ).toEqual({ label: 'Mote Mangal Karyalay Rd', detail: 'Dattwadi, Shobhapur' });
  });

  it('keeps a trailing city that is not a country', () => {
    expect(formatFreeTextAddress('Sathe Colony, Shukrawar Peth, Pune')).toEqual({
      label: 'Sathe Colony',
      detail: 'Shukrawar Peth, Pune',
    });
  });

  it('strips a leading plus code', () => {
    expect(formatFreeTextAddress('GV44+X4, Shukrawar Peth, Pune, India')).toEqual({
      label: 'Shukrawar Peth',
      detail: 'Pune',
    });
  });

  it('single generic value passes through', () => {
    expect(formatFreeTextAddress('Current location')).toEqual({
      label: 'Current location',
      detail: '',
    });
  });
});
