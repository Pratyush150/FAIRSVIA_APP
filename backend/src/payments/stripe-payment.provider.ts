import { BadGatewayException, Logger } from '@nestjs/common';
import {
  AuthorizeParams,
  PaymentIntentResult,
  PaymentProvider,
} from './payment-provider.interface';

/**
 * Real Stripe provider via the REST API (no SDK dependency). Selected when
 * STRIPE_SECRET_KEY is set. NOTE: exercised only once a real test key +
 * saved payment methods exist; until then the mock provider is used.
 * Amounts are converted to the smallest currency unit (e.g. paise).
 */
export class StripePaymentProvider implements PaymentProvider {
  private readonly logger = new Logger('StripePayments');
  private static readonly base = 'https://api.stripe.com/v1';

  constructor(private readonly secretKey: string) {
    this.logger.log('Using Stripe payment provider');
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

    const data = await this.post('/payment_intents', body);
    return { intentId: data.id as string, status: 'authorized' };
  }

  async capture(intentId: string, amount: number): Promise<PaymentIntentResult> {
    const data = await this.post(`/payment_intents/${intentId}/capture`, {
      amount_to_capture: String(this.minor(amount)),
    });
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
    const data = await this.post('/payment_intents', body);
    return { intentId: data.id as string, status: 'captured' };
  }

  async refund(intentId: string): Promise<void> {
    await this.post('/refunds', { payment_intent: intentId });
  }

  private minor(amount: number): number {
    return Math.round(amount * 100);
  }

  private async post(path: string, body: Record<string, string>): Promise<any> {
    let res: Response;
    try {
      res = await fetch(`${StripePaymentProvider.base}${path}`, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${this.secretKey}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: new URLSearchParams(body).toString(),
      });
    } catch (e) {
      throw new BadGatewayException(`Stripe unreachable: ${(e as Error).message}`);
    }
    const data = await res.json();
    if (!res.ok) {
      this.logger.error(`Stripe error: ${JSON.stringify(data.error ?? data)}`);
      throw new BadGatewayException(data.error?.message ?? 'Stripe error');
    }
    return data;
  }
}
