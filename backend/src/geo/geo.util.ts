import { LatLng } from './geo-provider.interface';

/** Great-circle distance in meters between two coordinates. */
export function haversineMeters(a: LatLng, b: LatLng): number {
  const r = 6371000; // Earth radius (m)
  const toRad = (d: number) => (d * Math.PI) / 180;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * r * Math.asin(Math.sqrt(h));
}

/** Encode a list of points into a Google-encoded polyline string. */
export function encodePolyline(points: LatLng[]): string {
  let result = '';
  let prevLat = 0;
  let prevLng = 0;
  for (const p of points) {
    const lat = Math.round(p.lat * 1e5);
    const lng = Math.round(p.lng * 1e5);
    result += encodeSignedValue(lat - prevLat);
    result += encodeSignedValue(lng - prevLng);
    prevLat = lat;
    prevLng = lng;
  }
  return result;
}

function encodeSignedValue(value: number): string {
  let v = value < 0 ? ~(value << 1) : value << 1;
  let out = '';
  while (v >= 0x20) {
    out += String.fromCharCode((0x20 | (v & 0x1f)) + 63);
    v >>= 5;
  }
  out += String.fromCharCode(v + 63);
  return out;
}

/** Decode a Google-encoded polyline (precision 5) into points. */
export function decodePolyline(encoded: string): LatLng[] {
  const points: LatLng[] = [];
  let index = 0;
  let lat = 0;
  let lng = 0;
  while (index < encoded.length) {
    let shift = 0;
    let result = 0;
    let b: number;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lat += result & 1 ? ~(result >> 1) : result >> 1;
    shift = 0;
    result = 0;
    do {
      b = encoded.charCodeAt(index++) - 63;
      result |= (b & 0x1f) << shift;
      shift += 5;
    } while (b >= 0x20 && index < encoded.length);
    lng += result & 1 ? ~(result >> 1) : result >> 1;
    points.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return points;
}

/** Where a point sits relative to a route. */
export interface PolylineProjection {
  /** Metres left to travel along the route from the nearest point on it. */
  remainingM: number;
  /** Perpendicular distance from the route to the point (metres). */
  offsetM: number;
}

/**
 * Project `pos` onto `route`. Snaps to the closest segment (planar projection
 * — fine at city scale) and reports both how far is left along the route from
 * there and how far off the route the point itself is. Returns null for a
 * route with fewer than two points.
 */
export function projectOntoPolyline(
  pos: LatLng,
  route: LatLng[],
): PolylineProjection | null {
  if (route.length < 2) return null;
  // Local equirectangular frame (metres) centred on the query point.
  const cosLat = Math.cos((pos.lat * Math.PI) / 180);
  const mPerDegLat = 111320;
  const toXY = (p: LatLng) => ({
    x: (p.lng - pos.lng) * mPerDegLat * cosLat,
    y: (p.lat - pos.lat) * mPerDegLat,
  });
  const xy = route.map(toXY);
  // Suffix sums: metres from vertex i to the end.
  const suffix = new Array<number>(route.length).fill(0);
  for (let i = route.length - 2; i >= 0; i--) {
    suffix[i] = suffix[i + 1] + haversineMeters(route[i], route[i + 1]);
  }
  let best = Infinity;
  let remaining = suffix[0];
  for (let i = 0; i < xy.length - 1; i++) {
    const a = xy[i];
    const b = xy[i + 1];
    const dx = b.x - a.x;
    const dy = b.y - a.y;
    const len2 = dx * dx + dy * dy;
    // Fraction along the segment of the projection of the origin (pos).
    const t = len2 === 0 ? 0 : Math.min(1, Math.max(0, -(a.x * dx + a.y * dy) / len2));
    const px = a.x + t * dx;
    const py = a.y + t * dy;
    const d = Math.hypot(px, py);
    if (d < best) {
      best = d;
      const segLen = Math.sqrt(len2);
      remaining = (1 - t) * segLen + suffix[i + 1];
    }
  }
  return { remainingM: Math.round(remaining), offsetM: Math.round(best) };
}

/**
 * Metres left to travel along a route from the point on it nearest to `pos`.
 * Thin wrapper over [projectOntoPolyline] for callers that only need the
 * remainder.
 */
export function remainingAlongPolyline(pos: LatLng, route: LatLng[]): number | null {
  return projectOntoPolyline(pos, route)?.remainingM ?? null;
}
