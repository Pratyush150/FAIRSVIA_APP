/**
 * Short, human place labels for reverse-geocoded points.
 *
 * Providers return full postal addresses ("204, Mote Mangal Karyalay Rd,
 * Dattwadi, Shobhapur, Dattwadi, Kasba Peth, Pune, Maharashtra 411030, India")
 * which read badly as a pickup line: house number first, localities repeated,
 * postcode and country at the end. These pure functions turn a provider
 * payload into
 *
 *   label  — the landmark / building / road name ("Mote Mangal Karyalay Rd")
 *   detail — a short caption: nearest locality + city ("Dattwadi, Pune")
 *
 * Never a house number, postcode, plus code or country as the label; never a
 * repeated name. The full address stays available separately (`address`).
 */

export interface PlaceLabel {
  label: string;
  detail: string;
}

/** Google Open Location Code, full or short ("GV44+X4", "7JCMGV44+X4"). */
const PLUS_CODE = /^[23456789CFGHJMPQRVWX]{2,8}\+[23456789CFGHJMPQRVWX]{0,3}\b/i;
/** Indian PIN / generic 5-6 digit postcode, optionally after a state name. */
const POSTCODE = /\b\d{5,6}\b/;
/**
 * House / plot / flat numbers: starts with a digit ("192", "283/2/D", "7-671",
 * "12A") or a numbering prefix ("Plot 80", "Flat 3B", "H.No 12", "S.No 45").
 */
/**
 * Flat / wing codes that start with a letter: "A1/18", "B-204", "C 12",
 * "D2-301". A short letter prefix, then a number, with optional /- parts.
 */
const FLAT_CODE = /^[A-Za-z]{1,2}[\s-]?\d+[A-Za-z]?(?:[/-]\w+)*$/;

const HOUSE_NUMBER =
  /^(?:\d[\w/\-.]*|(?:plot|flat|house|h\.?\s?no\.?|s\.?\s?no\.?|sr\.?\s?no\.?|gat|survey|shop|door)\s*(?:no\.?)?\s*[\w/\-.]*\d[\w/\-.]*)$/i;

const MAX_DETAIL_PARTS = 2;

/** Trailing countries dropped from free-text addresses (served markets). */
const COUNTRIES = new Set(
  [
    'India',
    'Uzbekistan',
    "O'zbekiston",
    'Oʻzbekiston',
    'Kazakhstan',
    'Kyrgyzstan',
    'Tajikistan',
    'Turkmenistan',
    'USA',
    'United States',
    'United States of America',
  ].map((c) => c.toLowerCase()),
);

const norm = (s: string) => s.trim().replace(/\s+/g, ' ').toLowerCase();

function clean(s: unknown): string {
  return typeof s === 'string' ? s.trim().replace(/\s+/g, ' ') : '';
}

/**
 * Google's placeholder for an unnamed road segment — common across India.
 * Never a label: "Unnamed Road" tells the rider nothing.
 */
const UNNAMED_ROAD = /^unnamed\s+road$/i;
const UNNAMED_ROAD_PREFIX = /^\s*unnamed\s+road\s*(?:,\s*|$)/i;

/** True if `s` is Google's "Unnamed Road" placeholder (any case). */
export function isUnnamedRoad(s: string | null | undefined): boolean {
  return typeof s === 'string' && UNNAMED_ROAD.test(s.trim());
}

/**
 * Drop a leading "Unnamed Road, " from a full address
 * ("Unnamed Road, Dattwadi, Pune" -> "Dattwadi, Pune"). A bare "Unnamed Road"
 * becomes ''.
 */
export function stripUnnamedRoad(address: string): string {
  return clean(address).replace(UNNAMED_ROAD_PREFIX, '').trim();
}

/** True if `s` can't stand on its own as a place name. */
function isJunk(s: string): boolean {
  const t = s.trim();
  if (!t) return true;
  if (UNNAMED_ROAD.test(t)) return true;
  if (HOUSE_NUMBER.test(t)) return true;
  if (FLAT_CODE.test(t)) return true;
  if (PLUS_CODE.test(t)) return true;
  if (/^\d+$/.test(t)) return true;
  return false;
}

/** Drop empties/junk and case-insensitive duplicates, keeping first order. */
function uniqueNames(parts: string[], exclude: string[] = []): string[] {
  const seen = new Set(exclude.map(norm));
  const out: string[] = [];
  for (const raw of parts) {
    const p = clean(raw);
    if (isJunk(p)) continue;
    const k = norm(p);
    if (seen.has(k)) continue;
    seen.add(k);
    out.push(p);
  }
  return out;
}

/** Nearest locality that isn't the label, then the city: "Dattwadi, Pune". */
function buildDetail(label: string, areas: string[], city: string): string {
  const area = uniqueNames(areas, [label])[0];
  return uniqueNames([area ?? '', city], [label]).join(', ');
}

// ---------------------------------------------------------------------------
// Google Geocoding API (reverse)
// ---------------------------------------------------------------------------

interface GoogleComponent {
  long_name: string;
  short_name?: string;
  types: string[];
}
interface GoogleResult {
  formatted_address?: string;
  types?: string[];
  address_components?: GoogleComponent[];
}

/** How many of Google's (proximity-ordered) results to look through. */
const GOOGLE_SCAN = 6;

function component(r: GoogleResult | undefined, type: string): string {
  const c = (r?.address_components ?? []).find((c) => c.types.includes(type));
  return clean(c?.long_name);
}

/**
 * Label + detail from a Google reverse-geocode `results` array.
 *
 * - label: a named building/POI at the point (result[0]'s premise /
 *   establishment / point_of_interest, if it is a name and not a number),
 *   else the nearest named road (first `route` in the top results), else the
 *   most specific locality.
 * - detail: most specific locality of result[0] (neighbourhood → sublocality
 *   level 3 → 2 → 1) + the city. The city is the majority `locality` across
 *   the top results, because Google occasionally tags a single result with a
 *   wrong one (seen live: a Shivajinagar, Pune point with locality "Chennai").
 */
export function formatGoogleReverse(
  results: GoogleResult[] | undefined,
): PlaceLabel | null {
  const all = (results ?? []).filter(
    (r) => !(r.types ?? []).includes('plus_code'),
  );
  if (all.length === 0) return null;
  const top = all.slice(0, GOOGLE_SCAN);
  const first = top[0];

  const areas = [
    'neighborhood',
    'sublocality_level_3',
    'sublocality_level_2',
    'sublocality_level_1',
  ].map((t) => component(first, t));

  // City by majority vote over the top results; ties keep the earliest.
  const votes = new Map<string, { name: string; n: number; at: number }>();
  top.forEach((r, i) => {
    const name = component(r, 'locality') || component(r, 'postal_town');
    if (!name) return;
    const k = norm(name);
    const v = votes.get(k);
    if (v) v.n++;
    else votes.set(k, { name, n: 1, at: i });
  });
  const city =
    [...votes.values()].sort((a, b) => b.n - a.n || a.at - b.at)[0]?.name ??
    component(first, 'administrative_area_level_3');

  const named = [
    component(first, 'point_of_interest'),
    component(first, 'establishment'),
    ...(first.address_components ?? [])
      .filter((c) => c.types.includes('premise'))
      .map((c) => clean(c.long_name)),
  ];
  // First *named* road: Google often tags the nearest segment "Unnamed Road"
  // while a later result carries the real road name.
  const road =
    top.map((r) => component(r, 'route')).find((s) => !!s && !isJunk(s)) ?? '';

  const label =
    uniqueNames([...named, road, ...areas, city])[0] ??
    formatFreeTextAddress(first.formatted_address ?? '').label;
  if (!label) return null;
  return { label, detail: buildDetail(label, areas, city) };
}

/**
 * Full address for a Google reverse result set, never starting with
 * "Unnamed Road": the first (proximity-ordered) non-plus-code result whose
 * formatted_address names something, else result[0]'s address with the
 * "Unnamed Road, " prefix stripped.
 */
export function googleReverseAddress(
  results: GoogleResult[] | undefined,
): string {
  const all = (results ?? []).filter(
    (r) => !(r.types ?? []).includes('plus_code') && !!r.formatted_address,
  );
  const first = all[0]?.formatted_address ?? '';
  if (!UNNAMED_ROAD_PREFIX.test(first)) return clean(first);
  // Only prefer a later result if it is still street-level-ish (not just
  // "Pune, Maharashtra, India"): take one with a route/premise/POI/area.
  const better = all.slice(1, GOOGLE_SCAN).find((r) => {
    const fa = r.formatted_address ?? '';
    if (UNNAMED_ROAD_PREFIX.test(fa)) return false;
    const t = r.types ?? [];
    return [
      'street_address',
      'route',
      'premise',
      'establishment',
      'point_of_interest',
      'neighborhood',
      'sublocality_level_2',
      'sublocality_level_1',
    ].some((x) => t.includes(x));
  });
  return clean(better?.formatted_address ?? '') || stripUnnamedRoad(first);
}

// ---------------------------------------------------------------------------
// Nominatim (OSM) reverse, format=jsonv2&addressdetails=1
// ---------------------------------------------------------------------------

interface NominatimReverse {
  name?: string | null;
  display_name?: string;
  addresstype?: string;
  address?: Record<string, string>;
}

const OSM_AREA_KEYS = [
  'neighbourhood',
  'quarter',
  'residential',
  'suburb',
  'city_district',
  'hamlet',
  'village',
];
const OSM_CITY_KEYS = ['city', 'town', 'municipality', 'village', 'county'];
/** Address keys that are themselves the named feature (POI) at the point. */
const OSM_FEATURE_KEYS = [
  'amenity',
  'shop',
  'tourism',
  'building',
  'place',
  'leisure',
  'office',
  'historic',
  'railway',
  'aeroway',
  'highway',
  'man_made',
];

/**
 * Label + detail from a Nominatim jsonv2 reverse result.
 *
 * - label: the feature's own `name` (POI, bus stop, named road…), else a named
 *   feature in `address` (amenity/building/…), else `road`, else the locality.
 * - detail: nearest locality (neighbourhood → suburb …) + city.
 */
export function formatNominatimReverse(
  r: NominatimReverse | undefined | null,
): PlaceLabel | null {
  if (!r) return null;
  const a = r.address ?? {};
  const areas = OSM_AREA_KEYS.map((k) => clean(a[k]));
  const city = OSM_CITY_KEYS.map((k) => clean(a[k])).find((s) => !!s) ?? '';
  const feature = [
    clean(r.name),
    r.addresstype ? clean(a[r.addresstype]) : '',
    ...OSM_FEATURE_KEYS.map((k) => clean(a[k])),
  ];
  const label =
    uniqueNames([...feature, clean(a.road), ...areas, city])[0] ??
    formatFreeTextAddress(r.display_name ?? '').label;
  if (!label) return null;
  return { label, detail: buildDetail(label, areas, city) };
}

// ---------------------------------------------------------------------------
// Free-text fallback (stub provider, unknown payloads)
// ---------------------------------------------------------------------------

/**
 * Best effort from a comma-separated address alone: drop house numbers, plus
 * codes, postcodes, the country and duplicates; first remaining part is the
 * label, the next two the detail. Postcodes glued to a state name
 * ("Maharashtra 411002") drop the whole part — the state is noise here too.
 */
export function formatFreeTextAddress(address: string): PlaceLabel {
  const parts = stripUnnamedRoad(address)
    .split(',')
    .map((p) => p.trim())
    .filter((p) => !!p);
  if (parts.length > 1 && COUNTRIES.has(norm(parts[parts.length - 1]))) {
    parts.pop();
  }
  const kept = uniqueNames(parts.filter((p) => !POSTCODE.test(p)));
  if (kept.length === 0) {
    const fallback = stripUnnamedRoad(address);
    return { label: fallback, detail: '' };
  }
  return {
    label: kept[0],
    detail: kept.slice(1, 1 + MAX_DETAIL_PARTS).join(', '),
  };
}
