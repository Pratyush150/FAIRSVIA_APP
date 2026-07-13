import { Inject, Injectable, Logger } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';
import { PrismaService } from '../common/prisma/prisma.service';
import {
  PUSH_PROVIDER,
  PushMessage,
  PushProvider,
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
  | 'no_drivers';

const TRIP_COPY: Record<TripNotificationKind, PushMessage> = {
  accepted: { title: 'Driver on the way', body: 'Your driver is heading to the pickup.' },
  arrived: { title: 'Your driver has arrived', body: 'Head to the pickup point.' },
  started: { title: 'Trip started', body: 'Enjoy your ride.' },
  completed: { title: 'Trip completed', body: 'Thanks for riding. Rate your driver.' },
  cancelled: { title: 'Trip cancelled', body: 'This trip was cancelled.' },
  no_drivers: { title: 'No drivers available', body: 'We couldn’t find a driver nearby.' },
};

@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(PUSH_PROVIDER) private readonly provider: PushProvider,
    @InjectQueue(QUEUE_NOTIFICATIONS) private readonly queue: Queue,
  ) {}

  /** Register (or refresh) a device's push token. */
  async register(userId: string, token: string, platform = 'android') {
    await this.prisma.deviceToken.upsert({
      where: { token },
      create: { userId, token, platform },
      update: { userId, platform },
    });
    return { ok: true };
  }

  async unregister(token: string) {
    await this.prisma.deviceToken
      .delete({ where: { token } })
      .catch(() => undefined);
    return { ok: true };
  }

  /**
   * Enqueue a push to every device a user has registered. Durable: the actual
   * send happens in the worker ([deliver]) with retries, so a transient
   * provider failure or a backend restart doesn't drop the notification.
   */
  async notify(userId: string, message: PushMessage): Promise<void> {
    await this.queue.add(NOTIFY_JOB, { userId, message }, DEFAULT_JOB_OPTS);
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
    await Promise.all(
      targets.map((t) =>
        this.provider.send({ token: t.token, platform: t.platform }, message),
      ),
    );
  }

  /** Convenience: push the canonical copy for a trip milestone. */
  async notifyTrip(
    userId: string,
    kind: TripNotificationKind,
    data: Record<string, string> = {},
  ): Promise<void> {
    const base = TRIP_COPY[kind];
    await this.notify(userId, { ...base, data: { kind, ...data } });
  }
}
