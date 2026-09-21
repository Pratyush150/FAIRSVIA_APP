/**
 * Keys whose values never belong in an append-only log that ops staff, and
 * anyone with database access, can read forever.
 *
 * Matched case-insensitively as substrings, so `stripeSecretKey`, `apiKey` and
 * `card_number` are all caught without enumerating every spelling.
 */
const SECRET_KEY_PATTERNS = [
  'password',
  'secret',
  'token',
  'authorization',
  'apikey',
  'api_key',
  'cvc',
  'cvv',
  'cardnumber',
  'card_number',
  'pan',
  'otp',
  'code', // start codes, OTPs, promo redemption codes
  'ssn',
  'dob',
];

export const REDACTED = '[redacted]';

/** How deep to walk before giving up — guards against a cyclic or absurd body. */
const MAX_DEPTH = 6;

/** Longest string kept verbatim; anything longer is truncated with a marker. */
const MAX_STRING = 512;

/** Most array elements kept. */
const MAX_ARRAY = 50;

function isSecretKey(key: string): boolean {
  const k = key.toLowerCase();
  return SECRET_KEY_PATTERNS.some((p) => k.includes(p));
}

/**
 * A copy of [value] safe to persist: secret-looking keys replaced, long
 * strings truncated, deep structures cut off.
 *
 * Returns `undefined` for an empty body so the column stays null rather than
 * holding `{}`.
 */
export function redact(value: unknown, depth = 0): unknown {
  if (value === null || value === undefined) return value ?? undefined;
  if (depth > MAX_DEPTH) return '[truncated: too deep]';

  if (typeof value === 'string') {
    return value.length > MAX_STRING
      ? `${value.slice(0, MAX_STRING)}…[truncated ${value.length - MAX_STRING} chars]`
      : value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') return value;
  if (value instanceof Date) return value.toISOString();

  if (Array.isArray(value)) {
    const kept = value.slice(0, MAX_ARRAY).map((v) => redact(v, depth + 1));
    if (value.length > MAX_ARRAY) {
      kept.push(`[truncated ${value.length - MAX_ARRAY} more]`);
    }
    return kept;
  }

  if (typeof value === 'object') {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      out[k] = isSecretKey(k) ? REDACTED : redact(v, depth + 1);
    }
    return Object.keys(out).length > 0 ? out : undefined;
  }

  // Functions, symbols, bigint — nothing we want in an audit row.
  return undefined;
}
