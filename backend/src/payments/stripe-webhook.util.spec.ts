import {
  signStripePayload,
  verifyStripeSignature,
  WebhookVerificationError,
} from './stripe-webhook.util';

describe('verifyStripeSignature', () => {
  const secret = 'whsec_test_123';
  const body = JSON.stringify({
    id: 'evt_1',
    type: 'payment_intent.succeeded',
    data: { object: { id: 'pi_1' } },
  });

  it('accepts a correctly signed payload and returns the event', () => {
    const header = signStripePayload(body, secret);
    const event = verifyStripeSignature(body, header, secret);
    expect(event.id).toBe('evt_1');
    expect(event.type).toBe('payment_intent.succeeded');
    expect(event.data.object.id).toBe('pi_1');
  });

  it('rejects a missing signature header', () => {
    expect(() => verifyStripeSignature(body, undefined, secret)).toThrow(
      WebhookVerificationError,
    );
  });

  it('rejects a tampered body (signature mismatch)', () => {
    const header = signStripePayload(body, secret);
    const tampered = body.replace('pi_1', 'pi_evil');
    expect(() => verifyStripeSignature(tampered, header, secret)).toThrow(
      /mismatch/i,
    );
  });

  it('rejects the wrong secret', () => {
    const header = signStripePayload(body, secret);
    expect(() => verifyStripeSignature(body, header, 'whsec_other')).toThrow(
      /mismatch/i,
    );
  });

  it('rejects a stale timestamp outside tolerance', () => {
    const ts = 1_000_000; // ancient
    const header = signStripePayload(body, secret, ts);
    // "now" far in the future relative to the signed timestamp.
    expect(() =>
      verifyStripeSignature(body, header, secret, 300, ts + 10_000),
    ).toThrow(/tolerance/i);
  });

  it('rejects a malformed header', () => {
    expect(() => verifyStripeSignature(body, 'garbage', secret)).toThrow(
      /malformed/i,
    );
  });
});
