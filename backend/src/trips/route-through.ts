import { GeoProvider, LatLng, RouteResult } from '../geo/geo-provider.interface';
import { decodePolyline, encodePolyline } from '../geo/geo.util';

/**
 * Route through ordered points. A direct A→B is the provider's route as-is.
 * With waypoints, each leg is routed and the legs' ROAD geometry is joined —
 * not straight lines between the waypoints, which put every real road path
 * outside the off-route threshold and raised false "driver off route" alerts.
 * A leg with no geometry falls back to a straight segment for that leg only.
 */
export async function routeThrough(
  geo: GeoProvider,
  points: LatLng[],
): Promise<RouteResult> {
  if (points.length === 2) return geo.route(points[0], points[1]);
  let distanceM = 0;
  let durationS = 0;
  const path: LatLng[] = [];
  for (let i = 0; i < points.length - 1; i++) {
    const leg = await geo.route(points[i], points[i + 1]);
    distanceM += leg.distanceM;
    durationS += leg.durationS;
    let legPath: LatLng[] = [];
    try {
      legPath = leg.polyline ? decodePolyline(leg.polyline) : [];
    } catch {
      legPath = [];
    }
    if (legPath.length < 2) legPath = [points[i], points[i + 1]];
    // Consecutive legs share their joint point; keep it once.
    path.push(...(path.length > 0 ? legPath.slice(1) : legPath));
  }
  return { distanceM, durationS, polyline: encodePolyline(path) };
}
