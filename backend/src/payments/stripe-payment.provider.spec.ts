import { createServer, IncomingMessage, Server } from 'http';
import { AddressInfo } from 'net';
import { StripePaymentProvider } from './stripe-payment.provider';

interface Hit {
  method?: string;
  url?: string;
  auth?: string;
  body?: string;
}

/** A mock Stripe that records every request and replies per-path. */
async function mockStripe(): Promise<{
  base: string;
  server: Server;
  hits: Hit[];
  fail: { on: boolean };
}> {
  const hits: Hit[] = [];
  const fail = { on: false };
  const server = createServer((req: IncomingMessage, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      hits.push({
        method: req.method,
        url: req.url,
        auth: req.headers.authorization,
        body,
      });
      if (fail.on) {
        res.writeHead(402, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'card_declined' } }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ id: 'pi_mock_123', status: 'succeeded' }));
    });
  });
  await new Promise<void>((r) => server.listen(0, '127.0.0.1', r));
  const { port } = server.address() as AddressInfo;
  return { base: `http://127.0.0.1:${port}`, server, hits, fail };
}

describe('StripePaymentProvider (real HTTP against a mock endpoint)', () => {
  it('authorizes with a manual-capture PaymentIntent in minor units', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const r = await provider.authorize({ amount: 12.34, currency: 'USD' });
      expect(r).toEqual({ intentId: 'pi_mock_123', status: 'authorized' });

      expect(hits[0].method).toBe('POST');
      expect(hits[0].url).toBe('/payment_intents');
      expect(hits[0].auth).toBe('Bearer sk_test_x');
      const form = new URLSearchParams(hits[0].body);
      expect(form.get('amount')).toBe('1234'); // dollars → cents
      expect(form.get('currency')).toBe('usd');
      expect(form.get('capture_method')).toBe('manual');
    } finally {
      server.close();
    }
  });

  it('captures against the intent id with amount_to_capture', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const r = await provider.capture('pi_abc', 10);
      expect(r.status).toBe('captured');
      expect(hits[0].url).toBe('/payment_intents/pi_abc/capture');
      expect(new URLSearchParams(hits[0].body).get('amount_to_capture')).toBe(
        '1000',
      );
    } finally {
      server.close();
    }
  });

  it('refunds by payment_intent', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      await provider.refund('pi_abc', 5);
      expect(hits[0].url).toBe('/refunds');
      const form = new URLSearchParams(hits[0].body);
      expect(form.get('payment_intent')).toBe('pi_abc');
      expect(form.get('amount')).toBe('500');
    } finally {
      server.close();
    }
  });

  it('surfaces a Stripe error as a gateway error', async () => {
    const { base, server, fail } = await mockStripe();
    fail.on = true;
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      await expect(
        provider.charge({ amount: 5, currency: 'USD' }),
      ).rejects.toThrow('card_declined');
    } finally {
      server.close();
    }
  });
});
