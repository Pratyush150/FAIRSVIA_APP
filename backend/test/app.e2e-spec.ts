import { INestApplication, ValidationPipe, RequestMethod } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { RedisService } from '../src/common/redis/redis.service';

/**
 * Full-stack e2e against the real Postgres + Redis (run inside the backend
 * container). Exercises the auth + trip flow through the HTTP layer.
 */
describe('UberNav API (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let redis: RedisService;

  const phone = `+9197${Date.now() % 100000000}`;
  let token: string;
  let tripId: string;

  // The OTP endpoint rate-limits to 5 requests per phone per TTL window. The
  // suite runs against a *persistent* dev Redis, so fixed phones (the admin)
  // accumulate that counter across back-to-back runs and eventually get 429'd,
  // failing login. Clearing the counter before login keeps the suite hermetic.
  const resetOtpLimits = async (p: string) => {
    await redis.del(`otp:rate:${p}`);
    await redis.del(`otp:attempts:${p}`);
  };

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();
    app = moduleRef.createNestApplication();
    app.setGlobalPrefix('api/v1', {
      exclude: [{ path: 'metrics', method: RequestMethod.GET }],
    });
    app.useGlobalPipes(
      new ValidationPipe({
        whitelist: true,
        forbidNonWhitelisted: true,
        transform: true,
      }),
    );
    await app.init();
    server = app.getHttpServer();
    redis = app.get(RedisService);
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /health -> ok', async () => {
    const res = await request(server).get('/api/v1/health');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('ok');
    expect(res.body.services).toMatchObject({ database: 'up', redis: 'up' });
  });

  it('OTP login issues a token and creates the user', async () => {
    await resetOtpLimits(phone);
    const r1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone });
    expect(r1.status).toBe(200);
    const code = r1.body.devCode as string;
    expect(code).toMatch(/^\d{4}$/);

    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code });
    expect(r2.status).toBe(200);
    token = r2.body.accessToken;
    expect(token).toBeDefined();
    expect(r2.body.user.phone).toBe(phone);
  });

  it('rejects a protected route without a token', async () => {
    await request(server).get('/api/v1/users/me').expect(401);
  });

  it('rejects a wrong OTP', async () => {
    const p = `+9196${Date.now() % 100000000}`;
    const r1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: p });
    const wrong = r1.body.devCode === '0000' ? '1111' : '0000';
    await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: p, code: wrong })
      .expect(400);
  });

  it('estimates a trip across all tiers', async () => {
    const res = await request(server)
      .post('/api/v1/trips/estimate')
      .set('Authorization', `Bearer ${token}`)
      .send({
        pickupLat: 12.9611,
        pickupLng: 77.6387,
        dropoffLat: 12.9674,
        dropoffLng: 77.5904,
      });
    expect(res.status).toBe(200);
    expect(res.body.tiers).toHaveLength(4);
    expect(res.body.distanceM).toBeGreaterThan(0);
    expect(typeof res.body.polyline).toBe('string');
  });

  it('validates bad estimate input (out-of-range lat)', async () => {
    await request(server)
      .post('/api/v1/trips/estimate')
      .set('Authorization', `Bearer ${token}`)
      .send({ pickupLat: 999, pickupLng: 0, dropoffLat: 0, dropoffLng: 0 })
      .expect(400);
  });

  it('creates a trip in REQUESTED', async () => {
    // Remote pickup (Delhi) so no local/sim driver matches it — keeps the
    // create→cancel lifecycle assertions deterministic regardless of who is
    // online.
    const res = await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${token}`)
      .send({
        pickupLat: 28.6139,
        pickupLng: 77.209,
        dropoffLat: 28.62,
        dropoffLng: 77.22,
        tier: 'economy',
        pickupAddr: 'Connaught Place',
        dropoffAddr: 'India Gate',
      });
    expect(res.status).toBe(201);
    expect(res.body.status).toBe('requested');
    expect(res.body.fareEstimate).toBeGreaterThan(0);
    tripId = res.body.id;
  });

  it('rejects an invalid tier', async () => {
    await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${token}`)
      .send({
        pickupLat: 12.96,
        pickupLng: 77.64,
        dropoffLat: 12.97,
        dropoffLng: 77.59,
        tier: 'gold',
      })
      .expect(400);
  });

  it('cancels the trip via the state machine (no fee before a driver commits)', async () => {
    const res = await request(server)
      .post(`/api/v1/trips/${tripId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'e2e' });
    // The trip has no available driver (remote pickup), so no fee applies. It's
    // either still cancellable (→ cancelled, fee 0) or the async dispatch loop
    // already finalized it to no_drivers — both are pre-commit, fee-free states.
    if (res.status === 200) {
      expect(res.body.status).toBe('cancelled');
      expect(res.body.fee).toBe(0);
    } else {
      expect(res.status).toBe(400);
      const view = await request(server)
        .get(`/api/v1/trips/${tripId}`)
        .set('Authorization', `Bearer ${token}`);
      expect(view.body.status).toBe('no_drivers');
    }
  });

  it('rejects double-cancel (illegal transition)', async () => {
    await request(server)
      .post(`/api/v1/trips/${tripId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'again' })
      .expect(400);
  });

  it('lists trip history', async () => {
    const res = await request(server)
      .get('/api/v1/trips/history')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(res.body.length).toBeGreaterThanOrEqual(1);
  });

  it('starts with no payment methods, then adds one as default', async () => {
    const empty = await request(server)
      .get('/api/v1/payments/methods')
      .set('Authorization', `Bearer ${token}`);
    expect(empty.status).toBe(200);
    expect(empty.body).toEqual([]);

    const added = await request(server)
      .post('/api/v1/payments/methods')
      .set('Authorization', `Bearer ${token}`)
      .send({ brand: 'visa', last4: '4242' });
    expect(added.status).toBe(201);
    expect(added.body.isDefault).toBe(true);
    expect(added.body.last4).toBe('4242');

    const list = await request(server)
      .get('/api/v1/payments/methods')
      .set('Authorization', `Bearer ${token}`);
    expect(list.body).toHaveLength(1);
  });

  it('updates the profile (name + email) via PATCH /users/me', async () => {
    const res = await request(server)
      .patch('/api/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ fullName: 'Test Rider', email: 'rider@example.com' });
    expect(res.status).toBe(200);
    expect(res.body.fullName).toBe('Test Rider');
    expect(res.body.email).toBe('rider@example.com');
  });

  it('rejects an invalid email on profile update', async () => {
    await request(server)
      .patch('/api/v1/users/me')
      .set('Authorization', `Bearer ${token}`)
      .send({ email: 'not-an-email' })
      .expect(400);
  });

  it('saved places: add, list, edit, delete (full CRUD)', async () => {
    // add
    const added = await request(server)
      .post('/api/v1/users/me/places')
      .set('Authorization', `Bearer ${token}`)
      .send({ label: 'Home', address: 'MG Road', lat: 12.97, lng: 77.59 });
    expect(added.status).toBe(201);
    const id = added.body.id as string;
    expect(id).toBeDefined();

    // list
    const list = await request(server)
      .get('/api/v1/users/me/places')
      .set('Authorization', `Bearer ${token}`);
    expect(list.status).toBe(200);
    expect(list.body.some((p: { id: string }) => p.id === id)).toBe(true);

    // edit
    const edited = await request(server)
      .patch(`/api/v1/users/me/places/${id}`)
      .set('Authorization', `Bearer ${token}`)
      .send({ label: 'Work' });
    expect(edited.status).toBe(200);
    expect(edited.body.label).toBe('Work');

    // delete
    const removed = await request(server)
      .delete(`/api/v1/users/me/places/${id}`)
      .set('Authorization', `Bearer ${token}`);
    expect(removed.status).toBe(200);

    // gone
    const after = await request(server)
      .get('/api/v1/users/me/places')
      .set('Authorization', `Bearer ${token}`);
    expect(after.body.some((p: { id: string }) => p.id === id)).toBe(false);
  });

  it("forbids editing another user's saved place", async () => {
    const mine = await request(server)
      .post('/api/v1/users/me/places')
      .set('Authorization', `Bearer ${token}`)
      .send({ label: 'Gym', lat: 12.9, lng: 77.6 });
    const id = mine.body.id as string;

    // a second, unrelated user
    const otherPhone = `+9198${Date.now() % 100000000}`;
    await resetOtpLimits(otherPhone);
    const o1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: otherPhone });
    const o2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: otherPhone, code: o1.body.devCode });
    const otherToken = o2.body.accessToken as string;

    await request(server)
      .patch(`/api/v1/users/me/places/${id}`)
      .set('Authorization', `Bearer ${otherToken}`)
      .send({ label: 'Hacked' })
      .expect(404);
    await request(server)
      .delete(`/api/v1/users/me/places/${id}`)
      .set('Authorization', `Bearer ${otherToken}`)
      .expect(404);
  });

  it('refuses to rate a trip that is not completed', async () => {
    // tripId was cancelled above — rating must be rejected.
    await request(server)
      .post(`/api/v1/trips/${tripId}/rating`)
      .set('Authorization', `Bearer ${token}`)
      .send({ stars: 5 })
      .expect(400);
  });

  it('rejects an out-of-range star rating', async () => {
    await request(server)
      .post(`/api/v1/trips/${tripId}/rating`)
      .set('Authorization', `Bearer ${token}`)
      .send({ stars: 9 })
      .expect(400);
  });

  it('registers a device token for push', async () => {
    const res = await request(server)
      .post('/api/v1/notifications/devices')
      .set('Authorization', `Bearer ${token}`)
      .send({ token: `dev-${Date.now()}`, platform: 'android' });
    expect(res.status).toBe(200);
    expect(res.body.ok).toBe(true);
  });

  it('forbids a non-admin from the admin API', async () => {
    await request(server)
      .get('/api/v1/admin/stats')
      .set('Authorization', `Bearer ${token}`)
      .expect(403);
  });

  describe('robustness & edge cases', () => {
    async function freshUser() {
      const p = `+9198${Math.floor(Math.random() * 1e8)}`;
      const r1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: p });
      const r2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: p, code: r1.body.devCode });
      return { phone: p, token: r2.body.accessToken as string,
        refreshToken: r2.body.refreshToken as string };
    }

    it('rotates refresh tokens and rejects reuse of the old one', async () => {
      const u = await freshUser();
      const rotated = await request(server)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: u.refreshToken });
      expect(rotated.status).toBe(200);
      expect(rotated.body.accessToken).toBeDefined();
      expect(rotated.body.refreshToken).not.toBe(u.refreshToken);

      // Reusing the now-rotated (revoked) token must be rejected.
      const reuse = await request(server)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: u.refreshToken });
      expect(reuse.status).toBe(401);
    });

    // A remote pickup (Delhi) — far from any Bangalore test/sim driver — so the
    // trip won't be matched mid-test and the access-control assertions hold in
    // any state (a non-participant is always forbidden).
    const remoteTrip = {
      pickupLat: 28.6139, pickupLng: 77.209,
      dropoffLat: 28.62, dropoffLng: 77.22,
      tier: 'economy', pickupAddr: 'A', dropoffAddr: 'B',
    };

    it('forbids reading or cancelling another user\'s trip', async () => {
      const a = await freshUser();
      const b = await freshUser();
      const created = await request(server)
        .post('/api/v1/trips')
        .set('Authorization', `Bearer ${a.token}`)
        .send(remoteTrip);
      expect(created.status).toBe(201);
      const id = created.body.id;

      await request(server)
        .get(`/api/v1/trips/${id}`)
        .set('Authorization', `Bearer ${b.token}`)
        .expect(403);
      await request(server)
        .post(`/api/v1/trips/${id}/cancel`)
        .set('Authorization', `Bearer ${b.token}`)
        .send({})
        .expect(403);
    });

    it('rejects accepting a trip with no live offer for this driver', async () => {
      const a = await freshUser();
      const created = await request(server)
        .post('/api/v1/trips')
        .set('Authorization', `Bearer ${a.token}`)
        .send(remoteTrip);
      const b = await freshUser();
      // b was never offered this trip → 400.
      await request(server)
        .post(`/api/v1/trips/${created.body.id}/accept`)
        .set('Authorization', `Bearer ${b.token}`)
        .expect(400);
    });

    it('returns 404 for a missing trip', async () => {
      const a = await freshUser();
      await request(server)
        .get('/api/v1/trips/00000000-0000-0000-0000-000000000000')
        .set('Authorization', `Bearer ${a.token}`)
        .expect(404);
    });

    it('exposes Prometheus metrics at /metrics', async () => {
      const res = await request(server).get('/metrics');
      expect(res.status).toBe(200);
      expect(res.text).toContain('http_requests_total');
      expect(res.text).toContain('process_cpu_seconds_total');
    });
  });

  describe('admin (role-gated)', () => {
    let adminToken: string;
    // Matches ADMIN_PHONES in the backend .env — promoted to admin on login.
    const adminPhone = '+919900000001';

    beforeAll(async () => {
      await resetOtpLimits(adminPhone);
      const r1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: adminPhone });
      const r2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: adminPhone, code: r1.body.devCode });
      adminToken = r2.body.accessToken;
      expect(r2.body.user.role).toBe('admin');
    });

    it('returns dashboard stats', async () => {
      const res = await request(server)
        .get('/api/v1/admin/stats')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(res.status).toBe(200);
      expect(typeof res.body.users).toBe('number');
      expect(res.body).toHaveProperty('onlineDrivers');
      expect(res.body).toHaveProperty('tripsByStatus');
    });

    it('returns an ops metrics snapshot', async () => {
      const res = await request(server)
        .get('/api/v1/admin/metrics')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(res.status).toBe(200);
      expect(res.body.system).toHaveProperty('uptimeSec');
      expect(res.body.http).toHaveProperty('requestsTotal');
      expect(res.body.queues.dispatch).toHaveProperty('waiting');
      expect(res.body.queues.notifications).toHaveProperty('active');
      expect(res.body).toHaveProperty('tripFunnel');
    });

    it('lists trips and users', async () => {
      const trips = await request(server)
        .get('/api/v1/admin/trips?limit=10')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(trips.status).toBe(200);
      expect(Array.isArray(trips.body)).toBe(true);

      const users = await request(server)
        .get('/api/v1/admin/users?limit=10')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(users.status).toBe(200);
      expect(users.body.length).toBeGreaterThanOrEqual(1);
    });

    it('deactivates and reactivates a user', async () => {
      const users = await request(server)
        .get('/api/v1/admin/users?q=97')
        .set('Authorization', `Bearer ${adminToken}`);
      const target = users.body[0];
      const off = await request(server)
        .patch(`/api/v1/admin/users/${target.id}/active`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ isActive: false });
      expect(off.status).toBe(200);
      expect(off.body.isActive).toBe(false);

      await request(server)
        .patch(`/api/v1/admin/users/${target.id}/active`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ isActive: true })
        .expect(200);
    });
  });
});
