/**
 * Number plates: stored in one normal form (upper case, no spaces or dashes)
 * so the same car is never two plates, and checked against the market's
 * format so riders can match the plate they are told to look for.
 */

/** "mh 12-ab 1234" → "MH12AB1234". */
export function normalizePlate(raw: string): string {
  return raw.toUpperCase().replace(/[\s\-.]/g, '');
}

// India: state or union-territory code + RTO district (1–2 digits) + series (0–3 letters)
// + number (1–4 digits), e.g. MH12AB1234, DL3CAB1234; or the Bharat series,
// e.g. 22BH1234AA.
const STATES =
  'AN|AP|AR|AS|BR|CH|CG|DD|DL|DN|GA|GJ|HR|HP|JK|JH|KA|KL|LA|LD|MP|MH|MN|ML|MZ|NL|OD|OR|PY|PB|RJ|SK|TN|TS|TR|UP|UK|UA|WB';
const INDIA = new RegExp(`^(${STATES})\\d{1,2}[A-Z]{0,3}\\d{1,4}$`);
const INDIA_BH = /^\d{2}BH\d{4}[A-Z]{1,2}$/;
const ANY = /^[A-Z0-9]{2,12}$/;

/** Is [normalized] a plausible plate in the market that uses [currency]? */
export function isValidPlate(normalized: string, currency: string): boolean {
  if (currency === 'INR') return INDIA.test(normalized) || INDIA_BH.test(normalized);
  return ANY.test(normalized);
}

export const PLATE_EXAMPLE: Record<string, string> = { INR: 'MH 12 AB 1234' };

/**
 * For display, the way it is printed on the car: "MH12AB1234" → "MH 12 AB
 * 1234", Bharat series "22BH1234AA" → "22 BH 1234 AA". Anything else is
 * returned unchanged. Mirrors Market.formatPlate in the apps.
 */
export function formatPlate(plate: string): string {
  const p = normalizePlate(plate);
  const bh = /^(\d{2})(BH)(\d{4})([A-Z]{1,2})$/.exec(p);
  if (bh) return bh.slice(1).join(' ');
  const m = /^([A-Z]{2})(\d{1,2})([A-Z]{0,3})(\d{1,4})$/.exec(p);
  if (m) return m.slice(1).filter(Boolean).join(' ');
  return plate;
}
