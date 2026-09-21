import { HttpStatus } from '@nestjs/common';
import type { Response } from 'express';
import { HealthController } from './health.controller';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';

/** Captures what the controller sent, so we can assert on the STATUS CODE —
 *  which is the whole point: probes read codes, not bodies. */
function mockRes() {
  const out: { status?: number; body?: unknown } = {};
  const res = {
    status(code: number) {
      out.status = code;
      return this;
    },
    json(body: unknown) {
      out.body = body;
      return this;
    },
  } as unknown as Response;
  return { res, out };
}

function controller(opts: { db: boolean; redis: boolean }) {
  const prisma = {
    $queryRaw: opts.db
      ? jest.fn().mockResolvedValue([{ '?column?': 1 }])
      : jest.fn().mockRejectedValue(new Error('db down')),
  } as unknown as PrismaService;
  const redis = {
    client: {
      ping: opts.redis
        ? jest.fn().mockResolvedValue('PONG')
        : jest.fn().mockRejectedValue(new Error('redis down')),
    },
  } as unknown as RedisService;
  return new HealthController(prisma, redis);
}

describe('HealthController', () => {
  describe('liveness', () => {
    it('reports ok without touching any dependency', () => {
      // Both dependencies are dead; liveness must not care. Wiring readiness
      // into liveness restarts every replica at once on a database blip.
      const body = controller({ db: false, redis: false }).live();
      expect(body.status).toBe('ok');
    });
  });

  describe('readiness', () => {
    it('returns 200 when everything answers', async () => {
      const { res, out } = mockRes();
      await controller({ db: true, redis: true }).ready(res);
      expect(out.status).toBe(HttpStatus.OK);
      expect(out.body).toMatchObject({
        status: 'ok',
        services: { database: 'up', redis: 'up' },
      });
    });

    it('returns 503 when the database is down', async () => {
      // The regression this file exists for: this used to be a 200 with
      // "degraded" in the body, so a pod with a dead database stayed in the
      // load balancer serving traffic.
      const { res, out } = mockRes();
      await controller({ db: false, redis: true }).ready(res);
      expect(out.status).toBe(HttpStatus.SERVICE_UNAVAILABLE);
      expect(out.body).toMatchObject({
        status: 'degraded',
        services: { database: 'down', redis: 'up' },
      });
    });

    it('returns 503 when redis is down', async () => {
      const { res, out } = mockRes();
      await controller({ db: true, redis: false }).ready(res);
      expect(out.status).toBe(HttpStatus.SERVICE_UNAVAILABLE);
      expect(out.body).toMatchObject({ services: { redis: 'down' } });
    });
  });

  describe('the legacy /health path', () => {
    it('still answers, and now carries the readiness status code', async () => {
      // nginx, the compose healthchecks and CI all point here.
      const okRes = mockRes();
      await controller({ db: true, redis: true }).check(okRes.res);
      expect(okRes.out.status).toBe(HttpStatus.OK);
      expect(okRes.out.body).toMatchObject({ status: 'ok' });

      const badRes = mockRes();
      await controller({ db: false, redis: false }).check(badRes.res);
      expect(badRes.out.status).toBe(HttpStatus.SERVICE_UNAVAILABLE);
    });
  });
});
