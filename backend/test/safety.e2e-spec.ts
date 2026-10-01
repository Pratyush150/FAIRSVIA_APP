import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { SMS_PROVIDER, SmsProvider } from '../src/auth/sms/sms-provider.interface';

/** SOS end to end: contacts, the SMS they receive, repeat presses, ops. */
describe('Safety / SOS (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const sent: { phone: string; message: string }[] = [];
  const sms: SmsProvider = {
    sendOtp: async () => undefined,
    sendMessage: async (phone, message) => {
      sent.push({ phone, message });
    },
  };
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
  const phone = () => `+1997${Math.floor(1e6 + Math.random() * 8e6)}`;

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(SMS_PROVIDER)
      .useValue(sms)
      .compile();
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
  });

  // app.close() drains in-flight BullMQ jobs; see app.e2e-spec.ts.
  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.driverProfile.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('manages emergency contacts with the limits a user would expect', async () => {
    const me = await login(phone());
    const add = (name: string, p: string) =>
      request(server).post('/api/v1/users/me/emergency-contacts').set(me.auth).send({ name, phone: p });

    const bad = await add('Mum', '12345');
    expect(bad.status).toBe(400);
    expect(JSON.stringify(bad.body.message)).toMatch(/international format/);

    const first = await add('Mum', '+998 90 123 45 67');
    expect(first.status).toBe(201);
    expect(first.body.phone).toBe('+998901234567');
    expect((await add('Mum again', '+998901234567')).status).toBe(409);
    await add('Dad', '+998901234568').expect(201);
    await add('Sister', '+998901234569').expect(201);
    const fourth = await add('Friend', '+998901234570');
    expect(fourth.status).toBe(400);
    expect(fourth.body.message).toMatch(/up to 3/);

    const list = await request(server).get('/api/v1/users/me/emergency-contacts').set(me.auth).expect(200);
    expect(list.body.map((c: { name: string }) => c.name)).toEqual(['Mum', 'Dad', 'Sister']);
    await request(server)
      .delete(`/api/v1/users/me/emergency-contacts/${first.body.id}`)
      .set(me.auth)
      .expect(200);
    const after = await request(server).get('/api/v1/users/me/emergency-contacts').set(me.auth);
    expect(after.body).toHaveLength(2);
  });

  it('texts every contact with the car, plate and location, once per press', async () => {
    const rider = await login(phone());
    const driverPhone = phone();
    const driver = await login(driverPhone);
    await prisma.user.update({ where: { id: rider.id }, data: { fullName: 'Aziza' } });
    await prisma.user.update({
      where: { id: driver.id },
      data: { fullName: 'Bekzod', role: 'driver' },
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
    for (const [name, p] of [['Mum', '+998901110001'], ['Dad', '+998901110002']]) {
      await request(server)
        .post('/api/v1/users/me/emergency-contacts')
        .set(rider.auth)
        .send({ name, phone: p })
        .expect(201);
    }
    const trip = await prisma.trip.create({
      data: {
        riderId: rider.id,
        driverId: driver.id,
        status: 'in_progress',
        pickupLat: 41.31,
        pickupLng: 69.24,
        dropoffLat: 41.33,
        dropoffLng: 69.28,
        dropoffAddr: 'Chorsu Bazaar',
      },
    });
    sent.length = 0;

    const res = await request(server)
      .post(`/api/v1/trips/${trip.id}/sos`)
      .set(rider.auth)
      .send({ lat: 41.3265, lng: 69.2285 })
      .expect(201);

    expect(res.body).toMatchObject({ contactsNotified: 2, contactsTotal: 2, repeat: false });
    expect(res.body.emergencyNumbers[0]).toEqual({ label: 'Police', number: '102' });
    expect(sent.map((s) => s.phone).sort()).toEqual(['+998901110001', '+998901110002']);
    const msg = sent[0].message;
    expect(msg).toContain('FAIRSVIA SOS: Aziza pressed the emergency button');
    expect(msg).toContain('https://maps.google.com/?q=41.32650,69.22850');
    expect(msg).toContain('White Chevrolet Cobalt, plate 01A123BC');
    expect(msg).toContain('Driver: Bekzod');
    expect(msg).toContain('Chorsu Bazaar');
    // The other party is never told.
    expect(sent.map((s) => s.phone)).not.toContain(driverPhone);

    // A panicked second tap: same incident, contacts NOT texted again.
    sent.length = 0;
    const again = await request(server)
      .post(`/api/v1/trips/${trip.id}/sos`)
      .set(rider.auth)
      .send({ lat: 41.327, lng: 69.229 })
      .expect(201);
    expect(again.body).toMatchObject({ incidentId: res.body.incidentId, repeat: true });
    expect(sent).toHaveLength(0);
    const incident = await prisma.safetyIncident.findUnique({ where: { id: res.body.incidentId } });
    expect(incident?.lat).toBeCloseTo(41.327);

    // Someone not on the trip cannot raise it.
    const stranger = await login(phone());
    await request(server).post(`/api/v1/trips/${trip.id}/sos`).set(stranger.auth).send({}).expect(403);

    // Counted for the SosRaised alert.
    const metrics = await request(server).get('/metrics').expect(200);
    expect(metrics.text).toMatch(/sos_alerts_total\{role="rider"\} [1-9]/);
  });

  it('ops see open incidents first and can acknowledge then resolve them', async () => {
    const rider = await login(phone());
    const trip = await prisma.trip.create({
      data: {
        riderId: rider.id,
        status: 'in_progress',
        pickupLat: 41.3,
        pickupLng: 69.24,
        dropoffLat: 41.31,
        dropoffLng: 69.25,
      },
    });
    const sos = await request(server)
      .post(`/api/v1/trips/${trip.id}/sos`)
      .set(rider.auth)
      .send({})
      .expect(201);
    // No contacts saved: nothing to text, but the incident still reaches ops.
    expect(sos.body).toMatchObject({ contactsNotified: 0, contactsTotal: 0 });

    const admin = await login(phone());
    await prisma.user.update({ where: { id: admin.id }, data: { role: 'admin' } });
    const adminAuth = (await login(await prisma.user
      .findUniqueOrThrow({ where: { id: admin.id } })
      .then((u) => u.phone))).auth;

    await request(server).get('/api/v1/admin/safety').set(rider.auth).expect(403);
    const list = await request(server).get('/api/v1/admin/safety').set(adminAuth).expect(200);
    const firstResolved = list.body.findIndex((i: { status: string }) => i.status === 'resolved');
    const ours = list.body.findIndex((i: { id: string }) => i.id === sos.body.incidentId);
    expect(ours).toBeGreaterThanOrEqual(0);
    if (firstResolved >= 0) expect(ours).toBeLessThan(firstResolved);
    expect(list.body[ours].status).toBe('open');

    await request(server)
      .patch(`/api/v1/admin/safety/${sos.body.incidentId}`)
      .set(adminAuth)
      .send({ status: 'acknowledged', note: 'Called the rider, she is safe.' })
      .expect(200);
    const resolved = await request(server)
      .patch(`/api/v1/admin/safety/${sos.body.incidentId}`)
      .set(adminAuth)
      .send({ status: 'resolved' })
      .expect(200);
    expect(resolved.body.status).toBe('resolved');
    expect(resolved.body.note).toBe('Called the rider, she is safe.');
    expect(resolved.body.acknowledgedAt).not.toBeNull();
    await request(server)
      .patch(`/api/v1/admin/safety/${sos.body.incidentId}`)
      .set(adminAuth)
      .send({ status: 'acknowledged' })
      .expect(400);
  });
});
