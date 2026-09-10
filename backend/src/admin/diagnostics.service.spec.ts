import { ConfigService } from '@nestjs/config';
import { DiagnosticsService } from './diagnostics.service';

function cfg(map: Record<string, unknown>): ConfigService {
  return { get: (k: string) => map[k] } as unknown as ConfigService;
}

describe('DiagnosticsService', () => {
  it('reports everything mock/stub when no keys are set', () => {
    const d = new DiagnosticsService(cfg({ smsProvider: 'mock', emailProvider: 'mock' }));
    const s = d.snapshot();
    expect(s.summary.real).toBe(0);
    expect(s.summary.total).toBe(6);
    expect(s.providers.find((p) => p.key === 'maps')!.mode).toBe('stub');
    expect(s.providers.find((p) => p.key === 'payments')!.ready).toBe(false);
    expect(s.providers.every((p) => !p.ready)).toBe(true);
  });

  it('reports real when every credential is present', () => {
    const d = new DiagnosticsService(
      cfg({
        googleMapsApiKey: 'AIza...',
        stripeSecretKey: 'sk_test_123',
        smsProvider: 'sns',
        aws: { accessKeyId: 'AKIA', secretAccessKey: 'secret', region: 'us-east-1' },
        emailProvider: 'ses',
        sesFrom: 'noreply@rideapp.example.com',
        fcmServiceAccountJson: '{"project_id":"x"}',
        checkr: { apiKey: 'checkr_live' },
      }),
    );
    const s = d.snapshot();
    expect(s.summary.real).toBe(6);
    expect(s.providers.find((p) => p.key === 'maps')!.service).toBe('Google Maps');
    expect(s.providers.find((p) => p.key === 'sms')!.service).toBe('Amazon SNS');
    expect(s.providers.every((p) => p.ready)).toBe(true);
  });

  it('SMS stays mock if SMS_PROVIDER=sns but AWS keys are missing', () => {
    const d = new DiagnosticsService(cfg({ smsProvider: 'sns', emailProvider: 'mock' }));
    expect(d.snapshot().providers.find((p) => p.key === 'sms')!.ready).toBe(false);
  });

  it('probe() reports all-unconfigured without making network calls', async () => {
    const d = new DiagnosticsService(cfg({}));
    const p = await d.probe();
    expect(p.results).toHaveLength(6);
    expect(p.results.every((r) => r.configured === false && r.ok === null)).toBe(true);
    expect(p.results.map((r) => r.key).sort()).toEqual([
      'background',
      'email',
      'maps',
      'payments',
      'push',
      'sms',
    ]);
  });
});
