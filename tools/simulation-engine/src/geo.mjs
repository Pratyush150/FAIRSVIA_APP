// Realistic geography: named Miami demand hotspots, weighted origin/destination
// selection, OSRM road-following routes, and along-route interpolation with
// bearing — so simulated cars drive on streets and turn on corners.

import { OSRM } from './config.mjs';

/**
 * Miami-area hotspots with a demand `weight` (higher = more trips originate /
 * terminate here). Roughly models a real demand surface: downtown/Brickell and
 * the airport dominate, beaches and neighborhoods trail.
 */
export const HOTSPOTS = [
  { name: 'Brickell', lat: 25.7615, lng: -80.1929, weight: 10 },
  { name: 'Downtown Miami', lat: 25.7743, lng: -80.1937, weight: 9 },
  { name: 'Miami Intl Airport', lat: 25.7959, lng: -80.287, weight: 10 },
  { name: 'Wynwood', lat: 25.8049, lng: -80.1993, weight: 7 },
  { name: 'Miami Beach', lat: 25.7907, lng: -80.13, weight: 8 },
  { name: 'Coral Gables', lat: 25.7215, lng: -80.2684, weight: 5 },
  { name: 'Little Havana', lat: 25.7657, lng: -80.2197, weight: 5 },
  { name: 'Coconut Grove', lat: 25.7289, lng: -80.2434, weight: 4 },
  { name: 'Design District', lat: 25.8137, lng: -80.1931, weight: 4 },
  { name: 'Edgewater', lat: 25.7986, lng: -80.19, weight: 4 },
  { name: 'Key Biscayne', lat: 25.6907, lng: -80.1626, weight: 2 },
  { name: 'Doral', lat: 25.8195, lng: -80.3553, weight: 3 },
];

// The active demand region — scenarios can restrict to a coverable cluster so a
// modest fleet gives realistic coverage; default is the whole metro (where far,
// low-weight hotspots legitimately produce occasional no_drivers).
let ACTIVE = HOTSPOTS;

/** Limit demand + driver placement to the named hotspots (null = whole metro). */
export function setRegion(names) {
  ACTIVE = names && names.length ? HOTSPOTS.filter((h) => names.includes(h.name)) : HOTSPOTS;
}

// Tier supply/demand mix. Drivers onboard and riders request from the SAME
// distribution so per-tier supply roughly tracks demand (a rider requesting a
// tier with no online drivers is an instant no_drivers — realistic but must be
// modeled deliberately, not by accident).
let TIER_WEIGHTS = [['economy', 0.7], ['comfort', 0.2], ['xl', 0.1]];

/** Override the tier mix (e.g. [['economy', 1]] for an all-economy scenario). */
export function setTierWeights(pairs) {
  if (pairs && pairs.length) TIER_WEIGHTS = pairs;
}

/** Weighted-random ride tier (rider demand). */
export function pickTier() {
  const total = TIER_WEIGHTS.reduce((a, [, w]) => a + w, 0);
  let r = Math.random() * total;
  for (const [tier, w] of TIER_WEIGHTS) {
    r -= w;
    if (r <= 0) return tier;
  }
  return TIER_WEIGHTS[0][0];
}

/**
 * Deterministically assign tiers to a fleet of `n` drivers, proportional to the
 * demand weights but GUARANTEEING at least one driver per tier that has demand
 * (as long as n >= number of tiers). This prevents the small-fleet failure mode
 * where random per-driver tiers leave a requested tier with zero supply — an
 * artifact of the simulator, not a real dispatch fault. Largest-remainder
 * apportionment, then round-robin so tiers interleave during ramp-up.
 */
export function assignTiers(n) {
  const total = TIER_WEIGHTS.reduce((a, [, w]) => a + w, 0);
  const active = TIER_WEIGHTS.filter(([, w]) => w > 0);
  if (!active.length || n <= 0) return Array.from({ length: Math.max(0, n) }, () => TIER_WEIGHTS[0][0]);

  // Floor allocation + guaranteed 1 each (when the fleet can afford it).
  const alloc = active.map(([tier, w]) => ({ tier, exact: (w / total) * n, count: 0 }));
  if (n >= active.length) alloc.forEach((a) => { a.count = 1; });
  let used = alloc.reduce((s, a) => s + a.count, 0);

  // Distribute the rest by largest fractional remainder.
  const remaining = n - used;
  const byRem = [...alloc].sort((a, b) => (b.exact - b.count) - (a.exact - a.count));
  for (let i = 0; i < remaining; i++) byRem[i % byRem.length].count += 1;

  // Round-robin flatten so tiers interleave across the ramp.
  const pools = alloc.map((a) => ({ tier: a.tier, left: a.count }));
  const out = [];
  while (out.length < n) {
    for (const p of pools) {
      if (p.left > 0 && out.length < n) { out.push(p.tier); p.left -= 1; }
    }
  }
  return out;
}

/** Weighted-random hotspot pick, with a small jitter so trips aren't identical. */
export function pickHotspot(exclude) {
  let pool = ACTIVE;
  if (exclude) pool = ACTIVE.filter((h) => h.name !== exclude.name);
  const w = pool.reduce((a, h) => a + h.weight, 0);
  let r = Math.random() * w;
  for (const h of pool) {
    r -= h.weight;
    if (r <= 0) return jitter(h);
  }
  return jitter(pool[pool.length - 1]);
}

/** Pick a distinct origin/destination pair. */
export function pickTrip() {
  const origin = pickWeighted();
  const dest = pickHotspot(origin.__spot);
  return { origin, dest };
}

function pickWeighted() {
  const w = ACTIVE.reduce((a, h) => a + h.weight, 0);
  let r = Math.random() * w;
  for (const h of ACTIVE) {
    r -= h.weight;
    if (r <= 0) return jitter(h);
  }
  return jitter(ACTIVE[0]);
}

function jitter(spot) {
  // ~±150m of positional noise so pickups aren't all the exact same coordinate.
  const p = {
    lat: spot.lat + (Math.random() - 0.5) * 0.003,
    lng: spot.lng + (Math.random() - 0.5) * 0.003,
    __spot: spot,
  };
  return p;
}

export function haversineMeters(a, b) {
  const R = 6371000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** Compass bearing a→b in degrees [0,360). */
export function bearing(a, b) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLng = toRad(b.lng - a.lng);
  const y = Math.sin(dLng) * Math.cos(toRad(b.lat));
  const x =
    Math.cos(toRad(a.lat)) * Math.sin(toRad(b.lat)) -
    Math.sin(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.cos(dLng);
  return (((Math.atan2(y, x) * 180) / Math.PI) + 360) % 360;
}

/**
 * Fetch a road-following route from OSRM as an ordered list of {lat,lng} points
 * plus distance/duration. Falls back to a straight 2-point line if OSRM is
 * unavailable, so the engine still runs without the routing stack.
 */
export async function route(from, to) {
  if (!OSRM) return straightLine(from, to);
  const url =
    `${OSRM}/route/v1/driving/${from.lng},${from.lat};${to.lng},${to.lat}` +
    `?overview=full&geometries=geojson`;
  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(8000) });
    if (!res.ok) return straightLine(from, to);
    const data = await res.json();
    const r = data.routes && data.routes[0];
    if (!r) return straightLine(from, to);
    const points = r.geometry.coordinates.map(([lng, lat]) => ({ lat, lng }));
    return { points, distanceM: Math.round(r.distance), durationS: Math.round(r.duration) };
  } catch {
    return straightLine(from, to);
  }
}

function straightLine(from, to) {
  const d = haversineMeters(from, to);
  return { points: [{ lat: from.lat, lng: from.lng }, { lat: to.lat, lng: to.lng }], distanceM: Math.round(d), durationS: Math.round(d / 10) };
}

/**
 * Walk a route at `speedMps` (advanced `timeScale`x per real tick), invoking
 * `onTick({lat,lng,heading})` at each `tickMs`. Resolves when the end is
 * reached. Emits realistic road-following positions with turn-following bearing.
 */
export async function drive(points, { speedMps, tickMs, timeScale, onTick, shouldStop }) {
  if (points.length < 2) {
    await onTick({ ...points[0], heading: 0 });
    return;
  }
  let seg = 0;
  let along = 0; // meters progressed into the current segment
  let heading = bearing(points[0], points[1]);
  const stepMeters = speedMps * (tickMs / 1000) * timeScale;

  for (;;) {
    if (shouldStop && shouldStop()) return;
    const a = points[seg];
    const b = points[seg + 1];
    const segLen = haversineMeters(a, b) || 0.0001;
    along += stepMeters;
    while (along >= segLen) {
      along -= segLen;
      seg += 1;
      if (seg >= points.length - 1) {
        await onTick({ ...points[points.length - 1], heading });
        return;
      }
      heading = bearing(points[seg], points[seg + 1]);
    }
    const frac = along / (haversineMeters(points[seg], points[seg + 1]) || 0.0001);
    const cur = {
      lat: points[seg].lat + (points[seg + 1].lat - points[seg].lat) * frac,
      lng: points[seg].lng + (points[seg + 1].lng - points[seg].lng) * frac,
      heading,
    };
    await onTick(cur);
    await new Promise((r) => setTimeout(r, tickMs));
  }
}
