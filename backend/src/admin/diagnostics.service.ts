import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';

export type ProviderMode = 'real' | 'mock' | 'stub';

export interface ProviderStatus {
  /** stable key, e.g. 'maps' */
  key: string;
  /** human feature name */
  feature: string;
  /** which real service would be used */
  service: string;
  mode: ProviderMode;
  /** are the credentials present so the real provider is active? */
  configured: boolean;
  /** true when the real provider is active (not mock/stub) */
  ready: boolean;
  /** env vars the operator sets to turn this real */
  envVars: string[];
  note: string;
}

export interface DiagnosticsSnapshot {
  generatedAt: string;
  summary: { real: number; notReal: number; total: number };
  providers: ProviderStatus[];
}

/**
 * Operator-facing "is every external API wired?" check. After pasting a key
 * into .env and restarting, hit GET /admin/diagnostics to confirm the provider
 * flipped from mock → real. Reports configuration state only — it does NOT make
 * billable calls to the providers (that would cost money on every check); a true
 * end-to-end test is "send yourself an OTP / complete a ride", noted per row.
 */
@Injectable()
export class DiagnosticsService implements OnModuleInit {
  private readonly logger = new Logger('Diagnostics');

  constructor(private readonly config: ConfigService) {}

  onModuleInit(): void {
    // Startup checkpoint: one consolidated line per provider so the logs show
    // exactly what's live on boot.
    for (const p of this.snapshot().providers) {
      const tag = p.ready ? 'REAL' : p.mode.toUpperCase();
      this.logger.log(`[provider] ${p.key.padEnd(11)} → ${tag} (${p.service})`);
    }
  }

  snapshot(): DiagnosticsSnapshot {
    const providers = [
      this.maps(),
      this.payments(),
      this.sms(),
      this.email(),
      this.push(),
      this.background(),
    ];
    const real = providers.filter((p) => p.ready).length;
    return {
      generatedAt: new Date().toISOString(),
      summary: { real, notReal: providers.length - real, total: providers.length },
      providers,
    };
  }

  private has(v: unknown): boolean {
    return typeof v === 'string' && v.trim().length > 0;
  }

  private maps(): ProviderStatus {
    const google = this.has(this.config.get<string>('googleMapsApiKey'));
    const osm =
      this.has(this.config.get<string>('osrmBaseUrl')) &&
      this.has(this.config.get<string>('nominatimBaseUrl'));
    const service = google ? 'Google Maps' : osm ? 'Self-hosted OSM' : 'Stub';
    const mode: ProviderMode = google || osm ? 'real' : 'stub';
    return {
      key: 'maps',
      feature: 'Maps / routing / geocoding',
      service,
      mode,
      configured: google || osm,
      ready: mode === 'real',
      envVars: ['GOOGLE_MAPS_API_KEY', '(or OSRM_BASE_URL + NOMINATIM_BASE_URL)'],
      note: google
        ? 'Using Google. Verify: GET /places/autocomplete returns real results.'
        : osm
          ? 'Using self-hosted OSM (OSRM+Nominatim).'
          : 'STUB straight-line routes — set GOOGLE_MAPS_API_KEY for real maps.',
    };
  }

  private payments(): ProviderStatus {
    const configured = this.has(this.config.get<string>('stripeSecretKey'));
    return {
      key: 'payments',
      feature: 'Card payments + driver payouts',
      service: 'Stripe',
      mode: configured ? 'real' : 'mock',
      configured,
      ready: configured,
      envVars: ['STRIPE_SECRET_KEY', 'STRIPE_PUBLISHABLE_KEY', 'STRIPE_WEBHOOK_SECRET'],
      note: configured
        ? 'Using Stripe. Verify: run a test card through the rider app.'
        : 'MOCK payments — set STRIPE_SECRET_KEY (sk_test_… is fine) to go real.',
    };
  }

  private sms(): ProviderStatus {
    const provider = this.config.get<string>('smsProvider');
    const aws = this.config.get<{ accessKeyId: string; secretAccessKey: string }>('aws');
    const twilio = this.config.get<{ accountSid: string; authToken: string; fromNumber: string }>(
      'twilio',
    );
    const snsReady =
      provider === 'sns' && this.has(aws?.accessKeyId) && this.has(aws?.secretAccessKey);
    const twilioReady =
      provider === 'twilio' &&
      this.has(twilio?.accountSid) &&
      this.has(twilio?.authToken) &&
      this.has(twilio?.fromNumber);
    const ready = snsReady || twilioReady;
    return {
      key: 'sms',
      feature: 'Login-code (OTP) texts',
      service: provider === 'twilio' ? 'Twilio' : 'Amazon SNS',
      mode: ready ? 'real' : 'mock',
      configured: ready,
      ready,
      envVars: ['SMS_PROVIDER=sns', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'AWS_REGION'],
      note: ready
        ? 'Using a real SMS provider. Verify: request an OTP to a verified number.'
        : 'MOCK SMS (code echoed in dev). Set SMS_PROVIDER=sns + AWS creds to send real texts.',
    };
  }

  private email(): ProviderStatus {
    const aws = this.config.get<{ accessKeyId: string; secretAccessKey: string }>('aws');
    const ready =
      this.config.get<string>('emailProvider') === 'ses' &&
      this.has(aws?.accessKeyId) &&
      this.has(aws?.secretAccessKey) &&
      this.has(this.config.get<string>('sesFrom'));
    return {
      key: 'email',
      feature: 'Transactional email (receipts)',
      service: 'Amazon SES',
      mode: ready ? 'real' : 'mock',
      configured: ready,
      ready,
      envVars: ['EMAIL_PROVIDER=ses', 'AWS_ACCESS_KEY_ID', 'AWS_SECRET_ACCESS_KEY', 'SES_FROM'],
      note: ready
        ? 'Using SES. Verify: complete a ride → receipt email to a verified address.'
        : 'MOCK email. Set EMAIL_PROVIDER=ses + AWS creds + SES_FROM to send real email.',
    };
  }

  private push(): ProviderStatus {
    const configured = this.has(this.config.get<string>('fcmServiceAccountJson'));
    return {
      key: 'push',
      feature: 'Push notifications',
      service: 'Firebase FCM',
      mode: configured ? 'real' : 'mock',
      configured,
      ready: configured,
      envVars: ['FCM_SERVICE_ACCOUNT_JSON'],
      note: configured
        ? 'Using FCM HTTP v1. Verify: trip milestone push reaches a registered device.'
        : 'MOCK push. Set FCM_SERVICE_ACCOUNT_JSON (service-account JSON) to go real.',
    };
  }

  private background(): ProviderStatus {
    const checkr = this.config.get<{ apiKey: string }>('checkr');
    const configured = this.has(checkr?.apiKey);
    return {
      key: 'background',
      feature: 'Driver background checks',
      service: 'Checkr',
      mode: configured ? 'real' : 'mock',
      configured,
      ready: configured,
      envVars: ['CHECKR_API_KEY'],
      note: configured
        ? 'Using Checkr. Verify: initiate a check → status transitions from pending.'
        : 'MOCK background checks (auto-clear). Set CHECKR_API_KEY to go real.',
    };
  }
}
