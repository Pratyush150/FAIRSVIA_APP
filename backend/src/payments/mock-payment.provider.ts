import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  AuthorizeParams,
  PaymentIntentResult,
  PaymentProvider,
} from './payment-provider.interface';

/**
 * Dev payment provider: simulates the auth-hold → capture → payout flow with
 * no real charges. Swap for Stripe by setting STRIPE_SECRET_KEY.
 */
@Injectable()
export class MockPaymentProvider implements PaymentProvider {
  private readonly logger = new Logger('MockPayments');

  constructor() {
    this.logger.warn('Using MOCK payment provider (no STRIPE_SECRET_KEY set).');
  }

  async authorize(params: AuthorizeParams): Promise<PaymentIntentResult> {
    this.assertAmount(params.amount);
    const intentId = `mock_pi_${randomUUID()}`;
    this.logger.log(`authorize ${params.currency} ${params.amount} → ${intentId}`);
    return { intentId, status: 'authorized' };
  }

  async capture(intentId: string, amount: number): Promise<PaymentIntentResult> {
    this.assertAmount(amount);
    this.logger.log(`capture ${intentId} amount=${amount}`);
    return { intentId, status: 'captured' };
  }

  async charge(params: AuthorizeParams): Promise<PaymentIntentResult> {
    this.assertAmount(params.amount);
    const intentId = `mock_ch_${randomUUID()}`;
    this.logger.log(`charge ${params.currency} ${params.amount} → ${intentId}`);
    return { intentId, status: 'captured' };
  }

  async refund(intentId: string): Promise<void> {
    this.logger.log(`refund ${intentId}`);
  }

  private assertAmount(amount: number): void {
    if (!(amount > 0)) {
      throw new BadRequestException('Amount must be greater than zero');
    }
  }
}
