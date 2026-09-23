import { BadGatewayException, Logger } from '@nestjs/common';
import {
  AuthorizeParams,
  CardInfo,
  ConnectAccountParams,
  ConnectAccountStatus,
  CustomerParams,
  PaymentIntentResult,
  PaymentProvider,
  ProviderRejectedException,
  SetupIntentResult,
  TransferParams,
} from './payment-provider.interface';

/**
 * Real Stripe provider via the REST API (no SDK dependency). Selected when
 * STRIPE_SECRET_KEY is set. NOTE: exercised only once a real test key +
 * saved payment methods exist; until then the mock provider is used.
 * Amounts are converted to the smallest currency unit (e.g. cents).
 */
export class StripePaymentProvider implements PaymentProvider {
  readonly needsSavedCard: boolean = true;
  private readonly logger = new Logger('StripePayments');

  // Pinned API version for the ephemeral key — must match what the mobile SDK
  // expects. flutter_stripe tracks recent Stripe versions; keep this current
  // with the SDK when upgrading.
  private static readonly EPHEMERAL_KEY_API_VERSION = '2024-06-20';

  constructor(
    private readonly secretKey: string,
    // Defaults to the live Stripe host; overridable (STRIPE_API_BASE_URL) so the
    // integration path can be validated against a local mock endpoint.
    private readonly base = 'https://api.stripe.com/v1',
  ) {
    this.logger.log(`Using Stripe payment provider (${this.base})`);
  }

  async authorize(params: AuthorizeParams): Promise<PaymentIntentResult> {
    const body: Record<string, string> = {
      amount: String(this.minor(params.amount)),
      currency: params.currency.toLowerCase(),
      capture_method: 'manual',
      confirm: 'true',
      'automatic_payment_methods[enabled]': 'true',
      'automatic_payment_methods[allow_redirects]': 'never',
    };
    if (params.customerRef) body.customer = params.customerRef;
    if (params.methodRef) body.payment_method = params.methodRef;
    if (params.description) body.description = params.description;

    const data = await this.post('/payment_intents', body, {
      idempotencyKey: params.idempotencyKey,
    });
    return { intentId: data.id as string, status: 'authorized' };
  }

  async capture(
    intentId: string,
    amount: number,
    idempotencyKey?: string,
  ): Promise<PaymentIntentResult> {
    const data = await this.post(
      `/payment_intents/${intentId}/capture`,
      { amount_to_capture: String(this.minor(amount)) },
      { idempotencyKey },
    );
    return { intentId: data.id as string, status: 'captured' };
  }

  async charge(params: AuthorizeParams): Promise<PaymentIntentResult> {
    const body: Record<string, string> = {
      amount: String(this.minor(params.amount)),
      currency: params.currency.toLowerCase(),
      capture_method: 'automatic',
      confirm: 'true',
      'automatic_payment_methods[enabled]': 'true',
      'automatic_payment_methods[allow_redirects]': 'never',
    };
    if (params.customerRef) body.customer = params.customerRef;
    if (params.methodRef) body.payment_method = params.methodRef;
    const data = await this.post('/payment_intents', body, {
      idempotencyKey: params.idempotencyKey,
    });
    return { intentId: data.id as string, status: 'captured' };
  }

  async refund(
    intentId: string,
    amount?: number,
    idempotencyKey?: string,
  ): Promise<string> {
    const body: Record<string, string> = { payment_intent: intentId };
    if (amount != null) body.amount = String(this.minor(amount));
    const data = await this.post('/refunds', body, { idempotencyKey });
    return data.id as string;
  }

  async createCustomer(params: CustomerParams): Promise<string> {
    const body: Record<string, string> = { 'metadata[userId]': params.userId };
    if (params.email) body.email = params.email;
    if (params.name) body.name = params.name;
    if (params.phone) body.phone = params.phone;
    const data = await this.post('/customers', body);
    return data.id as string;
  }

  async createSetupIntent(customerRef: string): Promise<SetupIntentResult> {
    // Ephemeral key first — the mobile SDK reads the customer's methods with it.
    const ephemeral = await this.post(
      '/ephemeral_keys',
      { customer: customerRef },
      { stripeVersion: StripePaymentProvider.EPHEMERAL_KEY_API_VERSION },
    );
    const intent = await this.post('/setup_intents', {
      customer: customerRef,
      usage: 'off_session',
      'automatic_payment_methods[enabled]': 'true',
      'automatic_payment_methods[allow_redirects]': 'never',
    });
    return {
      id: intent.id as string,
      clientSecret: intent.client_secret as string,
      customerRef,
      ephemeralKeySecret: ephemeral.secret as string,
    };
  }

  async listCards(customerRef: string): Promise<CardInfo[]> {
    const data = await this.get(
      `/payment_methods?customer=${encodeURIComponent(customerRef)}&type=card`,
    );
    const list = (data.data as any[]) ?? [];
    return list.map((pm) => ({
      ref: pm.id as string,
      brand: pm.card?.brand as string | undefined,
      last4: pm.card?.last4 as string | undefined,
    }));
  }

  async createConnectAccount(params: ConnectAccountParams): Promise<string> {
    const body: Record<string, string> = {
      type: 'express',
      'capabilities[transfers][requested]': 'true',
      'metadata[userId]': params.userId,
    };
    if (params.email) body.email = params.email;
    const data = await this.post('/accounts', body);
    return data.id as string;
  }

  async createAccountLink(
    accountId: string,
    refreshUrl: string,
    returnUrl: string,
  ): Promise<string> {
    const data = await this.post('/account_links', {
      account: accountId,
      refresh_url: refreshUrl,
      return_url: returnUrl,
      type: 'account_onboarding',
    });
    return data.url as string;
  }

  async getAccount(accountId: string): Promise<ConnectAccountStatus> {
    const data = await this.get(`/accounts/${encodeURIComponent(accountId)}`);
    return {
      payoutsEnabled: Boolean(data.payouts_enabled),
      detailsSubmitted: Boolean(data.details_submitted),
      chargesEnabled: Boolean(data.charges_enabled),
    };
  }

  async createTransfer(params: TransferParams): Promise<string> {
    const data = await this.post(
      '/transfers',
      {
        amount: String(this.minor(params.amount)),
        currency: params.currency.toLowerCase(),
        destination: params.accountId,
      },
      { idempotencyKey: params.idempotencyKey },
    );
    return data.id as string;
  }

  private minor(amount: number): number {
    return Math.round(amount * 100);
  }

  private async post(
    path: string,
    body: Record<string, string>,
    opts: { idempotencyKey?: string; stripeVersion?: string } = {},
  ): Promise<any> {
    const headers: Record<string, string> = {
      Authorization: `Bearer ${this.secretKey}`,
      'Content-Type': 'application/x-www-form-urlencoded',
    };
    if (opts.idempotencyKey) headers['Idempotency-Key'] = opts.idempotencyKey;
    if (opts.stripeVersion) headers['Stripe-Version'] = opts.stripeVersion;
    let res: Response;
    try {
      res = await fetch(`${this.base}${path}`, {
        method: 'POST',
        headers,
        body: new URLSearchParams(body).toString(),
      });
    } catch (e) {
      throw new BadGatewayException(`Stripe unreachable: ${(e as Error).message}`);
    }
    return this.parse(res);
  }

  private async get(path: string): Promise<any> {
    let res: Response;
    try {
      res = await fetch(`${this.base}${path}`, {
        method: 'GET',
        headers: { Authorization: `Bearer ${this.secretKey}` },
      });
    } catch (e) {
      throw new BadGatewayException(`Stripe unreachable: ${(e as Error).message}`);
    }
    return this.parse(res);
  }

  private async parse(res: Response): Promise<any> {
    const data = await res.json();
    if (!res.ok) {
      this.logger.error(`Stripe error: ${JSON.stringify(data.error ?? data)}`);
      const message = data.error?.message ?? 'Stripe error';
      // 4xx: Stripe answered and refused — nothing happened. 5xx or no answer
      // (see post/get): the outcome is unknown and must not be assumed failed.
      // 409 is excluded: it means the same idempotent request is still in
      // flight elsewhere, not that it was refused.
      if (res.status >= 400 && res.status < 500 && res.status !== 409) {
        throw new ProviderRejectedException(message);
      }
      throw new BadGatewayException(message);
    }
    return data;
  }
}
