import { createServer, IncomingMessage, Server } from 'http';
import { AddressInfo } from 'net';
import { StripePaymentProvider } from './stripe-payment.provider';

interface Hit {
  method?: string;
  url?: string;
  auth?: string;
  body?: string;
  idem?: string | string[];
  ver?: string | string[];
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
        idem: req.headers['idempotency-key'],
        ver: req.headers['stripe-version'],
      });
      if (fail.on) {
        res.writeHead(402, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: { message: 'card_declined' } }));
        return;
      }
      res.writeHead(200, { 'Content-Type': 'application/json' });
      // Path-aware bodies so the customer/setup-intent/card-list flows parse.
      const url = req.url ?? '';
      let payload: Record<string, unknown> = { id: 'pi_mock_123', status: 'succeeded' };
      if (url.startsWith('/customers')) payload = { id: 'cus_mock_1' };
      else if (url.startsWith('/ephemeral_keys')) payload = { id: 'ek_1', secret: 'ek_secret_1' };
      else if (url.startsWith('/setup_intents')) {
        payload = { id: 'seti_1', client_secret: 'seti_1_secret' };
      } else if (url.startsWith('/payment_methods')) {
        payload = { data: [{ id: 'pm_1', card: { brand: 'visa', last4: '4242' } }] };
      } else if (url.startsWith('/account_links')) {
        payload = { url: 'https://connect.stripe.com/setup/acct_mock_1' };
      } else if (url.startsWith('/accounts')) {
        payload = {
          id: 'acct_mock_1',
          payouts_enabled: true,
          details_submitted: true,
          charges_enabled: true,
        };
      } else if (url.startsWith('/transfers')) {
        payload = { id: 'tr_mock_1' };
      }
      res.end(JSON.stringify(payload));
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

  it('sends an Idempotency-Key header when one is supplied', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      await provider.authorize({
        amount: 10,
        currency: 'USD',
        idempotencyKey: 'idem-abc',
      });
      expect(hits[0].idem).toBe('idem-abc');
    } finally {
      server.close();
    }
  });

  it('creates a customer with the userId in metadata', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const ref = await provider.createCustomer({
        userId: 'u1',
        email: 'a@b.com',
        phone: '+15550001111',
      });
      expect(ref).toBe('cus_mock_1');
      expect(hits[0].url).toBe('/customers');
      const form = new URLSearchParams(hits[0].body);
      expect(form.get('metadata[userId]')).toBe('u1');
      expect(form.get('email')).toBe('a@b.com');
    } finally {
      server.close();
    }
  });

  it('creates an ephemeral key (pinned version) then a setup intent', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const setup = await provider.createSetupIntent('cus_mock_1');
      expect(setup).toEqual({
        id: 'seti_1',
        clientSecret: 'seti_1_secret',
        customerRef: 'cus_mock_1',
        ephemeralKeySecret: 'ek_secret_1',
      });
      // Ephemeral key first, carrying the pinned Stripe-Version header.
      expect(hits[0].url).toBe('/ephemeral_keys');
      expect(hits[0].ver).toBe('2024-06-20');
      expect(hits[1].url).toBe('/setup_intents');
      expect(new URLSearchParams(hits[1].body).get('customer')).toBe('cus_mock_1');
    } finally {
      server.close();
    }
  });

  it('lists a customer cards and maps brand/last4', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const cards = await provider.listCards('cus_mock_1');
      expect(cards).toEqual([{ ref: 'pm_1', brand: 'visa', last4: '4242' }]);
      expect(hits[0].method).toBe('GET');
      expect(hits[0].url).toContain('/payment_methods?customer=cus_mock_1');
      expect(hits[0].url).toContain('type=card');
    } finally {
      server.close();
    }
  });

  it('creates an Express connected account with the transfers capability', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const id = await provider.createConnectAccount({
        userId: 'd1',
        email: 'd@x.com',
      });
      expect(id).toBe('acct_mock_1');
      expect(hits[0].url).toBe('/accounts');
      const form = new URLSearchParams(hits[0].body);
      expect(form.get('type')).toBe('express');
      expect(form.get('capabilities[transfers][requested]')).toBe('true');
      expect(form.get('metadata[userId]')).toBe('d1');
    } finally {
      server.close();
    }
  });

  it('creates an onboarding account link', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const url = await provider.createAccountLink(
        'acct_mock_1',
        'ubernav://refresh',
        'ubernav://return',
      );
      expect(url).toBe('https://connect.stripe.com/setup/acct_mock_1');
      expect(hits[0].url).toBe('/account_links');
      const form = new URLSearchParams(hits[0].body);
      expect(form.get('account')).toBe('acct_mock_1');
      expect(form.get('type')).toBe('account_onboarding');
      expect(form.get('return_url')).toBe('ubernav://return');
    } finally {
      server.close();
    }
  });

  it('reads a connected account payout readiness', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const status = await provider.getAccount('acct_mock_1');
      expect(status).toEqual({
        payoutsEnabled: true,
        detailsSubmitted: true,
        chargesEnabled: true,
      });
      expect(hits[0].method).toBe('GET');
      expect(hits[0].url).toBe('/accounts/acct_mock_1');
    } finally {
      server.close();
    }
  });

  it('creates a payout transfer to the destination account', async () => {
    const { base, server, hits } = await mockStripe();
    try {
      const provider = new StripePaymentProvider('sk_test_x', base);
      const id = await provider.createTransfer({
        accountId: 'acct_mock_1',
        amount: 12.5,
        currency: 'USD',
        idempotencyKey: 'pay-1',
      });
      expect(id).toBe('tr_mock_1');
      expect(hits[0].url).toBe('/transfers');
      const form = new URLSearchParams(hits[0].body);
      expect(form.get('amount')).toBe('1250');
      expect(form.get('destination')).toBe('acct_mock_1');
      expect(hits[0].idem).toBe('pay-1');
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
