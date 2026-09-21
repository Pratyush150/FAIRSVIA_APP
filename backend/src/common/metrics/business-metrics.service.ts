import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { JobType, Queue } from 'bullmq';
import { TripStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { MetricsService } from './metrics.service';
import { QUEUE_DISPATCH, QUEUE_NOTIFICATIONS } from '../queue/queue.constants';

/** Trip statuses that count as "in flight" right now. */
const ACTIVE_STATUSES: TripStatus[] = [
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
];

/**
 * Fills the point-in-time gauges — queue depth, online drivers, active trips —
 * **at scrape time**, using prom-client's per-gauge `collect()` hook.
 *
 * Scrape-time collection rather than a background timer, deliberately: the cost
 * is paid once per scrape (15s) instead of continuously, the value is never
 * stale by up to a tick, and nothing keeps running when nothing is watching.
 *
 * Every collector is wrapped so a failing query leaves the previous value in
 * place rather than blowing up the whole `/metrics` response — losing one gauge
 * is much better than losing all of them plus the default process metrics.
 */
@Injectable()
export class BusinessMetricsService implements OnModuleInit {
  private readonly logger = new Logger(BusinessMetricsService.name);

  constructor(
    private readonly metrics: MetricsService,
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    @InjectQueue(QUEUE_DISPATCH) private readonly dispatchQueue: Queue,
    @InjectQueue(QUEUE_NOTIFICATIONS) private readonly notificationsQueue: Queue,
  ) {}

  onModuleInit(): void {
    this.metrics.setCollector('dispatch_queue_depth', () =>
      this.guard('dispatch_queue_depth', () => this.collectQueues()),
    );
    this.metrics.setCollector('drivers_online', () =>
      this.guard('drivers_online', () => this.collectDrivers()),
    );
    this.metrics.setCollector('active_trips', () =>
      this.guard('active_trips', () => this.collectActiveTrips()),
    );
  }

  private async guard(name: string, fn: () => Promise<void>): Promise<void> {
    try {
      await fn();
    } catch (e) {
      this.logger.warn(`metric ${name} could not be collected: ${String(e)}`);
    }
  }

  /**
   * Depth of both durable queues, per state. `waiting` on the dispatch queue is
   * the single highest-value number here: the load sweep showed backlog builds
   * there first, before anything a rider can see goes wrong.
   */
  private async collectQueues(): Promise<void> {
    const states: JobType[] = [
      'waiting',
      'active',
      'completed',
      'failed',
      'delayed',
    ];
    const [dispatch, notifications] = await Promise.all([
      this.dispatchQueue.getJobCounts(...states),
      this.notificationsQueue.getJobCounts(...states),
    ]);
    const g = this.metrics.dispatchQueueDepth;
    g.reset();
    for (const [state, count] of Object.entries(dispatch)) {
      g.set({ queue: QUEUE_DISPATCH, state }, Number(count) || 0);
    }
    for (const [state, count] of Object.entries(notifications)) {
      g.set({ queue: QUEUE_NOTIFICATIONS, state }, Number(count) || 0);
    }
  }

  /**
   * Online drivers per tier, from the same Redis status keys the admin live
   * view uses — including drivers already on a trip, who are online supply
   * even though dispatch has taken them out of the pool.
   */
  private async collectDrivers(): Promise<void> {
    const g = this.metrics.driversOnline;
    g.reset();
    const statusKeys = await this.redis.client.keys('driver:*:status');
    if (statusKeys.length === 0) return;
    const statuses = await this.redis.client.mget(...statusKeys);

    const onlineIds: string[] = [];
    for (let i = 0; i < statusKeys.length; i++) {
      const status = statuses[i];
      if (!status || status === 'offline') continue;
      // key shape: driver:{id}:status
      const id = statusKeys[i].split(':')[1];
      if (id) onlineIds.push(id);
    }
    if (onlineIds.length === 0) return;

    const tiers = await this.redis.client.mget(
      ...onlineIds.map((id) => `driver:${id}:tier`),
    );
    const byTier = new Map<string, number>();
    for (const tier of tiers) {
      // A driver online with no tier key is still supply; bucket them rather
      // than dropping them, so the total always matches the live view.
      const key = tier ?? 'unknown';
      byTier.set(key, (byTier.get(key) ?? 0) + 1);
    }
    for (const [tier, count] of byTier) g.set({ tier }, count);
  }

  private async collectActiveTrips(): Promise<void> {
    const count = await this.prisma.trip.count({
      where: { status: { in: ACTIVE_STATUSES } },
    });
    this.metrics.activeTrips.set(count);
  }
}
