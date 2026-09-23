import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { RedisService } from '../src/common/redis/redis.service';

/**
 * The pilot's public link (Cloudflare tunnel) must not hand out login codes
 * for arbitrary numbers, nor the internal metrics. Cloudflare marks every
 * request it forwards with CF-Connecting-IP.
 */
describe('Public edge (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let redis: RedisService;
  const viaTunnel = { 'CF-Connecting-IP': '203.0.113.9' };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1', {
      exclude: [{ path: 'metrics', method: RequestMethod.GET }],
    });
    app.useGlobalPipes(
      new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }),
    );
    await app.init();
    server = app.getHttpServer();
    redis = app.get(RedisService);
  });

  afterAll(async () => {
    await app.close();
  }, 60_000);

  const ask = async (phone: string, headers: Record<string, string> = {}) => {
    await redis.del(`otp:rate:${phone}`);
    return request(server).post('/api/v1/auth/otp/request').set(headers).send({ phone }).expect(200);
  };

  it('never shows a login code over the public edge for an unlisted number', async () => {
    const res = await ask('+19990001234', viaTunnel);
    expect(res.body.requestId).toEqual(expect.any(String));
    expect(res.body.devCode).toBeUndefined();
  });

  it("the admin's number included", async () => {
    const res = await ask('+19900000001', viaTunnel);
    expect(res.body.devCode).toBeUndefined();
  });

  it("shows it for the pilot's demo accounts, and a demo login works end to end", async () => {
    const res = await ask('+15550000001', viaTunnel);
    expect(res.body.devCode).toMatch(/^\d{6}$/);
    const login = await request(server)
      .post('/api/v1/auth/otp/verify')
      .set(viaTunnel)
      .send({ phone: '+15550000001', code: res.body.devCode })
      .expect(200);
    expect(login.body.accessToken).toEqual(expect.any(String));
  });

  it('on the internal network nothing changes (simulators, tests, admin)', async () => {
    const res = await ask('+19990001234');
    expect(res.body.devCode).toMatch(/^\d{6}$/);
  });

  it('hides /metrics from the public edge but not from Prometheus', async () => {
    await request(server).get('/metrics').set(viaTunnel).expect(404);
    const internal = await request(server).get('/metrics').expect(200);
    expect(internal.text).toContain('http_requests_total');
  });
});
