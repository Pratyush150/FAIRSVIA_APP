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

  it('boots with valid production config and disables the OTP echo', () => {
    withEnv(
      {
        NODE_ENV: 'production',
        JWT_ACCESS_SECRET: STRONG_A,
        JWT_REFRESH_SECRET: STRONG_B,
        DATABASE_URL: 'postgres://x',
        SMS_PROVIDER: 'twilio',
      },
      () => {
        const c = loadConfig();
        expect(c.otp.devEcho).toBe(false);
        expect(c.otp.length).toBe(6);
      },
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
