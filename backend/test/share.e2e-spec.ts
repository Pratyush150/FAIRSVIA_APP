import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { RedisKeys } from '../src/common/redis/redis.keys';
import { ShareKeys } from '../src/share/share.service';

/** Live trip tracking links: who can mint one, what the public sees, when it dies. */
describe('Share / live tracking link (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];

  const login = async (phone: string) => {
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    userIds.push(r2.body.user.id);
    return { id: r2.body.user.id as string, auth: { Authorization: `Bearer ${r2.body.accessToken}` } };
  };
  const phone = () => `+1996${Math.floor(1e6 + Math.random() * 8e6)}`;
  const tokenOf = (url: string) => url.split('/').pop() as string;

  let riderPhone: string;
  let driverPhone: string;
  let rider: Awaited<ReturnType<typeof login>>;
  let driver: Awaited<ReturnType<typeof login>>;

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
    prisma = app.get(PrismaService);
    redis = app.get(RedisService);

    riderPhone = phone();
    driverPhone = phone();
    rider = await login(riderPhone);
    driver = await login(driverPhone);
    await prisma.user.update({ where: { id: rider.id }, data: { fullName: 'Aziza Karimova' } });
    await prisma.user.update({
      where: { id: driver.id },
      data: { fullName: 'Bekzod Tursunov', role: 'driver' },
    });
    await prisma.driverProfile.create({
      data: {
        userId: driver.id,
        vehicleMake: 'Chevrolet',
        vehicleModel: 'Cobalt',
        vehicleColor: 'White',
        plateNumber: '01A123BC',
      },
    });
  });

  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.driverProfile.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await redis.del(RedisKeys.driverLoc(driver.id));
    await app.close();
  }, 60_000);

  const makeTrip = (status: string, extra: Record<string, unknown> = {}) =>
    prisma.trip.create({
      data: {
        riderId: rider.id,
        driverId: driver.id,
        status: status as never,
        pickupLat: 41.31,
        pickupLng: 69.24,
        pickupAddr: 'Amir Temur Square, 5 Amir Temur Ave, Tashkent, Uzbekistan',
        dropoffLat: 41.33,
        dropoffLng: 69.28,
        dropoffAddr: 'Chorsu Bazaar, Navoi St, Tashkent',
        startOtp: '4821',
        passengerPhone: '+998901234567',
        ...extra,
      },
    });

  it('only the trip\'s rider can mint a link, only while the trip is live', async () => {
    const trip = await makeTrip('accepted');
    await request(server).post(`/api/v1/trips/${trip.id}/share-link`).expect(401);
    await request(server).post(`/api/v1/trips/${trip.id}/share-link`).set(driver.auth).expect(403);
    const stranger = await login(phone());
    await request(server).post(`/api/v1/trips/${trip.id}/share-link`).set(stranger.auth).expect(403);
    await request(server)
      .post(`/api/v1/trips/00000000-0000-4000-8000-000000000000/share-link`)
      .set(rider.auth)
      .expect(404);

    const res = await request(server)
      .post(`/api/v1/trips/${trip.id}/share-link`)
      .set(rider.auth)
      .set('X-Forwarded-Proto', 'https')
      .set('Host', 'ride.example.test')
      .expect(201);
    expect(res.body.url).toMatch(/^https:\/\/ride\.example\.test\/api\/v1\/public\/t\/[A-Za-z0-9_-]{32}$/);
    // Asking again (Share tapped twice) returns the same link.
    const again = await request(server)
      .post(`/api/v1/trips/${trip.id}/share-link`)
      .set(rider.auth)
      .expect(201);
    expect(tokenOf(again.body.url)).toBe(tokenOf(res.body.url));

    const done = await makeTrip('completed', { completedAt: new Date() });
    await request(server).post(`/api/v1/trips/${done.id}/share-link`).set(rider.auth).expect(409);
  });

  it('serves the page and a payload with no phones, rider name or full address', async () => {
    const trip = await makeTrip('in_progress');
    await redis.client.hset(RedisKeys.driverLoc(driver.id), {
      lat: 41.32,
      lng: 69.26,
      heading: 90,
      ts: Date.now(),
    });
    const { body } = await request(server)
      .post(`/api/v1/trips/${trip.id}/share-link`)
      .set(rider.auth)
      .expect(201);
    const token = tokenOf(body.url);

    const page = await request(server).get(`/api/v1/public/t/${token}`).expect(200);
    expect(page.headers['content-type']).toMatch(/text\/html/);
    expect(page.headers['content-security-policy']).toContain("connect-src 'self'");
    expect(page.text).toContain('FAIRSVIA');
    expect(page.text).toContain('leaflet');
    expect(page.text).not.toMatch(/maps\.googleapis|key=AIza/);

    const track = await request(server).get(`/api/v1/public/track/${token}`).expect(200);
    expect(track.body).toMatchObject({
      status: 'on_trip',
      ended: false,
      driverFirstName: 'Bekzod',
      vehicleLabel: 'White Chevrolet Cobalt',
      plate: '01A123BC',
      lat: 41.32,
      lng: 69.26,
      heading: 90,
      pickup: { label: 'Amir Temur Square', lat: 41.31, lng: 69.24 },
      dropoff: { label: 'Chorsu Bazaar', lat: 41.33, lng: 69.28 },
    });
    expect(track.body.etaSec).toBeGreaterThan(0);
    const raw = JSON.stringify(track.body);
    for (const secret of [riderPhone, driverPhone, '+998901234567', 'Aziza', 'Tursunov', '4821', 'Navoi', 'Tashkent']) {
      expect(raw).not.toContain(secret);
    }
    expect(Object.keys(track.body).some((k) => /phone|rider|otp|fare/i.test(k))).toBe(false);
  });

  it('unknown, malformed and expired tokens are 404', async () => {
    await request(server).get('/api/v1/public/track/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA').expect(404);
    await request(server).get('/api/v1/public/track/not-a-token').expect(404);
    const page = await request(server).get('/api/v1/public/t/AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA').expect(404);
    expect(page.text).toContain('This link has expired');

    const trip = await makeTrip('accepted');
    const { body } = await request(server)
      .post(`/api/v1/trips/${trip.id}/share-link`)
      .set(rider.auth)
      .expect(201);
    const token = tokenOf(body.url);
    await request(server).get(`/api/v1/public/track/${token}`).expect(200);
    await redis.del(ShareKeys.token(token)); // TTL ran out
    await request(server).get(`/api/v1/public/track/${token}`).expect(404);
  });

  it('an ended trip says so, hides the car, and the link dies an hour later', async () => {
    const trip = await makeTrip('in_progress');
    const { body } = await request(server)
      .post(`/api/v1/trips/${trip.id}/share-link`)
      .set(rider.auth)
      .expect(201);
    const token = tokenOf(body.url);

    await prisma.trip.update({
      where: { id: trip.id },
      data: { status: 'completed', completedAt: new Date() },
    });
    const ended = await request(server).get(`/api/v1/public/track/${token}`).expect(200);
    expect(ended.body).toMatchObject({ status: 'completed', ended: true, lat: null, lng: null, etaSec: null });
    const ttl = await redis.client.ttl(ShareKeys.token(token));
    expect(ttl).toBeGreaterThan(3500);
    expect(ttl).toBeLessThanOrEqual(3600);

    // Completed more than an hour ago: gone.
    await prisma.trip.update({
      where: { id: trip.id },
      data: { completedAt: new Date(Date.now() - 61 * 60 * 1000) },
    });
    await request(server).get(`/api/v1/public/track/${token}`).expect(404);
    expect(await redis.get(ShareKeys.token(token))).toBeNull();
  });

  it('rate-limits the public feed per client', async () => {
    const trip = await makeTrip('accepted');
    const { body } = await request(server)
      .post(`/api/v1/trips/${trip.id}/share-link`)
      .set(rider.auth)
      .expect(201);
    const token = tokenOf(body.url);
    const ipKeys = ['::ffff:127.0.0.1', '127.0.0.1', '::1'].map(ShareKeys.rateIp);
    await redis.client.del(...ipKeys);
    const codes: number[] = [];
    for (let i = 0; i < 65; i++) {
      codes.push((await request(server).get(`/api/v1/public/track/${token}`)).status);
    }
    expect(codes.slice(0, 50).every((c) => c === 200)).toBe(true);
    expect(codes).toContain(429);
    await redis.client.del(...ipKeys);
  });
});
