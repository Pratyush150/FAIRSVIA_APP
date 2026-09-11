import loadConfig from './configuration';

/** Snapshot & restore process.env around each case. */
function withEnv(env: Record<string, string | undefined>, fn: () => void) {
  const saved = { ...process.env };
  try {
    for (const [k, v] of Object.entries(env)) {
      if (v === undefined) delete process.env[k];
      else process.env[k] = v;
    }
    fn();
  } finally {
    process.env = saved;
  }
}

const STRONG_A = 'a'.repeat(40);
const STRONG_B = 'b'.repeat(40);

describe('configuration production guard', () => {
  it('throws when JWT secrets are unset in production', () => {
    withEnv(
      {
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: undefined,
        JWT_REFRESH_SECRET: undefined,
        DATABASE_URL: 'postgres://x',
        SMS_PROVIDER: 'twilio',
      },
      () => expect(() => loadConfig()).toThrow(/JWT_ACCESS_SECRET/),
    );
  });

  it('throws on a "change_me" placeholder secret', () => {
    withEnv(
      {
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: 'change_me_to_a_long_random_string_here',
        JWT_REFRESH_SECRET: STRONG_B,
        DATABASE_URL: 'postgres://x',
        SMS_PROVIDER: 'twilio',
      },
      () => expect(() => loadConfig()).toThrow(/placeholder/),
    );
  });

  it('throws when SMS_PROVIDER is mock in production', () => {
    withEnv(
      {
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: STRONG_A,
        JWT_REFRESH_SECRET: STRONG_B,
        DATABASE_URL: 'postgres://x',
        SMS_PROVIDER: 'mock',
      },
      () => expect(() => loadConfig()).toThrow(/SMS_PROVIDER/),
    );
  });

  /** A complete, valid production env; individual cases knock one value out. */
  const PROD_OK = {
    NODE_ENV: 'production',
    JWT_ACCESS_SECRET: STRONG_A,
    JWT_REFRESH_SECRET: STRONG_B,
    DATABASE_URL: 'postgres://x',
    SMS_PROVIDER: 'twilio',
    STRIPE_SECRET_KEY: 'sk_live_x',
    STRIPE_WEBHOOK_SECRET: 'whsec_x',
    DRIVER_AUTO_VERIFY: 'false',
  };

  it('boots with valid production config and disables the OTP echo', () => {
    withEnv(PROD_OK, () => {
      const c = loadConfig();
      expect(c.otp.devEcho).toBe(false);
      expect(c.otp.length).toBe(6);
      expect(c.driverAutoVerify).toBe(false);
      expect(c.stripeSecretKey).toBe('sk_live_x');
    });
  });

  it('refuses to boot in production without STRIPE_SECRET_KEY (mock provider = free rides)', () => {
    withEnv({ ...PROD_OK, STRIPE_SECRET_KEY: undefined }, () =>
      expect(() => loadConfig()).toThrow(/STRIPE_SECRET_KEY/),
    );
    withEnv({ ...PROD_OK, STRIPE_SECRET_KEY: '' }, () =>
      expect(() => loadConfig()).toThrow(/STRIPE_SECRET_KEY/),
    );
  });

  it('refuses to boot in production without STRIPE_WEBHOOK_SECRET', () => {
    withEnv({ ...PROD_OK, STRIPE_WEBHOOK_SECRET: undefined }, () =>
      expect(() => loadConfig()).toThrow(/STRIPE_WEBHOOK_SECRET/),
    );
  });

  it('refuses to boot in production when drivers would auto-verify', () => {
    withEnv({ ...PROD_OK, DRIVER_AUTO_VERIFY: 'true' }, () =>
      expect(() => loadConfig()).toThrow(/DRIVER_AUTO_VERIFY/),
    );
    // Unset defaults to false in production (explicit "false" also fine).
    withEnv({ ...PROD_OK, DRIVER_AUTO_VERIFY: undefined }, () =>
      expect(loadConfig().driverAutoVerify).toBe(false),
    );
  });

  it('keeps the dev defaults: mock payments and driver auto-verify', () => {
    withEnv(
      {
        NODE_ENV: 'development',
        STRIPE_SECRET_KEY: undefined,
        STRIPE_WEBHOOK_SECRET: undefined,
        DRIVER_AUTO_VERIFY: undefined,
      },
      () => {
        const c = loadConfig();
        expect(c.stripeSecretKey).toBe('');
        expect(c.driverAutoVerify).toBe(true);
      },
    );
    withEnv(
      { NODE_ENV: 'development', DRIVER_AUTO_VERIFY: 'false' },
      () => expect(loadConfig().driverAutoVerify).toBe(false),
    );
  });

  it('echoes the OTP only with the mock provider in a non-prod env', () => {
    withEnv(
      { NODE_ENV: 'development', SMS_PROVIDER: 'mock' },
      () => expect(loadConfig().otp.devEcho).toBe(true),
    );
    withEnv(
      { NODE_ENV: 'development', SMS_PROVIDER: 'twilio' },
      () => expect(loadConfig().otp.devEcho).toBe(false),
    );
  });
});
