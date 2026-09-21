/** Centralized Redis key builders for the hot path (spec §7.2). */
export const RedisKeys = {
  // Trips whose dispatch was skipped because an operator paused matching.
  // Re-dispatched when the pause is lifted, so pausing defers work rather
  // than stranding riders.
  dispatchDeferred: () => 'dispatch:deferred',
  driversGeo: (tier: string) => `drivers:geo:${tier}`,
  driverStatus: (id: string) => `driver:${id}:status`,
  driverLoc: (id: string) => `driver:${id}:loc`,
  driverTier: (id: string) => `driver:${id}:tier`,
  driverActiveTrip: (id: string) => `driver:${id}:activeTrip`,
  driverActiveRider: (id: string) => `driver:${id}:activeRider`,
  tripLock: (id: string) => `trip:${id}:lock`,
  // Trip odometer: accumulated driven meters (present only while in_progress)
  // and the last metered GPS point, used to recompute the final fare.
  tripDriven: (id: string) => `trip:${id}:driven`,
  tripMeterLast: (id: string) => `trip:${id}:meterLast`,
  // In-trip chat: a capped list of messages, TTL'd after the ride.
  tripChat: (id: string) => `trip:${id}:chat`,
  // Per-user chat send-rate window counter.
  chatRate: (userId: string) => `chat:rate:${userId}`,
  // Surge: per-cell SET of riders with a recent live request (each rider
  // counts once per cell window, however many times they retry) + an admin
  // global override.
  surgeDemand: (cell: string) => `surge:demand:${cell}`,
  // Navigation context for the driver's current leg (target + polyline +
  // routed average speed) so each GPS ping can derive a cheap ETA without a
  // DB read or a routing call. Written at assignment (approach leg) and at
  // trip start (trip leg); removed when the trip ends.
  tripNav: (id: string) => `trip:${id}:nav`,
  // Per-trip watchdog state for the rider-facing alerts LocationService raises
  // off the GPS stream: the last point the driver actually moved from, and
  // once-per-episode flags so a deviation or a long stop pops one alert, not
  // one per ping. TTL'd, and deleted with the rest of the trip's hot keys.
  tripWatch: (id: string) => `trip:${id}:watch`,
  surgeOverride: () => 'surge:override',
  driverOfferLock: (id: string) => `driver:${id}:offerlock`,
  // Cross-process offer signalling: the dispatch worker records who a trip is
  // currently offered to, and a driver's accept/decline lands here so the
  // worker (on any node) picks it up.
  dispatchOffer: (tripId: string) => `dispatch:offer:${tripId}`,
  dispatchResponse: (tripId: string) => `dispatch:resp:${tripId}`,
  // Drivers who explicitly declined this trip: never re-offered on a later
  // sweep of the same dispatch run.
  dispatchDeclined: (tripId: string) => `dispatch:declined:${tripId}`,
} as const;
