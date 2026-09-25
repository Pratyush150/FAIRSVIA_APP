import { Injectable, Logger, OnApplicationBootstrap, OnModuleDestroy } from '@nestjs/common';
import { RedisService } from '../../common/redis/redis.service';
import { RealtimeService } from '../../realtime/realtime.service';
import { NotificationsService } from '../../notifications/notifications.service';
import { DriversService } from '../drivers.service';
import { FatigueService } from './fatigue.service';
import { FatigueKeys, fatigueConfig, fatigueState } from './fatigue.rules';

/**
 * Every DRIVER_FATIGUE_SWEEP_SEC (30 s) walks the drivers with an open online
 * session and:
 *  - over the limit → takes them offline (forceOffline no-ops mid-trip, so
 *    this lands on the first tick after the trip ends; dispatch already
 *    stops offering meanwhile) and pushes "time to rest";
 *  - inside the warning window → one `driver:fatigue_warning` + push;
 *  - every DRIVER_BREAK_REMINDER_HOURS of one session → a non-blocking
 *    `driver:break_reminder`.
 * A short Redis lock keeps two backend nodes from double-sending.
 */
@Injectable()
export class FatigueSweeper implements OnApplicationBootstrap, OnModuleDestroy {
  private readonly logger = new Logger('FatigueSweeper');
  private timer?: NodeJS.Timeout;

  constructor(
    private readonly redis: RedisService,
    private readonly fatigue: FatigueService,
    private readonly drivers: DriversService,
    private readonly realtime: RealtimeService,
    private readonly notifications: NotificationsService,
  ) {}

  onApplicationBootstrap(): void {
    this.timer = setInterval(
      () => void this.tick().catch(() => undefined),
      fatigueConfig.sweepEveryMs(),
    );
    this.timer.unref();
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }

  /** One pass. Public for tests; returns what it did per driver. */
  async tick(now = Date.now(), useLock = true): Promise<Record<string, string>> {
    const done: Record<string, string> = {};
    if (useLock) {
      const got = await this.redis.client.set(
        FatigueKeys.sweepLock(),
        '1',
        'PX',
        Math.max(1000, fatigueConfig.sweepEveryMs() - 500),
        'NX',
      );
      if (got !== 'OK') return done;
    }
    for (const id of await this.fatigue.tracked()) {
      try {
        done[id] = await this.checkOne(id, now);
      } catch (e) {
        this.logger.warn(`fatigue check failed for ${id}: ${e}`);
      }
    }
    return done;
  }

  private async checkOne(id: string, now: number): Promise<string> {
    const raw = await this.fatigue.raw(id);
    if (!raw.onlineSince) {
      await this.redis.client.srem(FatigueKeys.fatigueTracked(), id);
      return 'untracked';
    }
    const s = fatigueState(raw, now);
    if (s.overLimit) {
      const flipped = await this.drivers.forceOffline(id, null, 'fatigue');
      if (!flipped) return 'over_limit_on_trip';
      const after = await this.fatigue.state(id, Date.now());
      this.realtime.emitToUser(id, 'driver:fatigue_locked', after);
      void this.notifications
        .notify(id, {
          title: 'Time to rest',
          body: `You've been online ${fmt(s.onlineSeconds)}. Take a ${fmt(s.restBreakSeconds)} break before your next ride.`,
          data: { kind: 'fatigue_locked' },
        })
        .catch(() => undefined);
      return 'forced_offline';
    }
    let action = 'ok';
    if (!raw.warned && s.onlineSeconds >= s.warnAtSeconds) {
      await this.fatigue.markWarned(id);
      this.realtime.emitToUser(id, 'driver:fatigue_warning', s);
      void this.notifications
        .notify(id, {
          title: 'Almost at your driving limit',
          body: `${fmt(s.remainingSeconds)} left before a required ${fmt(s.restBreakSeconds)} rest.`,
          data: { kind: 'fatigue_warning' },
        })
        .catch(() => undefined);
      action = 'warned';
    }
    const session = Math.max(0, Math.round((now - raw.onlineSince) / 1000));
    const n = Math.floor(session / fatigueConfig.reminderEverySecs());
    const sent = raw.remindSince === raw.onlineSince ? raw.remindN : 0;
    if (n > sent) {
      await this.fatigue.markReminded(id, raw.onlineSince, n);
      this.realtime.emitToUser(id, 'driver:break_reminder', { sessionSeconds: session, ...s });
      action = action === 'warned' ? 'warned+reminded' : 'reminded';
    }
    return action;
  }
}

function fmt(secs: number): string {
  const h = Math.floor(secs / 3600);
  const m = Math.floor((secs % 3600) / 60);
  return h > 0 ? (m > 0 ? `${h} h ${m} min` : `${h} h`) : `${m} min`;
}
