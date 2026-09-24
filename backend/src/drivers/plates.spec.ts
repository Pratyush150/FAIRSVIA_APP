import { isValidPlate, normalizePlate } from './plates';

describe('number plates', () => {
  it('stores one form however it was typed', () => {
    expect(normalizePlate('mh 12-ab 1234')).toBe('MH12AB1234');
    expect(normalizePlate(' DL.3C.AB.1234 ')).toBe('DL3CAB1234');
  });

  it('accepts real Indian plates, including the Bharat series', () => {
    for (const p of ['MH12AB1234', 'DL3CAB1234', 'KA01XX0001', 'MH14A1', '22BH1234AA']) {
      expect(isValidPlate(p, 'INR')).toBe(true);
    }
  });

  it('refuses what cannot be an Indian plate — e.g. a Florida test plate', () => {
    for (const p of ['FL534048', 'ABC123', '1234', 'MH12AB12345']) {
      expect(isValidPlate(p, 'INR')).toBe(false);
    }
  });

  it('elsewhere, any plausible plate is fine', () => {
    expect(isValidPlate('FL534048', 'USD')).toBe(true);
    expect(isValidPlate('X', 'USD')).toBe(false);
  });
});
