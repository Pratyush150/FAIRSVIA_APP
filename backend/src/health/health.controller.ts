import { Controller, Get, HttpStatus, Res } from '@nestjs/common';
import type { Response } from 'express';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';

/**
 * Two probes, deliberately different.
 *
 * **Liveness** (`/health/live`) answers "is this process alive" and checks
 * nothing downstream. Wiring dependency checks into liveness is a classic
 * self-inflicted outage: the database blips, every replica fails its liveness
 * probe at once, and the orchestrator restarts the entire fleet — turning a
 * recoverable blip into a cold start.
 *
 * **Readiness** (`/health/ready`, and `/health` for existing probes) answers
 * "can this instance serve traffic" and returns **503** when it cannot, so a
 * load balancer takes it out of rotation. This used to return 200 with
 * `status: "degraded"` in the body — and since probes read status codes, not
 * bodies, a backend with a dead database happily stayed in the pool.
 */
@Controller('health')
export class HealthController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  /** Liveness: no dependency checks, by design. */
  @Get('live')
  live() {
    return { status: 'ok', timestamp: new Date().toISOString() };
  }

  /** Readiness: 200 when every dependency answers, 503 otherwise. */
  @Get('ready')
  async ready(@Res() res: Response): Promise<void> {
    await this.respondWithReadiness(res);
  }

  /**
   * The original probe path. Kept — nginx, the compose healthchecks and CI all
   * point at it — but it now reports readiness *with the matching status code*.
   * The body shape is unchanged so existing checks that grep for
   * `"status":"ok"` keep working.
   */
  @Get()
  async check(@Res() res: Response): Promise<void> {
    await this.respondWithReadiness(res);
  }

  private async respondWithReadiness(res: Response): Promise<void> {
    const [db, redis] = await Promise.all([this.checkDb(), this.checkRedis()]);
    const ok = db && redis;
    res.status(ok ? HttpStatus.OK : HttpStatus.SERVICE_UNAVAILABLE).json({
      status: ok ? 'ok' : 'degraded',
      services: { database: db ? 'up' : 'down', redis: redis ? 'up' : 'down' },
      timestamp: new Date().toISOString(),
    });
  }

  private async checkDb(): Promise<boolean> {
    try {
      await this.prisma.$queryRaw`SELECT 1`;
      return true;
    } catch {
      return false;
    }
  }

  private async checkRedis(): Promise<boolean> {
    try {
      return (await this.redis.client.ping()) === 'PONG';
    } catch {
      return false;
    }
  }
}
