import { INestApplication, RequestMethod, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import request from 'supertest';
import { AppModule } from '../src/app.module';
import { PrismaService } from '../src/common/prisma/prisma.service';
import { RedisService } from '../src/common/redis/redis.service';
import { PAYMENT_PROVIDER } from '../src/payments/payment-provider.interface';
import { MockPaymentProvider } from '../src/payments/mock-payment.provider';

/** A real processor (like Stripe) can only charge a card the rider saved. */
class CardOnlyProvider extends MockPaymentProvider {
  override readonly needsSavedCard = true;
}

describe('Card rides need a card (e2e)', () => {
  let app: INestApplication;
  let server: ReturnType<INestApplication['getHttpServer']>;
  let prisma: PrismaService;
  let redis: RedisService;
  const userIds: string[] = [];

  const login = async () => {
    const phone = `+1998${Math.floor(1e6 + Math.random() * 8e6)}`;
    await redis.del(`otp:rate:${phone}`);
    const r1 = await request(server).post('/api/v1/auth/otp/request').send({ phone });
    const r2 = await request(server)
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: r1.body.devCode });
    userIds.push(r2.body.user.id);
    return { id: r2.body.user.id as string, auth: { Authorization: `Bearer ${r2.body.accessToken}` } };
  };

  const book = (auth: Record<string, string>, body: object = {}) =>
    request(server)
      .post('/api/v1/trips')
      .set(auth)
      .send({
        pickupLat: 28.6139,
        pickupLng: 77.209,
        dropoffLat: 28.62,
        dropoffLng: 77.22,
        tier: 'economy',
        ...body,
      });

  beforeAll(async () => {
    const moduleRef = await Test.createTestingModule({ imports: [AppModule] })
      .overrideProvider(PAYMENT_PROVIDER)
      .useValue(new CardOnlyProvider())
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

  afterAll(async () => {
    await prisma.trip.deleteMany({ where: { riderId: { in: userIds } } });
    await prisma.user.deleteMany({ where: { id: { in: userIds } } });
    await app.close();
  }, 60_000);

  it('refuses a card ride from a rider with no card, and books nothing', async () => {
    const rider = await login();
    const res = await book(rider.auth).expect(400);
    expect(res.body.code).toBe('PAYMENT_METHOD_REQUIRED');
    expect(await prisma.trip.count({ where: { riderId: rider.id } })).toBe(0);
  });

  it('still books cash for the same rider', async () => {
    const rider = await login();
    await book(rider.auth, { paymentMode: 'cash' }).expect(201);
  });

  it('books a card ride once the rider has a default card, or picks one', async () => {
    const savedCard = async (userId: string, isDefault: boolean) =>
      prisma.paymentMethod.create({ data: { userId, brand: 'visa', last4: '4242', isDefault } });

    // A saved card that is not the default, picked explicitly at booking.
    const picker = await login();
    const card = await savedCard(picker.id, false);
    await book(picker.auth, { paymentMethodId: card.id }).expect(201);

    // The same kind of card, neither picked nor the default: nothing to charge.
    const unpicked = await login();
    await savedCard(unpicked.id, false);
    const refused = await book(unpicked.auth).expect(400);
    expect(refused.body.code).toBe('PAYMENT_METHOD_REQUIRED');

    // A default card is charged without being picked.
    const withDefault = await login();
    await savedCard(withDefault.id, true);
    await book(withDefault.auth).expect(201);
  });
});
