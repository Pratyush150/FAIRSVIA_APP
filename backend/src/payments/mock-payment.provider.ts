import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  AuthorizeParams,
  CardInfo,
  CustomerParams,
  PaymentIntentResult,
  PaymentProvider,
  SetupIntentResult,
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

  async capture(
    intentId: string,
    amount: number,
    _idempotencyKey?: string,
  ): Promise<PaymentIntentResult> {
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

  async refund(intentId: string, amount?: number): Promise<void> {
    this.logger.log(
      `refund ${intentId}${amount != null ? ` amount=${amount}` : ' (full)'}`,
    );
  }

  async createCustomer(params: CustomerParams): Promise<string> {
    const id = `mock_cus_${params.userId.slice(0, 8)}`;
    this.logger.log(`createCustomer ${params.userId} → ${id}`);
    return id;
  }

  async createSetupIntent(customerRef: string): Promise<SetupIntentResult> {
    const id = `mock_seti_${randomUUID()}`;
    return {
      id,
      clientSecret: `${id}_secret_${randomUUID()}`,
      customerRef,
      ephemeralKeySecret: `mock_ek_${randomUUID()}`,
    };
  }

  async listCards(_customerRef: string): Promise<CardInfo[]> {
    // The mock never holds real cards; card rows are added via addMethod.
    return [];
  }

  private assertAmount(amount: number): void {
    if (!(amount > 0)) {
      throw new BadRequestException('Amount must be greater than zero');
    }
  }
}
