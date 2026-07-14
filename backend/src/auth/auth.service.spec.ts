import { BadRequestException } from '@nestjs/common';
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
    },
    refreshToken: {
      create: jest.fn(async () => ({ id: 'rt-1' })),
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
      const res = await service.requestOtp('+919876543210');

      expect(sentOtp).not.toBeNull();
      expect(sentOtp!.code).toMatch(/^\d{6}$/);
      // Dev mode echoes the code back.
      expect(res.devCode).toBe(sentOtp!.code);
      // Stored value is the hash, never the plaintext.
      expect(store.get('otp:+919876543210')).toBe(sha256(sentOtp!.code));
    });

    it('rate-limits after 5 requests in the window', async () => {
      for (let i = 0; i < 5; i++) {
        await service.requestOtp('+911111111111');
      }
      await expect(service.requestOtp('+911111111111')).rejects.toThrow(
        /too many otp requests/i,
      );
    });
  });

  describe('verifyOtp', () => {
    it('accepts the correct code, upserts the user, and issues tokens', async () => {
      const { devCode } = await service.requestOtp('+919876543210');
      const result = await service.verifyOtp('+919876543210', devCode!);

      expect(result.user.phone).toBe('+919876543210');
      expect(result.accessToken).toContain('signed:');
      expect(result.refreshToken).toContain('signed:');
      expect(prisma.refreshToken.create).toHaveBeenCalledTimes(1);
      // OTP is burned after success.
      expect(store.get('otp:+919876543210')).toBeUndefined();
    });

    it('rejects an incorrect code', async () => {
      const { devCode } = await service.requestOtp('+919876543210');
      const wrong = devCode === '0000' ? '1111' : '0000';
      await expect(service.verifyOtp('+919876543210', wrong)).rejects.toBeInstanceOf(
        BadRequestException,
      );
    });

    it('rejects when no OTP was requested', async () => {
      await expect(service.verifyOtp('+910000000000', '1234')).rejects.toThrow(
        /expired or not requested/i,
      );
    });
  });
});
