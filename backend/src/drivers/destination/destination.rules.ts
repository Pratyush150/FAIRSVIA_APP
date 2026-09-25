import { haversineMeters } from '../../geo/geo.util';

/**
 * Destination ("go home") mode — the matching rule.
 *
 * While a driver has a destination set, dispatch only offers them a trip when
 * BOTH hold:
 *   1. The pickup is inside the normal dispatch radius. This is not re-checked
 *      here: the sweep's GEO ring search already only returns drivers within
 *      the current radius of the pickup, exactly as for every other driver.
 *   2. The drop-off brings the driver meaningfully closer to the destination:
 *        dist(dropoff, destination) <= CLOSER_RATIO × dist(driver, destination)
 *      with CLOSER_RATIO = 0.7, i.e. after the trip the driver has covered at
 *      least 30 % of the straight-line distance still left to go home.
 *
 * Distances are great-circle (haversine) — cheap on the hot path, no routing
 * call per candidate. The mode switches itself off when the driver is within
 * ARRIVED_RADIUS_M of the destination or MAX_ACTIVE_MS after it was set.
 */
export const DESTINATION_CLOSER_RATIO = 0.7;
export const DESTINATION_ARRIVED_RADIUS_M = 500;
export const DESTINATION_MAX_ACTIVE_MS = 2 * 3600_000;
export const DESTINATION_DEFAULT_USES_PER_DAY = 2;

export interface Point {
  lat: number;
  lng: number;
}

/** True when a trip ending at [dropoff] takes a driver at [driver] meaningfully
 *  closer to [destination] (rule 2 above). */
export function bringsCloser(driver: Point, dropoff: Point, destination: Point): boolean {
  const now = haversineMeters(driver, destination);
  const after = haversineMeters(dropoff, destination);
  return after <= DESTINATION_CLOSER_RATIO * now;
}

/** Why an active destination should end now, or null to keep it. */
export function autoOffReason(
  startedAt: number,
  nowMs: number,
  driver: Point | null,
  destination: Point,
): 'expired' | 'arrived' | null {
  if (nowMs - startedAt >= DESTINATION_MAX_ACTIVE_MS) return 'expired';
  if (driver && haversineMeters(driver, destination) <= DESTINATION_ARRIVED_RADIUS_M) {
    return 'arrived';
  }
  return null;
}
