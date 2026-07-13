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
  };
  smsProvider: string;
  googleMapsApiKey: string;
  stripeSecretKey: string;
  platformFeePercent: number;
  cancellationFee: number;
  fcmServerKey: string;
  adminPhones: string[];
}

export default (): AppConfig => ({
  nodeEnv: process.env.NODE_ENV ?? 'development',
  port: parseInt(process.env.PORT ?? '3000', 10),
  databaseUrl: process.env.DATABASE_URL ?? '',
  redisUrl: process.env.REDIS_URL ?? 'redis://localhost:6379',
  jwt: {
    accessSecret: process.env.JWT_ACCESS_SECRET ?? 'dev_access_secret_change_me',
    refreshSecret: process.env.JWT_REFRESH_SECRET ?? 'dev_refresh_secret_change_me',
    accessTtl: process.env.JWT_ACCESS_TTL ?? '15m',
    refreshTtlDays: parseInt(process.env.JWT_REFRESH_TTL_DAYS ?? '30', 10),
  },
  otp: {
    ttlSeconds: parseInt(process.env.OTP_TTL_SECONDS ?? '300', 10),
    length: parseInt(process.env.OTP_LENGTH ?? '4', 10),
    maxAttempts: parseInt(process.env.OTP_MAX_ATTEMPTS ?? '5', 10),
  },
  smsProvider: process.env.SMS_PROVIDER ?? 'mock',
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
});
