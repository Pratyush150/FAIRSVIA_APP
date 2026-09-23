import { BadRequestException, UnauthorizedException } from '@nestjs/common';
import { createHash } from 'node:crypto';
import { AuthService } from './auth.service';

/**
 * Unit tests for AuthService with hand-rolled mocks (no Nest DI container).
 * Redis is simulated with an in-memory Map so the OTP round-trip is real.
 */
function sha256(input: string): string {
  return createHash('sha256').update(input).digest('hex');
}

describe('AuthService', () => {
  let service: AuthService;
  let store: Map<string, string>;
  let counters: Map<string, number>;
  let sentOtp: { phone: string; code: string } | null;

  const prisma = {
    user: {
      upsert: jest.fn(async ({ where }: { where: { phone: string } }) => ({
        id: 'user-1',
        phone: where.phone,
        email: null,
        fullName: null,
        photoUrl: null,
        role: 'rider',
        ratingAvg: 5,
        ratingCount: 0,
      })),
      findUniqueOrThrow: jest.fn(),
      findUnique: jest.fn(),
    },
    refreshToken: {
      create: jest.fn(async () => ({ id: 'rt-1' })),
      deleteMany: jest.fn(async () => ({ count: 0 })),
      findFirst: jest.fn(),
      updateMany: jest.fn(async () => ({ count: 1 })),
    },
  };

  const redis = {
    get: jest.fn(async (k: string) => store.get(k) ?? null),
    setEx: jest.fn(async (k: string, v: string) => {
      store.set(k, v);
    }),
    del: jest.fn(async (k: string) => {
      store.delete(k);
    }),
    incrWithTtl: jest.fn(async (k: string) => {
      const next = (counters.get(k) ?? 0) + 1;
      counters.set(k, next);
      return next;
    }),
  };

  const jwt = {
    signAsync: jest.fn(async (payload: object) => `signed:${JSON.stringify(payload)}`),
    verifyAsync: jest.fn(),
  };

  const config = {
    get: jest.fn((key: string) => {
      switch (key) {
        case 'otp':
          return { ttlSeconds: 300, length: 6, maxAttempts: 5, devEcho: true };
        case 'jwt':
          return {
            accessSecret: 'a',
            refreshSecret: 'r',
            accessTtl: '15m',
            refreshTtlDays: 30,
          };
        case 'nodeEnv':
          return 'development';
        default:
          return undefined;
      }
    }),
  };

  const sms = {
    sendOtp: jest.fn(async (phone: string, code: string) => {
      sentOtp = { phone, code };
    }),
  };

  beforeEach(() => {
    store = new Map();
    counters = new Map();
    sentOtp = null;
    jest.clearAllMocks();
    service = new AuthService(
      prisma as never,
      redis as never,
      jwt as never,
      config as never,
      sms as never,
    );
  });

  describe('requestOtp', () => {
    it('generates a 6-digit code, stores its hash, and sends it', async () => {
      const res = await service.requestOtp('+19876543210');

      expect(sentOtp).not.toBeNull();
      expect(sentOtp!.code).toMatch(/^\d{6}$/);
      // Dev mode echoes the code back.
      expect(res.devCode).toBe(sentOtp!.code);
      // Stored value is the hash, never the plaintext.
      expect(store.get('otp:+19876543210')).toBe(sha256(sentOtp!.code));
    });

    describe('over the public edge', () => {
      const get = config.get as jest.Mock;
      const original = get.getMockImplementation();
      afterEach(() => get.mockImplementation(original));
      const withEcho = (phones: string[]) =>
        get.mockImplementation((key: string) => {
          if (key === 'otp') {
            return { ttlSeconds: 300, length: 6, maxAttempts: 5, devEcho: true, publicEchoPhones: phones };
          }
          if (key === 'adminPhones') return ['+19900000001'];
          return undefined;
        });

      it('shows the code only for listed numbers', async () => {
        withEcho(['+919000000001']);
        expect((await service.requestOtp('+919000000001', true)).devCode).toMatch(/^\d{6}$/);
        expect((await service.requestOtp('+919812345678', true)).devCode).toBeUndefined();
      });

      it('"*" shows it for any number — except the admin\'s', async () => {
        withEcho(['*']);
        expect((await service.requestOtp('+919812345678', true)).devCode).toMatch(/^\d{6}$/);
        expect((await service.requestOtp('+19900000001', true)).devCode).toBeUndefined();
      });
    });

    it('rate-limits after 5 requests in the window', async () => {
      for (let i = 0; i < 5; i++) {
        await service.requestOtp('+11111111111');
      }
      await expect(service.requestOtp('+11111111111')).rejects.toThrow(
        /too many otp requests/i,
      );
    });
  });

  describe('verifyOtp', () => {
    it('accepts the correct code, upserts the user, and issues tokens', async () => {
      const { devCode } = await service.requestOtp('+19876543210');
      const result = await service.verifyOtp('+19876543210', devCode!);

      expect(result.user.phone).toBe('+19876543210');
      expect(result.accessToken).toContain('signed:');
      expect(result.refreshToken).toContain('signed:');
      expect(prisma.refreshToken.create).toHaveBeenCalledTimes(1);
      // OTP is burned after success.
      expect(store.get('otp:+19876543210')).toBeUndefined();
    });

    it('rejects an incorrect code', async () => {
      const { devCode } = await service.requestOtp('+19876543210');
      const wrong = devCode === '0000' ? '1111' : '0000';
      await expect(service.verifyOtp('+19876543210', wrong)).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('rejects when no OTP was requested', async () => {
      await expect(service.verifyOtp('+10000000000', '1234')).rejects.toThrow(
        /expired or not requested/i,
      );
    });
  });

  describe('refresh', () => {
    const future = new Date(Date.now() + 60_000);
    const activeUser = { id: 'user-1', role: 'rider', isActive: true };

    beforeEach(() => {
      jwt.verifyAsync.mockResolvedValue({ sub: 'user-1', jti: 'j1' });
      prisma.user.findUnique.mockResolvedValue(activeUser);
      prisma.refreshToken.updateMany.mockResolvedValue({ count: 1 });
    });

    it('rotates a valid token: conditional revoke, then a new pair', async () => {
      prisma.refreshToken.findFirst.mockResolvedValue({
        id: 'rt-old', revoked: false, expiresAt: future,
      });
      const tokens = await service.refresh('old');
      expect(tokens.accessToken).toContain('signed:');
      // The revoke is conditional on revoked:false so a concurrent refresh can't
      // also succeed.
      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { id: 'rt-old', revoked: false },
        data: { revoked: true },
      });
      expect(prisma.refreshToken.create).toHaveBeenCalledTimes(1);
      // Expired rows for this user are pruned opportunistically.
      expect(prisma.refreshToken.deleteMany).toHaveBeenCalledWith({
        where: { userId: 'user-1', expiresAt: { lt: expect.any(Date) } },
      });
    });

    it('replaying a revoked token revokes ALL of the user\'s tokens (reuse detection)', async () => {
      prisma.refreshToken.findFirst.mockResolvedValue({
        id: 'rt-old', revoked: true, expiresAt: future,
      });
      await expect(service.refresh('replayed')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { userId: 'user-1', revoked: false },
        data: { revoked: true },
      });
      expect(prisma.refreshToken.create).not.toHaveBeenCalled();
    });

    it('losing the concurrent-claim race is treated as reuse', async () => {
      prisma.refreshToken.findFirst.mockResolvedValue({
        id: 'rt-old', revoked: false, expiresAt: future,
      });
      // First updateMany = the conditional claim → someone else got there.
      prisma.refreshToken.updateMany
        .mockResolvedValueOnce({ count: 0 })
        .mockResolvedValueOnce({ count: 2 });
      await expect(service.refresh('raced')).rejects.toBeInstanceOf(
        UnauthorizedException,
      );
      expect(prisma.refreshToken.updateMany).toHaveBeenNthCalledWith(2, {
        where: { userId: 'user-1', revoked: false },
        data: { revoked: true },
      });
      expect(prisma.refreshToken.create).not.toHaveBeenCalled();
    });

    it('rejects an expired token without issuing', async () => {
      prisma.refreshToken.findFirst.mockResolvedValue({
        id: 'rt-old', revoked: false, expiresAt: new Date(Date.now() - 1000),
      });
      await expect(service.refresh('expired')).rejects.toThrow(/expired or revoked/i);
      expect(prisma.refreshToken.create).not.toHaveBeenCalled();
    });

    it('rejects a deactivated user even with a valid token', async () => {
      prisma.refreshToken.findFirst.mockResolvedValue({
        id: 'rt-old', revoked: false, expiresAt: future,
      });
      prisma.user.findUnique.mockResolvedValue({ ...activeUser, isActive: false });
      await expect(service.refresh('ok')).rejects.toThrow(/not active/i);
      expect(prisma.refreshToken.create).not.toHaveBeenCalled();
    });

    it('rejects a token whose signature does not verify', async () => {
      jwt.verifyAsync.mockRejectedValue(new Error('bad sig'));
      await expect(service.refresh('garbage')).rejects.toThrow(/invalid refresh token/i);
      expect(prisma.refreshToken.findFirst).not.toHaveBeenCalled();
    });
  });

  describe('logout', () => {
    it('revokes only the presented token when one is given', async () => {
      prisma.refreshToken.updateMany.mockResolvedValue({ count: 1 });
      const res = await service.logout('user-1', 'the-token');
      expect(res).toEqual({ ok: true, revoked: 1 });
      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { userId: 'user-1', tokenHash: sha256('the-token'), revoked: false },
        data: { revoked: true },
      });
    });

    it('revokes every token (all devices) when no token is given', async () => {
      prisma.refreshToken.updateMany.mockResolvedValue({ count: 3 });
      const res = await service.logout('user-1');
      expect(res.revoked).toBe(3);
      expect(prisma.refreshToken.updateMany).toHaveBeenCalledWith({
        where: { userId: 'user-1', revoked: false },
        data: { revoked: true },
      });
    });
  });
});
