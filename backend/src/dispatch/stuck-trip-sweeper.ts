import { Injectable, Logger, OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { DispatchService, searchWindowMs } from './dispatch.service';

/**
 * A search runs SEARCH_WINDOW_SEC (180 s by default); anything still searching
 * well past that was orphaned. At least 10 min, and always 5 min beyond the
 * configured window so a live search is never cut short.
 */
export function stuckAfterMs(): number {
  return Math.max(10 * 60_000, searchWindowMs() + 5 * 60_000);
}
const SWEEP_EVERY_MS = 60_000;
const LOCK_KEY = 'dispatch:stuck-sweeper:lock';

/**
 * Ends ride searches that nothing is running any more.
 *
 * A search lives in a BullMQ job. If that job is lost — a crash at the wrong
 * moment, a queue flushed by hand — the trip stays REQUESTED/MATCHING for
 * ever: the rider stares at "finding a driver", and can never book again,
 * because booking refuses a second ride while one is in flight. This sweeps
 * such trips to no_drivers (or expired, if the search never began) through the
 * normal path, so the rider is told and can book again.
 *
 * Leaves alone: rides parked on purpose by the ops dispatch pause, scheduled
 * rides (their own lifecycle), and anything younger than stuckAfterMs() —
 * far beyond a live search's window.
 */
@Injectable()
export class StuckTripSweeper implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger('StuckTripSweeper');
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly dispatch: DispatchService,
  ) {}

  onApplicationBootstrap(): void {
    this.timer = setInterval(() => void this.sweep().catch(() => undefined), SWEEP_EVERY_MS);
    this.timer.unref(); // never the reason a process stays up
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  /** One pass. Returns how many trips it ended. */
  async sweep(now: Date = new Date()): Promise<number> {
    // One instance sweeps at a time; the lock outlives a slow pass.
    const locked = await this.redis.client.set(LOCK_KEY, '1', 'PX', SWEEP_EVERY_MS - 5_000, 'NX');
    if (locked !== 'OK') return 0;

    const cutoff = new Date(now.getTime() - stuckAfterMs());
    const [stuck, deferred] = await Promise.all([
      this.prisma.trip.findMany({
        where: {
          status: { in: [TripStatus.requested, TripStatus.matching] },
          requestedAt: { lt: cutoff },
        },
        select: { id: true, riderId: true, pickupLat: true, pickupLng: true, status: true },
        take: 200,
      }),
      this.dispatch.deferredIds(),
    ]);
    let ended = 0;
    for (const trip of stuck) {
      if (deferred.has(trip.id)) continue;
      if (await this.dispatch.declareNoDrivers(trip, trip.status)) ended += 1;
    }
    if (ended > 0) this.logger.warn(`ended ${ended} orphaned ride search(es)`);
    return ended;
  }
}
