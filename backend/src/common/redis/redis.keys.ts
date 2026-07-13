/** Centralized Redis key builders for the hot path (spec §7.2). */
export const RedisKeys = {
  driversGeo: (tier: string) => `drivers:geo:${tier}`,
  driverStatus: (id: string) => `driver:${id}:status`,
  driverLoc: (id: string) => `driver:${id}:loc`,
  driverTier: (id: string) => `driver:${id}:tier`,
  driverActiveTrip: (id: string) => `driver:${id}:activeTrip`,
  driverActiveRider: (id: string) => `driver:${id}:activeRider`,
  tripLock: (id: string) => `trip:${id}:lock`,
} as const;
