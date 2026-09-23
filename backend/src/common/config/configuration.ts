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
    /** Requests arriving through the public edge (Cloudflare tunnel / CDN)
     *  get the echoed code only for these phones — the pilot's demo
     *  accounts. Without it, anyone holding the public URL could read the
     *  login code for any number, the admin's included. `*` = every number
     *  except the ADMIN_PHONES (pilot testing with testers' own phones, no SMS
     *  provider yet). Empty = no echo over the public edge at all.
     *  On-network requests are unaffected. */
    publicEchoPhones: string[];
  };
  smsProvider: string;
  /** Twilio SMS credentials + endpoint. `baseUrl` defaults to the real Twilio
   *  host but can be pointed at a local mock endpoint for testing. */
  twilio: {
    accountSid: string;
    authToken: string;
    fromNumber: string;
    baseUrl: string;
  };
  /** Checkr driver-background-check credentials + endpoint. Empty apiKey selects
   *  the mock provider; `baseUrl` is overridable to a mock endpoint. */
  checkr: {
    apiKey: string;
    packageSlug: string;
    baseUrl: string;
  };
  /** Allowed browser origins for CORS. Empty = reflect any origin (dev only). */
  corsOrigins: string[];
  googleMapsApiKey: string;
  /** Self-hosted OpenStreetMap routing (OSRM) + geocoding (Nominatim) base
   *  URLs. When both are set (and no Google key), the OSM provider is used. */
  osrmBaseUrl: string;
  nominatimBaseUrl: string;
  stripeSecretKey: string;
  /** Publishable key (pk_...) — safe to hand to the client so flutter_stripe can
   *  tokenize cards. Empty means the app keeps the mock add-card flow. */
  stripePublishableKey: string;
  /** Signing secret (whsec_...) for verifying incoming Stripe webhooks. */
  stripeWebhookSecret: string;
  /** Deep links Stripe Connect onboarding returns to (driver app). */
  stripeConnectReturnUrl: string;
  stripeConnectRefreshUrl: string;
  /** Stripe API host; overridable to a local mock endpoint for testing. */
  stripeApiBaseUrl: string;
  platformFeePercent: number;
  cancellationFee: number;
  /** A driver may mark "arrived" only within this many metres of the pickup
   *  (checked against their last fresh GPS fix). */
  arrivalRadiusM: number;
  fcmServerKey: string;
  /** Google service-account JSON for FCM HTTP v1 push (real provider when set). */
  fcmServiceAccountJson: string;
  adminPhones: string[];
  /** When true, driver documents are auto-approved at onboarding (dev default).
   *  When false, drivers onboard as pending and an admin must verify them
   *  before they can go online. */
  driverAutoVerify: boolean;
  /** AWS region + IAM credentials shared by SNS (SMS) and SES (email). Empty
   *  keys select the mock providers. */
  aws: { region: string; accessKeyId: string; secretAccessKey: string };
  /** Transactional email provider: `ses` (real, when AWS creds + SES_FROM set)
   *  or `mock`. */
  emailProvider: string;
  /** Verified SES sender address used as the From on outgoing email. */
  sesFrom: string;
  /** Local emergency numbers shown in the SOS sheet, in display order. */
  emergencyNumbers: { label: string; number: string }[];
  /** IANA zone whose midnight starts a business day ("today" in earnings,
   *  dashboards, daily-active counts). The launch market is Tashkent. */
  businessTimezone: string;
}

/** Fail at boot on a typo'd zone rather than silently counting days in UTC. */
function validTimezone(tz: string): string {
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: tz });
  } catch {
    throw new Error(`BUSINESS_TZ "${tz}" is not a valid IANA time zone`);
  }
  return tz;
}

/**
 * `EMERGENCY_NUMBERS="Police:102,Ambulance:103"` → ordered list. The default
 * is Uzbekistan (the launch market; CIS numbering). Set it per country —
 * a wrong number here is worse than none.
 */
export function parseEmergencyNumbers(raw: string): { label: string; number: string }[] {
  return raw
    .split(',')
    .map((pair) => pair.split(':').map((x) => x.trim()))
    .filter(([label, number]) => label && number && /^[0-9+]{2,15}$/.test(number))
    .map(([label, number]) => ({ label, number }));
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
  const stripeSecretKey = process.env.STRIPE_SECRET_KEY ?? '';
  const stripeWebhookSecret = process.env.STRIPE_WEBHOOK_SECRET ?? '';
  // Dev default: auto-verify drivers (no admin in the loop). Production must
  // set it to "false" explicitly — the guard below refuses to boot otherwise.
  const driverAutoVerify =
    (process.env.DRIVER_AUTO_VERIFY ?? (isProd ? 'false' : 'true')) !== 'false';

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
    // An empty STRIPE_SECRET_KEY silently selects the MockPaymentProvider in
    // payments.module.ts — every ride would "succeed" without charging anyone.
    // The webhook secret is required too, or Stripe's payment_failed /
    // account.updated events are rejected and payment state silently drifts.
    if (!stripeSecretKey) {
      problems.push('STRIPE_SECRET_KEY is unset (would fall back to the mock payment provider)');
    }
    if (!stripeWebhookSecret) {
      problems.push('STRIPE_WEBHOOK_SECRET is unset (Stripe webhooks would be rejected)');
    }
    // Auto-verify lets anyone self-onboard as a verified driver with no admin
    // document review. It is a dev-only convenience.
    if (driverAutoVerify) {
      problems.push('DRIVER_AUTO_VERIFY must be "false" (drivers would self-verify)');
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
    publicEchoPhones: (process.env.OTP_PUBLIC_ECHO_PHONES ?? '')
      .split(',')
      .map((p) => p.trim())
      .filter(Boolean),
  },
  smsProvider,
  twilio: {
    accountSid: process.env.TWILIO_ACCOUNT_SID ?? '',
    authToken: process.env.TWILIO_AUTH_TOKEN ?? '',
    fromNumber: process.env.TWILIO_FROM_NUMBER ?? '',
    baseUrl: process.env.TWILIO_API_BASE_URL ?? 'https://api.twilio.com',
  },
  checkr: {
    apiKey: process.env.CHECKR_API_KEY ?? '',
    packageSlug: process.env.CHECKR_PACKAGE ?? 'driver_standard',
    baseUrl: process.env.CHECKR_API_BASE_URL ?? 'https://api.checkr.com/v1',
  },
  corsOrigins: (process.env.CORS_ORIGINS ?? '')
    .split(',')
    .map((o) => o.trim())
    .filter((o) => o.length > 0),
  googleMapsApiKey: process.env.GOOGLE_MAPS_API_KEY ?? '',
  osrmBaseUrl: process.env.OSRM_BASE_URL ?? '',
  nominatimBaseUrl: process.env.NOMINATIM_BASE_URL ?? '',
  stripeSecretKey,
  stripePublishableKey: process.env.STRIPE_PUBLISHABLE_KEY ?? '',
  stripeWebhookSecret,
  stripeConnectReturnUrl:
    process.env.STRIPE_CONNECT_RETURN_URL ?? 'fairsvia-driver://connect/return',
  stripeConnectRefreshUrl:
    process.env.STRIPE_CONNECT_REFRESH_URL ?? 'fairsvia-driver://connect/refresh',
  stripeApiBaseUrl: process.env.STRIPE_API_BASE_URL ?? 'https://api.stripe.com/v1',
  platformFeePercent: parseFloat(process.env.PLATFORM_FEE_PERCENT ?? '0.20'),
  cancellationFee: parseFloat(process.env.CANCELLATION_FEE ?? '5'),
  arrivalRadiusM: parseFloat(process.env.ARRIVAL_RADIUS_M ?? '150'),
  fcmServerKey: process.env.FCM_SERVER_KEY ?? '',
  fcmServiceAccountJson: process.env.FCM_SERVICE_ACCOUNT_JSON ?? '',
  // Comma-separated phone numbers that are promoted to the admin role on login,
  // to bootstrap the self-hosted admin app without a manual DB edit.
  adminPhones: (process.env.ADMIN_PHONES ?? '')
    .split(',')
    .map((p) => p.trim())
    .filter((p) => p.length > 0),
  driverAutoVerify,
  aws: {
    region: process.env.AWS_REGION ?? 'us-east-1',
    accessKeyId: process.env.AWS_ACCESS_KEY_ID ?? '',
    secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY ?? '',
  },
  emailProvider: process.env.EMAIL_PROVIDER ?? 'mock',
  sesFrom: process.env.SES_FROM ?? 'noreply@rideapp.example.com',
  emergencyNumbers: parseEmergencyNumbers(
    process.env.EMERGENCY_NUMBERS ?? 'Police:102,Ambulance:103,Fire:101',
  ),
  businessTimezone: validTimezone(process.env.BUSINESS_TZ ?? 'Asia/Tashkent'),
  };
};
