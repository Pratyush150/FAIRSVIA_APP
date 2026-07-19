import { createHmac, timingSafeEqual } from 'node:crypto';

/** A minimal parsed Stripe event (only the fields we act on). */
export interface StripeEvent {
  id: string;
  type: string;
  data: { object: Record<string, any> };
}

export class WebhookVerificationError extends Error {}

/**
 * Verify a Stripe webhook signature and return the parsed event — a
 * dependency-free reimplementation of `stripe.webhooks.constructEvent`.
 *
 * The `Stripe-Signature` header looks like `t=<ts>,v1=<sig>[,v1=<sig>...]`; the
 * signed payload is `<ts>.<rawBody>` HMAC-SHA256'd with the endpoint secret.
 * Throws WebhookVerificationError on any mismatch (bad header, stale timestamp,
 * or no matching signature).
 */
export function verifyStripeSignature(
  rawBody: Buffer | string,
  signatureHeader: string | undefined,
  secret: string,
  toleranceSec = 300,
  nowSec: number = Math.floor(Date.now() / 1000),
): StripeEvent {
  if (!signatureHeader) {
    throw new WebhookVerificationError('Missing Stripe-Signature header');
  }
  const parts = signatureHeader.split(',').map((p) => p.trim());
  let timestamp = '';
  const v1: string[] = [];
  for (const part of parts) {
    const [k, val] = part.split('=');
    if (k === 't') timestamp = val;
    else if (k === 'v1' && val) v1.push(val);
  }
  if (!timestamp || v1.length === 0) {
    throw new WebhookVerificationError('Malformed Stripe-Signature header');
  }

  const ts = Number(timestamp);
  if (!Number.isFinite(ts) || Math.abs(nowSec - ts) > toleranceSec) {
    throw new WebhookVerificationError('Timestamp outside tolerance');
  }

  const payload =
    typeof rawBody === 'string' ? rawBody : rawBody.toString('utf8');
  const expected = createHmac('sha256', secret)
    .update(`${timestamp}.${payload}`, 'utf8')
    .digest('hex');
  const expectedBuf = Buffer.from(expected, 'utf8');

  const matches = v1.some((candidate) => {
    const candBuf = Buffer.from(candidate, 'utf8');
    return (
      candBuf.length === expectedBuf.length &&
      timingSafeEqual(candBuf, expectedBuf)
    );
  });
  if (!matches) {
    throw new WebhookVerificationError('Signature mismatch');
  }

  let event: StripeEvent;
  try {
    event = JSON.parse(payload);
  } catch {
    throw new WebhookVerificationError('Body is not valid JSON');
  }
  if (!event.id || !event.type) {
    throw new WebhookVerificationError('Event missing id/type');
  }
  return event;
}

/** Build a `Stripe-Signature` header for a payload — used by tests. */
export function signStripePayload(
  rawBody: string,
  secret: string,
  timestamp: number = Math.floor(Date.now() / 1000),
): string {
  const sig = createHmac('sha256', secret)
    .update(`${timestamp}.${rawBody}`, 'utf8')
    .digest('hex');
  return `t=${timestamp},v1=${sig}`;
}
