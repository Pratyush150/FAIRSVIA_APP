import { INestApplication, ValidationPipe, RequestMethod } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { RedisService } from '../src/common/redis/redis.service';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisKeys } from '../src/common/redis/redis.keys';

/**
 * Full-stack e2e against the real Postgres + Redis (run inside the backend
 * container). Exercises the auth + trip flow through the HTTP layer.
 */
describe('Ride App API (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let redis: RedisService;

  const phone = `+197${Date.now() % 100000000}`;
  let token: string;
  let tripId: string;
  // A deterministically-cancellable trip (parked on a non-responsive driver).
  let parkedTripId: string;
  let parkedRiderToken: string;

  // The OTP endpoint rate-limits to 5 requests per phone per TTL window. The
  // suite runs against a *persistent* dev Redis, so fixed phones (the admin)
  // accumulate that counter across back-to-back runs and eventually get 429'd,
  // failing login. Clearing the counter before login keeps the suite hermetic.
  const resetOtpLimits = async (p: string) => {
    await redis.del(`otp:rate:${p}`);
    await redis.del(`otp:attempts:${p}`);
  };

  /**
   * A brand-new signed-in rider. A rider may only have ONE trip in flight at a
   * time (enforced since the trips hardening pass), so any test that creates a
   * trip needs its own rider — sharing the suite's `token` makes the second
   * creation a 409 and the failure looks like a trip bug rather than a test
   * that outgrew the rule.
   */
  const freshRider = async () => {
    const p = `+196${Math.floor(Math.random() * 1e8)}`;
    const r1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: p });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: p, code: r1.body.devCode });
    return r2.body.accessToken as string;
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

  // app.close() drains in-flight BullMQ jobs (graceful shutdown). A dispatch
  // job can be mid-offer when the suite ends, so the default 5 s hook limit
  // intermittently failed the suite with every test green.
  const suiteStart = new Date();

  afterAll(async () => {
    // Rides this suite left in flight must not linger either: the dev server
    // shares this database and offers every "matching" ride to real online
    // drivers — a phone in the field would get offers for test rides. Scoped
    // to riders the suite itself created.
    await app.get(PrismaService).trip.updateMany({
      where: {
        status: { in: ['requested', 'matching', 'accepted', 'arrived', 'in_progress'] },
        rider: { createdAt: { gte: suiteStart } },
      },
      data: { status: 'cancelled', cancelReason: 'e2e cleanup' },
    });
    // The suite's SOS must not linger: on a shared dev database it shows up
    // as a real open alert in the admin console and fires SosRaised.
    if (tripId) {
      await app.get(PrismaService).safetyIncident.deleteMany({ where: { tripId } });
    }
    await app.close();
  }, 60_000);

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
    expect(code).toMatch(/^\d{6}$/);

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
    const p = `+196${Date.now() % 100000000}`;
    const r1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: p });
    const wrong = r1.body.devCode === '000000' ? '111111' : '000000';
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
        // Miami (Brickell → Downtown). Must be inside the Florida OSRM extract
        // so real road distance drives the tier fares; foreign coords collapse
        // to distance 0 and defeat the assertions below.
        pickupLat: 25.7615,
        pickupLng: -80.1929,
        dropoffLat: 25.7743,
        dropoffLng: -80.1937,
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

  it('GET /trips/active returns the live trip, and nothing for a fresh user', async () => {
    // The rider from the previous test has a live (requested/matching) trip.
    const active = await request(server)
      .get('/api/v1/trips/active')
      .set('Authorization', `Bearer ${token}`);
    expect(active.status).toBe(200);
    expect(active.body.id).toBe(tripId);
    expect(['requested', 'matching']).toContain(active.body.status);

    // A brand-new user with no trips gets an empty (null) active trip.
    const p = `+197${Date.now() % 100000000}`;
    await resetOtpLimits(p);
    const req = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: p });
    const verify = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: p, code: req.body.devCode });
    const freshToken = verify.body.accessToken as string;

    const none = await request(server)
      .get('/api/v1/trips/active')
      .set('Authorization', `Bearer ${freshToken}`);
    expect(none.status).toBe(200);
    expect(none.body.id).toBeUndefined();
  });

  it('records the payment mode (defaults to card, accepts cash)', async () => {
    const rider = await freshRider();
    const cash = await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${rider}`)
      .send({
        pickupLat: 28.6139,
        pickupLng: 77.209,
        dropoffLat: 28.62,
        dropoffLng: 77.22,
        tier: 'economy',
        paymentMode: 'cash',
      });
    expect(cash.status).toBe(201);
    expect(cash.body.paymentMode).toBe('cash');

    // An unknown payment mode is rejected by validation.
    await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${rider}`)
      .send({
        pickupLat: 28.6139,
        pickupLng: 77.209,
        dropoffLat: 28.62,
        dropoffLng: 77.22,
        tier: 'economy',
        paymentMode: 'bitcoin',
      })
      .expect(400);
  });

  it('supports multi-stop rides (adds distance, stores stops, caps at 3)', async () => {
    // Miami (Brickell → Downtown), inside the Florida OSRM extract so the detour
    // genuinely adds road distance; the detour stop sits off the direct line.
    const base = {
      pickupLat: 25.7615,
      pickupLng: -80.1929,
      dropoffLat: 25.7743,
      dropoffLng: -80.1937,
    };
    // Direct estimate.
    const direct = await request(server)
      .post('/api/v1/trips/estimate')
      .set('Authorization', `Bearer ${token}`)
      .send(base);
    const directDist = direct.body.distanceM as number;

    // Same trip with a detour stop well off the direct line.
    const withStop = await request(server)
      .post('/api/v1/trips/estimate')
      .set('Authorization', `Bearer ${token}`)
      .send({ ...base, stops: [{ lat: 25.79, lng: -80.13, addr: 'Detour' }] });
    expect(withStop.status).toBe(200);
    expect(withStop.body.distanceM).toBeGreaterThan(directDist);
    expect(withStop.body.stops).toHaveLength(1);

    // Create a multi-stop trip; the stop is persisted and the fare reflects it.
    const created = await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${await freshRider()}`)
      .send({
        ...base,
        tier: 'economy',
        stops: [{ lat: 25.79, lng: -80.13, addr: 'Detour' }],
      });
    expect(created.status).toBe(201);
    expect(created.body.stops).toHaveLength(1);
    expect(created.body.stops[0].addr).toBe('Detour');

    // More than 3 stops is rejected.
    await request(server)
      .post('/api/v1/trips/estimate')
      .set('Authorization', `Bearer ${token}`)
      .send({
        ...base,
        stops: [
          { lat: 25.79, lng: -80.13 },
          { lat: 25.80, lng: -80.14 },
          { lat: 25.81, lng: -80.15 },
          { lat: 25.82, lng: -80.16 },
        ],
      })
      .expect(400);
  });

  it('notification inbox: fresh user is empty, endpoints behave', async () => {
    // A brand-new user never triggers an (async) notification, so its inbox
    // stays deterministically empty — no cross-test push can race in.
    const nPhone = `+197${Date.now() % 100000000}`;
    await resetOtpLimits(nPhone);
    const r1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: nPhone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: nPhone, code: r1.body.devCode });
    const nToken = r2.body.accessToken as string;

    const list = await request(server)
      .get('/api/v1/me/notifications')
      .set('Authorization', `Bearer ${nToken}`);
    expect(list.status).toBe(200);
    expect(list.body).toEqual([]);

    const count = await request(server)
      .get('/api/v1/me/notifications/unread-count')
      .set('Authorization', `Bearer ${nToken}`);
    expect(count.body.unread).toBe(0);

    // read-all on an empty inbox marks nothing and stays at zero.
    const readAll = await request(server)
      .post('/api/v1/me/notifications/read-all')
      .set('Authorization', `Bearer ${nToken}`);
    expect(readAll.status).toBe(200);
    expect(readAll.body.marked).toBe(0);

    // Marking an unknown id is a harmless no-op.
    await request(server)
      .post('/api/v1/me/notifications/00000000-0000-0000-0000-000000000000/read')
      .set('Authorization', `Bearer ${nToken}`)
      .expect(200);
  });

  it('favorite drivers: add, list, remove', async () => {
    // The target must be a real driver: an unknown id is a 404 (API audit),
    // never a dangling favourite row.
    await request(server)
      .post('/api/v1/drivers/11111111-1111-1111-1111-111111111111/favorite')
      .set('Authorization', `Bearer ${token}`)
      .expect(404);
    await request(server)
      .post('/api/v1/drivers/not-a-uuid/favorite')
      .set('Authorization', `Bearer ${token}`)
      .expect(400);

    const dPhone = `+196${Date.now() % 100000000}`;
    await resetOtpLimits(dPhone);
    const d1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: dPhone });
    const d2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: dPhone, code: d1.body.devCode });
    const dToken = d2.body.accessToken as string;
    await request(server)
      .post('/api/v1/drivers/onboarding')
      .set('Authorization', `Bearer ${dToken}`)
      .send({
        vehicleMake: 'Toyota',
        vehicleModel: 'Prius',
        vehicleColor: 'white',
        plateNumber: `FAV${Date.now() % 100000}`,
        vehicleTier: 'economy',
        licenseNo: 'LIC-FAV',
      })
      .expect(201);
    const driverId = d2.body.user.id as string;

    const add = await request(server)
      .post(`/api/v1/drivers/${driverId}/favorite`)
      .set('Authorization', `Bearer ${token}`);
    expect(add.status).toBe(200);
    expect(add.body.favorited).toBe(true);

    const list = await request(server)
      .get('/api/v1/me/favorites')
      .set('Authorization', `Bearer ${token}`);
    expect(list.status).toBe(200);
    expect(list.body.some((f: { driverId: string }) => f.driverId === driverId))
      .toBe(true);

    // Adding again is idempotent (no duplicate).
    await request(server)
      .post(`/api/v1/drivers/${driverId}/favorite`)
      .set('Authorization', `Bearer ${token}`)
      .expect(200);
    const list2 = await request(server)
      .get('/api/v1/me/favorites')
      .set('Authorization', `Bearer ${token}`);
    expect(
      list2.body.filter((f: { driverId: string }) => f.driverId === driverId)
        .length,
    ).toBe(1);

    const remove = await request(server)
      .delete(`/api/v1/drivers/${driverId}/favorite`)
      .set('Authorization', `Bearer ${token}`);
    expect(remove.status).toBe(200);
    expect(remove.body.favorited).toBe(false);

    const list3 = await request(server)
      .get('/api/v1/me/favorites')
      .set('Authorization', `Bearer ${token}`);
    expect(list3.body.some((f: { driverId: string }) => f.driverId === driverId))
      .toBe(false);
  });

  it('schedules a ride for later, lists it, and cancels it', async () => {
    const when = new Date(Date.now() + 60 * 60 * 1000).toISOString(); // +1h
    const created = await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${token}`)
      .send({
        pickupLat: 28.6139,
        pickupLng: 77.209,
        dropoffLat: 28.62,
        dropoffLng: 77.22,
        tier: 'economy',
        scheduledAt: when,
      });
    expect(created.status).toBe(201);
    expect(created.body.status).toBe('scheduled');
    expect(created.body.scheduledAt).toBeTruthy();
    const scheduledId = created.body.id;

    // It shows up in the rider's scheduled list.
    const list = await request(server)
      .get('/api/v1/trips/scheduled')
      .set('Authorization', `Bearer ${token}`);
    expect(list.status).toBe(200);
    expect(list.body.some((t: { id: string }) => t.id === scheduledId)).toBe(
      true,
    );

    // A ride too soon (< 5 min lead) is rejected.
    await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${token}`)
      .send({
        pickupLat: 28.6139,
        pickupLng: 77.209,
        dropoffLat: 28.62,
        dropoffLng: 77.22,
        tier: 'economy',
        scheduledAt: new Date(Date.now() + 60 * 1000).toISOString(),
      })
      .expect(400);

    // A scheduled ride can be cancelled with no fee (no driver committed).
    const cancelled = await request(server)
      .post(`/api/v1/trips/${scheduledId}/cancel`)
      .set('Authorization', `Bearer ${token}`)
      .send({ reason: 'e2e schedule' });
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.status).toBe('cancelled');
    expect(cancelled.body.fee).toBe(0);
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

  it('cancels a matching trip with no fee before a driver commits', async () => {
    // Determinism: the earlier remote-pickup trip races the async dispatch loop
    // (still cancellable vs already finalized to no_drivers). Instead we PARK a
    // single non-responsive driver at a unique, remote coordinate. Dispatch
    // offers to it and blocks in the 15s offer loop, so the trip stays in
    // MATCHING and the cancel lands deterministically as fee-free (the driver
    // was offered but never committed).
    const pin = { lat: 5.001, lng: 5.001 };
    const driverId = `e2e-cancel-drv-${Date.now()}`;
    await redis.client.geoadd('drivers:geo:economy', pin.lng, pin.lat, driverId);
    await redis.client.set(RedisKeys.driverStatus(driverId), 'online');

    // A dedicated rider so the test is order-independent.
    const rPhone = `+194${Date.now() % 100000000}`;
    await resetOtpLimits(rPhone);
    const r1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: rPhone });
    const rv = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: rPhone, code: r1.body.devCode });
    parkedRiderToken = rv.body.accessToken as string;

    const created = await request(server)
      .post('/api/v1/trips')
      .set('Authorization', `Bearer ${parkedRiderToken}`)
      .send({
        pickupLat: pin.lat,
        pickupLng: pin.lng,
        dropoffLat: 5.02,
        dropoffLng: 5.02,
        tier: 'economy',
      });
    expect(created.status).toBe(201);
    parkedTripId = created.body.id;

    // Wait until dispatch has offered to the parked driver (trip → matching).
    let status = created.body.status as string;
    for (let i = 0; i < 50 && status !== 'matching'; i++) {
      await new Promise((r) => setTimeout(r, 100));
      const v = await request(server)
        .get(`/api/v1/trips/${parkedTripId}`)
        .set('Authorization', `Bearer ${parkedRiderToken}`);
      status = v.body.status;
    }
    expect(status).toBe('matching');

    const cancelled = await request(server)
      .post(`/api/v1/trips/${parkedTripId}/cancel`)
      .set('Authorization', `Bearer ${parkedRiderToken}`)
      .send({ reason: 'e2e' });
    expect(cancelled.status).toBe(200);
    expect(cancelled.body.status).toBe('cancelled');
    expect(cancelled.body.fee).toBe(0);

    // Release the parked dispatch loop (send a decline) and remove the seeded
    // driver so nothing leaks into other tests or the next run.
    await redis.client.set(
      RedisKeys.dispatchResponse(parkedTripId),
      `0:${driverId}`,
      'PX',
      30000,
    );
    await redis.client.zrem('drivers:geo:economy', driverId);
    await redis.client.del(
      RedisKeys.driverStatus(driverId),
      RedisKeys.driverOfferLock(driverId),
    );
  });

  it('rejects double-cancel (illegal transition)', async () => {
    await request(server)
      .post(`/api/v1/trips/${parkedTripId}/cancel`)
      .set('Authorization', `Bearer ${parkedRiderToken}`)
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

  it('places/reverse returns the full address plus a short label/detail', async () => {
    // Provider depends on env (stub in CI, Google/OSM in dev): assert the
    // contract, not the words. Content is covered by place-label.spec.ts.
    const res = await request(server)
      .get('/api/v1/places/reverse?lat=18.5074&lng=73.8553')
      .set('Authorization', `Bearer ${token}`);
    expect(res.status).toBe(200);
    expect(typeof res.body.address).toBe('string');
    expect(res.body.address.length).toBeGreaterThan(0);
    expect(typeof res.body.label).toBe('string');
    expect(res.body.label.length).toBeGreaterThan(0);
    expect(res.body.label).not.toMatch(/^\d/);
    expect(typeof res.body.detail).toBe('string');
    expect(res.body.location).toEqual({ lat: 18.5074, lng: 73.8553 });
  });

  it("forbids editing another user's saved place", async () => {
    const mine = await request(server)
      .post('/api/v1/users/me/places')
      .set('Authorization', `Bearer ${token}`)
      .send({ label: 'Gym', lat: 12.9, lng: 77.6 });
    const id = mine.body.id as string;

    // a second, unrelated user
    const otherPhone = `+198${Date.now() % 100000000}`;
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
    // tripId never reached completed (remote pickup, no match) — rating must
    // be rejected.
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

  // `tripId` is the remote-pickup trip that is deliberately never matched, so
  // it has no driver — and chat only opens once the two parties are paired
  // (ChatService.isChatOpen). The send/list/grace-window/rate-limit behaviour is
  // covered against a paired trip in chat.service.spec.ts; what the HTTP layer
  // owes us here is the access control around it.
  it('in-trip chat: closed before a driver is paired, and never open to non-participants', async () => {
    const send = await request(server)
      .post(`/api/v1/trips/${tripId}/messages`)
      .set('Authorization', `Bearer ${token}`)
      .send({ text: 'On my way!' });
    expect(send.status).toBe(403);

    // The rider may still read their own (empty) thread.
    const list = await request(server)
      .get(`/api/v1/trips/${tripId}/messages`)
      .set('Authorization', `Bearer ${token}`);
    expect(list.status).toBe(200);
    expect(Array.isArray(list.body)).toBe(true);

    // whitespace-only is rejected on its own merits, before the chat-open check
    await request(server)
      .post(`/api/v1/trips/${tripId}/messages`)
      .set('Authorization', `Bearer ${token}`)
      .send({ text: '   ' })
      .expect(400);

    // a non-participant cannot read the thread
    const otherPhone = `+195${Date.now() % 100000000}`;
    await resetOtpLimits(otherPhone);
    const o1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: otherPhone });
    const o2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: otherPhone, code: o1.body.devCode });
    await request(server)
      .get(`/api/v1/trips/${tripId}/messages`)
      .set('Authorization', `Bearer ${o2.body.accessToken}`)
      .expect(403);
  });

  it('safety: rider raises SOS, non-participant is forbidden', async () => {
    const sos = await request(server)
      .post(`/api/v1/trips/${tripId}/sos`)
      .set('Authorization', `Bearer ${token}`)
      .send({ lat: 12.97, lng: 77.59 });
    expect(sos.status).toBe(201);
    expect(sos.body.ok).toBe(true);
    expect(sos.body.incidentId).toEqual(expect.any(String));
    expect(sos.body.repeat).toBe(false);

    const otherPhone = `+194${Date.now() % 100000000}`;
    await resetOtpLimits(otherPhone);
    const o1 = await request(server)
      .post('/api/v1/auth/otp/request')
      .send({ phone: otherPhone });
    const o2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone: otherPhone, code: o1.body.devCode });
    await request(server)
      .post(`/api/v1/trips/${tripId}/sos`)
      .set('Authorization', `Bearer ${o2.body.accessToken}`)
      .send({})
      .expect(403);
  });

  it('forbids a non-admin from the admin API', async () => {
    await request(server)
      .get('/api/v1/admin/stats')
      .set('Authorization', `Bearer ${token}`)
      .expect(403);
  });

  describe('robustness & edge cases', () => {
    async function freshUser() {
      const p = `+198${Math.floor(Math.random() * 1e8)}`;
      const r1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: p });
      const r2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: p, code: r1.body.devCode });
      return { phone: p, token: r2.body.accessToken as string,
        refreshToken: r2.body.refreshToken as string };
    }

    it('rotates refresh tokens, replays the rotation for its own client, and rejects a genuinely revoked token', async () => {
      const u = await freshUser();
      const rotated = await request(server)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: u.refreshToken });
      expect(rotated.status).toBe(200);
      expect(rotated.body.accessToken).toBeDefined();
      expect(rotated.body.refreshToken).not.toBe(u.refreshToken);

      // Presenting the just-rotated token again inside the replay window hands
      // back the SAME pair rather than treating it as theft. A client whose
      // refresh response was lost to a dropped network retries with the only
      // token it still has, and signing it out for that is the logout riders
      // and drivers hit every time they changed network.
      const replay = await request(server)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: u.refreshToken });
      expect(replay.status).toBe(200);
      expect(replay.body.refreshToken).toBe(rotated.body.refreshToken);

      // A token that was revoked outright (signed out everywhere) is still
      // refused — the replay window only covers the pair we just issued.
      await request(server)
        .post('/api/v1/auth/logout')
        .set('Authorization', `Bearer ${rotated.body.accessToken}`)
        .send({ refreshToken: rotated.body.refreshToken })
        .expect(200);
      const revoked = await request(server)
        .post('/api/v1/auth/refresh')
        .send({ refreshToken: rotated.body.refreshToken });
      expect(revoked.status).toBe(401);
    });

    // A remote pickup (Seattle) — far from any Miami test/sim driver — so the
    // trip won't be matched mid-test and the access-control assertions hold in
    // any state (a non-participant is always forbidden).
    const remoteTrip = {
      pickupLat: 47.6062, pickupLng: -122.3321,
      dropoffLat: 47.61, dropoffLng: -122.34,
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
    const adminPhone = '+19900000001';

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

    it('fare config: admin lists tiers and edits a fare, then restores it', async () => {
      const list = await request(server)
        .get('/api/v1/admin/fares')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(list.status).toBe(200);
      expect(list.body.map((f: { tier: string }) => f.tier)).toEqual([
        'economy',
        'comfort',
        'xl',
        'premium',
      ]);
      const original = list.body[0].baseFare as number;

      const bumped = await request(server)
        .patch('/api/v1/admin/fares/economy')
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ baseFare: original + 25 });
      expect(bumped.status).toBe(200);
      expect(bumped.body.baseFare).toBe(original + 25);

      // Restore so later runs / tests see the seeded value.
      await request(server)
        .patch('/api/v1/admin/fares/economy')
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ baseFare: original })
        .expect(200);
    });

    it('surge: admin override raises the fare estimate, then clears', async () => {
      // A pristine cell (Orlando) inside the Florida OSRM extract that no other
      // test or simulation sends trips to, so organic surge stays 1 and the admin
      // override floor is the only multiplier — isolating this assertion from
      // cross-test/cross-run Redis demand. (Far from the Miami cluster the load
      // sims exercise, so no residual surge, but still routable for a real fare.)
      const orlando = {
        pickupLat: 28.5383,
        pickupLng: -81.3792,
        dropoffLat: 28.55,
        dropoffLng: -81.36,
      };
      // Self-heal: clear any override left by a prior failed run so the baseline
      // is truly organic (surge 1) before we measure the override's effect.
      await request(server)
        .patch('/api/v1/admin/surge')
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ multiplier: 1 })
        .expect(200);
      const base = await request(server)
        .post('/api/v1/trips/estimate')
        .set('Authorization', `Bearer ${token}`)
        .send(orlando);
      const baseFare = base.body.tiers[0].fare;
      expect(base.body.surge).toBe(1);

      // Admin forces a 1.5x surge floor.
      const set = await request(server)
        .patch('/api/v1/admin/surge')
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ multiplier: 1.5 });
      expect(set.status).toBe(200);
      expect(set.body.override).toBe(1.5);

      const surged = await request(server)
        .post('/api/v1/trips/estimate')
        .set('Authorization', `Bearer ${token}`)
        .send(orlando);
      expect(surged.body.surge).toBe(1.5);
      expect(surged.body.tiers[0].fare).toBeGreaterThan(baseFare);

      // Snapshot is visible to admins.
      const snap = await request(server)
        .get('/api/v1/admin/surge')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(snap.status).toBe(200);
      expect(snap.body.override).toBe(1.5);

      // Clear the override so other tests / runs see organic surge.
      await request(server)
        .patch('/api/v1/admin/surge')
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ multiplier: 1 })
        .expect(200);
    });

    it('promo: admin creates a code, rider quotes it and rides with a discount', async () => {
      const code = `E2E${Date.now().toString().slice(-8)}`;

      // Admin creates a 20% promo capped at 40 off.
      const created = await request(server)
        .post('/api/v1/admin/promos')
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ code, kind: 'percent', value: 20, maxDiscount: 40 });
      expect(created.status).toBe(201);
      expect(created.body.code).toBe(code);

      // Rider prices it against a 200 subtotal: 20% = 40, at the cap.
      const quote = await request(server)
        .post('/api/v1/promos/quote')
        .set('Authorization', `Bearer ${token}`)
        .send({ code, subtotal: 200 });
      expect(quote.status).toBe(200);
      expect(quote.body.discount).toBe(40);
      expect(quote.body.net).toBe(160);

      // Gross fare for this exact route (estimate does not add demand, so it
      // matches the surge the trip create will read a moment later).
      const route = {
        pickupLat: 19.076,
        pickupLng: 72.8777,
        dropoffLat: 19.12,
        dropoffLng: 72.9,
      };
      const gross = await request(server)
        .post('/api/v1/trips/estimate')
        .set('Authorization', `Bearer ${token}`)
        .send(route);
      const grossFare = gross.body.tiers[0].fare as number;

      // Rider requests the ride with the code; the stored estimate is discounted.
      // Own rider: the suite's `token` already has a trip in flight, and a
      // rider may only have one. The per-user promo limit below is checked
      // against this same rider — that is whose redemption it is.
      const promoRider = await freshRider();
      const withPromo = await request(server)
        .post('/api/v1/trips')
        .set('Authorization', `Bearer ${promoRider}`)
        .send({ ...route, tier: 'economy', promoCode: code.toLowerCase() });
      expect(withPromo.status).toBe(201);
      expect(withPromo.body.promoCode).toBe(code);
      expect(withPromo.body.promoDiscount).toBeGreaterThan(0);
      expect(withPromo.body.fareEstimate).toBeCloseTo(
        grossFare - withPromo.body.promoDiscount,
        2,
      );

      // Per-user limit is 1 by default: a second quote by the rider who already
      // redeemed it is rejected.
      await request(server)
        .post('/api/v1/promos/quote')
        .set('Authorization', `Bearer ${promoRider}`)
        .send({ code, subtotal: 200 })
        .expect(400);
    });

    it('refund: admin-only, and 404 when there is no payment to refund', async () => {
      // A non-admin cannot refund.
      await request(server)
        .post(`/api/v1/admin/payments/${tripId}/refund`)
        .set('Authorization', `Bearer ${token}`)
        .send({ amount: 10 })
        .expect(403);

      // The earlier cancelled trip has no captured payment → nothing to refund.
      await request(server)
        .post(`/api/v1/admin/payments/${tripId}/refund`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ amount: 10 })
        .expect(404);
    });

    it('live ops snapshot: drivers + active trips (admin-only)', async () => {
      const res = await request(server)
        .get('/api/v1/admin/live')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body.drivers)).toBe(true);
      expect(Array.isArray(res.body.trips)).toBe(true);
      // Any driver entry has real coordinates + a status.
      for (const d of res.body.drivers) {
        expect(typeof d.lat).toBe('number');
        expect(typeof d.lng).toBe('number');
        expect(d.status).toBeTruthy();
      }

      // Non-admins are forbidden.
      await request(server)
        .get('/api/v1/admin/live')
        .set('Authorization', `Bearer ${token}`)
        .expect(403);
    });

    it('support tickets: rider opens, admin replies + resolves, rider reopens', async () => {
      // Mint a dedicated rider token so the test is order-independent.
      const rPhone = `+195${Date.now() % 100000000}`;
      await resetOtpLimits(rPhone);
      const r1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: rPhone });
      const rv = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: rPhone, code: r1.body.devCode });
      const riderToken = rv.body.accessToken as string;

      // Rider opens a ticket.
      const created = await request(server)
        .post('/api/v1/support/tickets')
        .set('Authorization', `Bearer ${riderToken}`)
        .send({
          subject: 'Charged twice',
          message: 'I was billed two times for one ride.',
          category: 'payment',
        });
      expect(created.status).toBe(201);
      expect(created.body.status).toBe('open');
      const ticketId = created.body.id;

      // It shows in the rider's list and its thread has the opening message.
      const mine = await request(server)
        .get('/api/v1/support/tickets')
        .set('Authorization', `Bearer ${riderToken}`);
      expect(mine.body.some((t: { id: string }) => t.id === ticketId)).toBe(true);
      const thread = await request(server)
        .get(`/api/v1/support/tickets/${ticketId}`)
        .set('Authorization', `Bearer ${riderToken}`);
      expect(thread.body.messages).toHaveLength(1);
      expect(thread.body.messages[0].authorRole).toBe('user');

      // Admin sees it in the queue and replies (→ active).
      const queue = await request(server)
        .get('/api/v1/admin/support/tickets')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(queue.body.some((t: { id: string }) => t.id === ticketId)).toBe(true);
      const adminReply = await request(server)
        .post(`/api/v1/support/tickets/${ticketId}/messages`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ body: 'Looking into the double charge now.' });
      expect(adminReply.status).toBe(201);
      expect(adminReply.body.status).toBe('active');
      expect(adminReply.body.messages).toHaveLength(2);

      // Admin resolves it.
      const resolved = await request(server)
        .patch(`/api/v1/admin/support/tickets/${ticketId}`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ status: 'resolved' });
      expect(resolved.status).toBe(200);
      expect(resolved.body.status).toBe('resolved');

      // A rider reply reopens the ticket (→ active).
      const reopen = await request(server)
        .post(`/api/v1/support/tickets/${ticketId}/messages`)
        .set('Authorization', `Bearer ${riderToken}`)
        .send({ body: 'Still not refunded.' });
      expect(reopen.body.status).toBe('active');

      // A different rider cannot read this ticket.
      const oPhone = `+196${Date.now() % 100000000}`;
      await resetOtpLimits(oPhone);
      const o1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: oPhone });
      const o2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: oPhone, code: o1.body.devCode });
      await request(server)
        .get(`/api/v1/support/tickets/${ticketId}`)
        .set('Authorization', `Bearer ${o2.body.accessToken}`)
        .expect(403);
    });

    it('lists recent SOS alerts for admins', async () => {
      const res = await request(server)
        .get('/api/v1/admin/safety')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(res.status).toBe(200);
      expect(Array.isArray(res.body)).toBe(true);
      // The rider's SOS earlier in the suite should be present.
      expect(res.body.some((e: { tripId: string }) => e.tripId === tripId)).toBe(
        true,
      );
    });

    it('KYC gate: admin revoke blocks going online, re-approve restores it', async () => {
      // A fresh driver (auto-verified in dev, so can go online immediately).
      const dPhone = `+199${Date.now() % 100000000}`;
      await resetOtpLimits(dPhone);
      const d1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: dPhone });
      const d2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: dPhone, code: d1.body.devCode });
      const dToken = d2.body.accessToken as string;
      const dId = d2.body.user.id as string;
      await request(server)
        .post('/api/v1/drivers/onboarding')
        .set('Authorization', `Bearer ${dToken}`)
        .send({
          vehicleMake: 'Toyota',
          vehicleModel: 'Etios',
          plateNumber: 'KA01XX0001',
          vehicleTier: 'economy',
        })
        .expect(201);

      // No name yet: riders couldn't check who is coming, so no going online.
      const nameless = await request(server)
        .post('/api/v1/drivers/status')
        .set('Authorization', `Bearer ${dToken}`)
        .send({ status: 'online' })
        .expect(400);
      expect(nameless.body.code).toBe('NAME_REQUIRED');
      await request(server)
        .patch('/api/v1/users/me')
        .set('Authorization', `Bearer ${dToken}`)
        .send({ fullName: 'Rahul Patil' })
        .expect(200);

      // Verified and named → online allowed.
      await request(server)
        .post('/api/v1/drivers/status')
        .set('Authorization', `Bearer ${dToken}`)
        .send({ status: 'online' })
        .expect(200);

      // Admin revokes verification.
      const revoke = await request(server)
        .patch(`/api/v1/admin/drivers/${dId}/verify`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ docsVerified: false });
      expect(revoke.status).toBe(200);
      expect(revoke.body.docsVerified).toBe(false);

      // Now blocked from going online.
      await request(server)
        .post('/api/v1/drivers/status')
        .set('Authorization', `Bearer ${dToken}`)
        .send({ status: 'online' })
        .expect(403);

      // Appears in the pending-review list.
      const pending = await request(server)
        .get('/api/v1/admin/drivers?pending=true')
        .set('Authorization', `Bearer ${adminToken}`);
      expect(pending.body.some((x: { id: string }) => x.id === dId)).toBe(true);

      // Re-approve → online works again.
      await request(server)
        .patch(`/api/v1/admin/drivers/${dId}/verify`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ docsVerified: true })
        .expect(200);
      await request(server)
        .post('/api/v1/drivers/status')
        .set('Authorization', `Bearer ${dToken}`)
        .send({ status: 'online' })
        .expect(200);
    });

    it('background check: driver initiates → pending → clear verifies; admin can refresh', async () => {
      const dPhone = `+1963${Date.now() % 10000000}`;
      await resetOtpLimits(dPhone);
      const d1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: dPhone });
      const d2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: dPhone, code: d1.body.devCode });
      const dToken = d2.body.accessToken as string;
      const dId = d2.body.user.id as string;
      await request(server)
        .post('/api/v1/drivers/onboarding')
        .set('Authorization', `Bearer ${dToken}`)
        .send({
          vehicleMake: 'Honda',
          vehicleModel: 'Civic',
          plateNumber: 'FL01BGC1',
          vehicleTier: 'economy',
        })
        .expect(201);

      // No check yet.
      const s0 = await request(server)
        .get('/api/v1/drivers/background')
        .set('Authorization', `Bearer ${dToken}`)
        .expect(200);
      expect(s0.body.status).toBe('none');

      // Order a check → pending, vendor ids recorded.
      const init = await request(server)
        .post('/api/v1/drivers/background')
        .set('Authorization', `Bearer ${dToken}`)
        .send({})
        .expect(200);
      expect(init.body.status).toBe('pending');
      expect(init.body.candidateId).toBeTruthy();
      expect(init.body.reportId).toBeTruthy();

      // Poll → clear, which verifies the driver's documents.
      const ref = await request(server)
        .post('/api/v1/drivers/background/refresh')
        .set('Authorization', `Bearer ${dToken}`)
        .expect(200);
      expect(ref.body.status).toBe('clear');
      expect(ref.body.docsVerified).toBe(true);

      // Admin can refresh any driver's check; non-admins cannot.
      const adminRef = await request(server)
        .post(`/api/v1/admin/drivers/${dId}/background/refresh`)
        .set('Authorization', `Bearer ${adminToken}`)
        .expect(200);
      expect(adminRef.body.status).toBe('clear');
      await request(server)
        .post(`/api/v1/admin/drivers/${dId}/background/refresh`)
        .set('Authorization', `Bearer ${dToken}`)
        .expect(403);
    });

    it('background check: a flagged applicant resolves to consider (manual review)', async () => {
      const dPhone = `+1964${Date.now() % 10000000}`;
      await resetOtpLimits(dPhone);
      const d1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: dPhone });
      const d2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: dPhone, code: d1.body.devCode });
      const dToken = d2.body.accessToken as string;
      await request(server)
        .post('/api/v1/drivers/onboarding')
        .set('Authorization', `Bearer ${dToken}`)
        .send({
          vehicleMake: 'Honda',
          vehicleModel: 'Civic',
          plateNumber: 'FL01BGC2',
          vehicleTier: 'economy',
        })
        .expect(201);

      // The mock flags any candidate whose email marks it for review.
      await request(server)
        .post('/api/v1/drivers/background')
        .set('Authorization', `Bearer ${dToken}`)
        .send({ email: `consider.${Date.now()}@drivers.example` })
        .expect(200);
      const ref = await request(server)
        .post('/api/v1/drivers/background/refresh')
        .set('Authorization', `Bearer ${dToken}`)
        .expect(200);
      expect(ref.body.status).toBe('consider');
    });

    it('payout ledger: fresh driver has zero balance; over-withdrawal is 400', async () => {
      const dPhone = `+198${Date.now() % 100000000}`;
      await resetOtpLimits(dPhone);
      const d1 = await request(server)
        .post('/api/v1/auth/otp/request')
        .send({ phone: dPhone });
      const d2 = await request(server)
        .post('/api/v1/auth/otp/verify')
        .send({ phone: dPhone, code: d1.body.devCode });
      const dToken = d2.body.accessToken as string;
      await request(server)
        .post('/api/v1/drivers/onboarding')
        .set('Authorization', `Bearer ${dToken}`)
        .send({
          vehicleMake: 'Toyota',
          vehicleModel: 'Etios',
          plateNumber: 'KA01LG0001',
          vehicleTier: 'economy',
        })
        .expect(201);

      // Fresh driver: empty ledger, zero balance.
      const bal = await request(server)
        .get('/api/v1/drivers/balance')
        .set('Authorization', `Bearer ${dToken}`);
      expect(bal.status).toBe(200);
      expect(bal.body.balance).toBe(0);
      expect(bal.body.entries).toEqual([]);

      // Can't withdraw more than the (zero) balance.
      await request(server)
        .post('/api/v1/drivers/balance/withdraw')
        .set('Authorization', `Bearer ${dToken}`)
        .send({ amount: 100 })
        .expect(400);
    });
  });
});
