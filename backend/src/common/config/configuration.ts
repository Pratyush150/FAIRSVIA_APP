export interface AppConfig {
  nodeEnv: string;
  port: number;
  databaseUrl: string;
  redisUrl: string;
  jwt: {
    accessSecret: string;
    refreshSecret: string;
    accessTtl: string;
    refreshTtlDays: number;
  };
  otp: {
    ttlSeconds: number;
    length: number;
    maxAttempts: number;
    /** When true, the plaintext OTP is echoed in the request response (dev
     *  convenience with the mock SMS provider). Never true in production. */
    devEcho: boolean;
  };
  smsProvider: string;
  /** Allowed browser origins for CORS. Empty = reflect any origin (dev only). */
  corsOrigins: string[];
  googleMapsApiKey: string;
  stripeSecretKey: string;
  platformFeePercent: number;
  cancellationFee: number;
  fcmServerKey: string;
  adminPhones: string[];
  /** When true, driver documents are auto-approved at onboarding (dev default).
   *  When false, drivers onboard as pending and an admin must verify them
   *  before they can go online. */
  driverAutoVerify: boolean;
}

// Dev-only fallbacks. These MUST never be used in production — the guard below
// refuses to boot if they (or empty values) are in effect when NODE_ENV is
// 'production', so a misconfigured deploy fails loudly instead of shipping with
// a publicly-known signing key that would let anyone forge admin tokens.
const DEV_ACCESS_SECRET = 'dev_access_secret_change_me';
const DEV_REFRESH_SECRET = 'dev_refresh_secret_change_me';

export default (): AppConfig => {
  const nodeEnv = process.env.NODE_ENV ?? 'development';
  const isProd = nodeEnv === 'production';
  const accessSecret = process.env.JWT_ACCESS_SECRET ?? DEV_ACCESS_SECRET;
  const refreshSecret = process.env.JWT_REFRESH_SECRET ?? DEV_REFRESH_SECRET;
  const databaseUrl = process.env.DATABASE_URL ?? '';
  const smsProvider = process.env.SMS_PROVIDER ?? 'mock';
  // The OTP is only ever echoed back to the caller with the mock provider in a
  // non-production env — a real provider (or production) never reveals codes.
  const otpDevEcho = !isProd && smsProvider === 'mock';

  if (isProd) {
    const problems: string[] = [];
    // Reject unset, dev defaults, and obvious placeholders (the .example values
    // are ≥32 chars, so a length check alone wouldn't catch them).
    const isPlaceholder = (s: string) =>
      !s || s === DEV_ACCESS_SECRET || s === DEV_REFRESH_SECRET ||
      s.includes('change_me');
    if (!process.env.JWT_ACCESS_SECRET || isPlaceholder(accessSecret)) {
      problems.push('JWT_ACCESS_SECRET is unset, a dev default, or a placeholder');
    }
    if (!process.env.JWT_REFRESH_SECRET || isPlaceholder(refreshSecret)) {
      problems.push('JWT_REFRESH_SECRET is unset, a dev default, or a placeholder');
    }
    if (accessSecret === refreshSecret) {
      problems.push('JWT_ACCESS_SECRET and JWT_REFRESH_SECRET must differ');
    }
    if ((accessSecret ?? '').length < 32 || (refreshSecret ?? '').length < 32) {
      problems.push('JWT secrets must be at least 32 characters');
    }
    if (!databaseUrl) problems.push('DATABASE_URL is unset');
    // The mock SMS provider never delivers a code AND would otherwise be the
    // only way to log in — force a real provider so OTPs actually reach users
    // and are never echoed. Empty/unknown values fall back to mock in the
    // provider factory, so reject those too.
    if (!smsProvider || smsProvider === 'mock') {
      problems.push('SMS_PROVIDER must be a real provider (not empty or "mock")');
    }
    if (problems.length > 0) {
      throw new Error(
        `Refusing to start in production with insecure config:\n  - ${problems.join('\n  - ')}`,
      );
    }
  }

  return {
  nodeEnv,
  port: parseInt(process.env.PORT ?? '3000', 10),
  databaseUrl,
  redisUrl: process.env.REDIS_URL ?? 'redis://localhost:6379',
  jwt: {
    accessSecret,
    refreshSecret,
    accessTtl: process.env.JWT_ACCESS_TTL ?? '15m',
    refreshTtlDays: parseInt(process.env.JWT_REFRESH_TTL_DAYS ?? '30', 10),
  },
  otp: {
    ttlSeconds: parseInt(process.env.OTP_TTL_SECONDS ?? '300', 10),
    length: parseInt(process.env.OTP_LENGTH ?? '6', 10),
    maxAttempts: parseInt(process.env.OTP_MAX_ATTEMPTS ?? '5', 10),
    devEcho: otpDevEcho,
  },
  smsProvider,
  corsOrigins: (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0),
  googleMapsApiKey: process.env.GOOGLE_MAPS_API_KEY ?? '',
  stripeSecretKey: process.env.STRIPE_SECRET_KEY ?? '',
  platformFeePercent: parseFloat(process.env.PLATFORM_FEE_PERCENT ?? '0.20'),
  cancellationFee: parseFloat(process.env.CANCELLATION_FEE ?? '30'),
  fcmServerKey: process.env.FCM_SERVER_KEY ?? '',
  // Comma-separated phone numbers that are promoted to the admin role on login,
  // to bootstrap the self-hosted admin app without a manual DB edit.
  adminPhones: (process.env.ADMIN_PHONES ?? '')
    .split(',')
    .map((p) => p.trim())
    .filter((p) => p.length > 0),
  driverAutoVerify: (process.env.DRIVER_AUTO_VERIFY ?? 'true') !== 'false',
  };
};
