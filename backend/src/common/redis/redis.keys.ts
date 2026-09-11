/** Centralized Redis key builders for the hot path (spec §7.2). */
export const RedisKeys = {
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
  // Surge: per-cell recent demand counter + an admin global override.
  surgeDemand: (cell: string) => `surge:demand:${cell}`,
  surgeOverride: () => 'surge:override',
  driverOfferLock: (id: string) => `driver:${id}:offerlock`,
  // Cross-process offer signalling: the dispatch worker records who a trip is
  // currently offered to, and a driver's accept/decline lands here so the
  // worker (on any node) picks it up.
  dispatchOffer: (tripId: string) => `dispatch:offer:${tripId}`,
  dispatchResponse: (tripId: string) => `dispatch:resp:${tripId}`,
} as const;
