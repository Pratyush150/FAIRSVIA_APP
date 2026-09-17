import { ConflictException, Inject, Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  PUSH_PROVIDER,
  PushMessage,
  PushProvider,
  isStalePushToken,
} from './push-provider.interface';
import {
  QUEUE_NOTIFICATIONS,
  NOTIFY_JOB,
  DEFAULT_JOB_OPTS,
} from '../common/queue/queue.constants';

/** The trip milestones we push a notification for, with their copy. */
export type TripNotificationKind =
  | 'accepted'
  | 'arrived'
  | 'started'
  | 'completed'
  | 'cancelled'
  | 'no_drivers'
  | 'scheduled_started'
  | 'off_route'
  | 'driver_stopped';

/** Rider-facing copy per milestone. */
const TRIP_COPY: Record<TripNotificationKind, PushMessage> = {
  accepted: { title: 'Driver on the way', body: 'Your driver is heading to the pickup.' },
  arrived: { title: 'Your driver has arrived', body: 'Head to the pickup point.' },
  started: { title: 'Trip started', body: 'Enjoy your ride.' },
  completed: { title: 'Trip completed', body: 'Thanks for riding. Rate your driver.' },
  cancelled: { title: 'Trip cancelled', body: 'This trip was cancelled.' },
  no_drivers: { title: 'No drivers available', body: 'We couldn’t find a driver nearby.' },
  scheduled_started: {
    title: 'Finding your driver',
    body: 'Your scheduled ride is now being matched.',
  },
  // Raised by the GPS watchdogs (LocationService), so a rider who isn't
  // staring at the map still learns the ride stopped following the route or
  // stopped moving. Worded as information, not an accusation — there are
  // plenty of innocent reasons for both.
  off_route: {
    title: 'Your driver left the route',
    body: 'The route was updated. Tap to see where your driver is.',
  },
  driver_stopped: {
    title: 'Your driver has stopped',
    body: 'Your driver has not moved for a few minutes.',
  },
};

/**
 * Driver-facing copy where it differs from the rider's. The driver used to
 * get the rider's line on completion ("Thanks for riding. Rate your driver.").
 * `earned` (formatted amount, e.g. "12.50") comes from the trip data.
 */
const DRIVER_TRIP_COPY: Partial<
  Record<TripNotificationKind, (data: Record<string, string>) => PushMessage>
> = {
  completed: (d) => ({
    title: 'Trip complete',
    body: d.earned
      ? `Trip complete — you earned $${d.earned}. Rate your rider.`
      : 'Trip complete. Rate your rider.',
  }),
  cancelled: () => ({
    title: 'Trip cancelled',
    body: 'The rider cancelled this trip. You’re back in the queue.',
  }),
};

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(PUSH_PROVIDER) private readonly provider: PushProvider,
    @InjectQueue(QUEUE_NOTIFICATIONS) private readonly queue: Queue,
  ) {}

  /** Register (or refresh) a device's push token. A token already registered
   *  to a *different* user is rejected (409): otherwise anyone who learned a
   *  token could redirect that device's pushes to themselves. The previous
   *  owner must unregister (sign-out) before the device can be claimed. */
  async register(userId: string, token: string, platform = 'android') {
    const existing = await this.prisma.deviceToken.findUnique({
      where: { token },
      select: { userId: true },
    });
    if (existing && existing.userId !== userId) {
      throw new ConflictException('Device token is registered to another account');
    }
    await this.prisma.deviceToken.upsert({
      where: { token },
      create: { userId, token, platform },
      update: { platform },
    });
    return { ok: true };
  }

  /** Remove a push token, scoped to its owner so one user can't unregister
   *  another user's device (push-notification denial of service). */
  async unregister(userId: string, token: string) {
    await this.prisma.deviceToken
      .deleteMany({ where: { token, userId } })
      .catch(() => undefined);
    return { ok: true };
  }

  /**
   * Enqueue a push to every device a user has registered. Durable: the actual
   * send happens in the worker ([deliver]) with retries, so a transient
   * provider failure or a backend restart doesn't drop the notification.
   */
  async notify(userId: string, message: PushMessage): Promise<void> {
    // Persist to the in-app inbox (best-effort — never block the push on it),
    // then enqueue the durable push fan-out.
    await this.prisma.notification
      .create({
        data: {
          userId,
          title: message.title,
          body: message.body,
          kind: message.data?.kind ?? null,
          data: message.data ?? undefined,
        },
      })
      .catch((e) => this.logger.warn(`inbox persist failed: ${e}`));
    // Guard the enqueue itself so a Redis/queue outage can't surface as an
    // unhandled promise rejection in the fire-and-forget (`void notifyTrip`)
    // callers — which would crash the process on modern Node defaults.
    await this.queue
      .add(NOTIFY_JOB, { userId, message }, DEFAULT_JOB_OPTS)
      .catch((e) => this.logger.warn(`push enqueue failed: ${e}`));
  }

  // --- In-app inbox ---

  /** The user's notifications, newest first. */
  async listInbox(userId: string, take = 50) {
    const rows = await this.prisma.notification.findMany({
      where: { userId },
      orderBy: { createdAt: 'desc' },
      take,
    });
    return rows.map((n) => ({
      id: n.id,
      title: n.title,
      body: n.body,
      kind: n.kind,
      data: n.data,
      read: n.readAt != null,
      createdAt: n.createdAt,
    }));
  }

  /** Count of unread notifications (for the badge). */
  async unreadCount(userId: string): Promise<{ unread: number }> {
    const unread = await this.prisma.notification.count({
      where: { userId, readAt: null },
    });
    return { unread };
  }

  /** Mark one notification read (only the owner's). */
  async markRead(userId: string, id: string) {
    await this.prisma.notification.updateMany({
      where: { id, userId, readAt: null },
      data: { readAt: new Date() },
    });
    return { ok: true };
  }

  /** Mark all of the user's notifications read. */
  async markAllRead(userId: string) {
    const res = await this.prisma.notification.updateMany({
      where: { userId, readAt: null },
      data: { readAt: new Date() },
    });
    return { ok: true, marked: res.count };
  }

  /** The actual fan-out send — invoked by the notifications queue worker. */
  async deliver(userId: string, message: PushMessage): Promise<void> {
    const targets = await this.prisma.deviceToken.findMany({
      where: { userId },
    });
    if (targets.length === 0) {
      // No device registered — the socket event still delivers in-app.
      this.logger.debug(`No device tokens for ${userId}; skipping push.`);
      return;
    }
    const results = await Promise.allSettled(
      targets.map((t) =>
        this.provider.send({ token: t.token, platform: t.platform }, message),
      ),
    );

    const stale: string[] = [];
    const transient: string[] = [];
    let delivered = 0;
    results.forEach((r, i) => {
      if (r.status === 'fulfilled') {
        delivered++;
      } else if (isStalePushToken(r.reason)) {
        stale.push(targets[i].token);
      } else {
        transient.push(`${targets[i].token.slice(0, 8)}…: ${r.reason}`);
      }
    });

    // Stale (UNREGISTERED/404) tokens are pruned, never retried.
    if (stale.length > 0) {
      await this.prisma.deviceToken
        .deleteMany({ where: { token: { in: stale } } })
        .catch((e) => this.logger.warn(`token prune failed: ${e}`));
      this.logger.log(`Pruned ${stale.length} stale device token(s) for ${userId}.`);
    }
    if (transient.length > 0) {
      this.logger.warn(
        `push to ${userId}: ${transient.length}/${targets.length} send(s) failed: ${transient.join('; ')}`,
      );
    }
    // Retry (via BullMQ) only when nothing reached the user — a retry re-sends
    // to every device, so retrying after a partial success would duplicate the
    // push on the devices that already got it.
    if (delivered === 0 && transient.length > 0) {
      throw new Error(`push delivery failed for ${userId}: ${transient[0]}`);
    }
  }

  /**
   * Convenience: push the canonical copy for a trip milestone. `audience`
   * selects the driver's wording where it differs (completion / cancel).
   */
  async notifyTrip(
    userId: string,
    kind: TripNotificationKind,
    data: Record<string, string> = {},
    audience: 'rider' | 'driver' = 'rider',
  ): Promise<void> {
    const base =
      audience === 'driver' && DRIVER_TRIP_COPY[kind]
        ? DRIVER_TRIP_COPY[kind]!(data)
        : TRIP_COPY[kind];
    await this.notify(userId, { ...base, data: { kind, ...data } });
  }
}
