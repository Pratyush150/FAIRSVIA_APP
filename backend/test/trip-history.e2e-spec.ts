import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';

/**
 * GET /trips/history carries what the rider Home's "Rate your ride with …"
 * card needs: the driver's name/photo/vehicle (never the phone) and the
 * rider's own rating of the trip (null until rated).
 */
describe('Trip history carries driver + myRating (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];

  const login = async () => {
    const phone = `+1996${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    userIds.push(r2.body.user.id);
    return {
      id: r2.body.user.id as string,
      phone,
      auth: { Authorization: `Bearer ${r2.body.accessToken}` },
    };
  };

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
  });

  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.driverProfile.deleteMany({ where: { userId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('rider rows carry driver name/photo/vehicle and myRating; no phone', async () => {
    const rider = await login();
    const driver = await login();
    await prisma.user.update({
      where: { id: driver.id },
      data: {
        fullName: 'Aziz Karimov',
        photoUrl: 'https://cdn.example/aziz.jpg',
        role: 'driver',
        driverProfile: {
          create: {
            vehicleMake: 'Chevrolet',
            vehicleModel: 'Cobalt',
            vehicleColor: 'White',
            plateNumber: '01A123BC',
          },
        },
      },
    });
    const trip = await prisma.trip.create({
      data: {
        riderId: rider.id,
        driverId: driver.id,
        status: 'completed',
        pickupLat: 41.31,
        pickupLng: 69.24,
        dropoffLat: 41.33,
        dropoffLng: 69.28,
        completedAt: new Date(),
      },
    });

    const before = await request(server)
      .get('/api/v1/trips/history')
      .set(rider.auth)
      .expect(200);
    const row = before.body.find((t: { id: string }) => t.id === trip.id);
    expect(row.driver).toEqual({
      name: 'Aziz Karimov',
      avatarUrl: 'https://cdn.example/aziz.jpg',
      vehicleLabel: 'White Chevrolet Cobalt',
      plate: '01A123BC',
    });
    expect(row.myRating).toBeNull();
    expect(JSON.stringify(before.body)).not.toContain(driver.phone);

    await request(server)
      .post(`/api/v1/trips/${trip.id}/rating`)
      .set(rider.auth)
      .send({ stars: 4 })
      .expect(201);

    const after = await request(server)
      .get('/api/v1/trips/history')
      .set(rider.auth)
      .expect(200);
    expect(after.body.find((t: { id: string }) => t.id === trip.id).myRating).toBe(4);

    // The driver's own history: no driver block, and their rating is theirs
    // (still null — the rider's 4 stars are not the driver's rating).
    const asDriver = await request(server)
      .get('/api/v1/trips/history')
      .set(driver.auth)
      .expect(200);
    const drow = asDriver.body.find((t: { id: string }) => t.id === trip.id);
    expect(drow.driver).toBeUndefined();
    // …but it names who they drove, and never with a phone number.
    if (drow.rider) {
      expect(Object.keys(drow.rider)).toEqual(['name']);
    }
    expect(JSON.stringify(asDriver.body)).not.toContain(rider.phone);
    expect(drow.myRating).toBeNull();
  });
});
