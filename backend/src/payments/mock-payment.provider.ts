import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import {
  AuthorizeParams,
  CardInfo,
  ConnectAccountParams,
  ConnectAccountStatus,
  CustomerParams,
  PaymentIntentResult,
  PaymentProvider,
  SetupIntentResult,
  TransferParams,
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

  async createConnectAccount(params: ConnectAccountParams): Promise<string> {
    const id = `mock_acct_${params.userId.slice(0, 8)}`;
    this.logger.log(`createConnectAccount ${params.userId} → ${id}`);
    return id;
  }

  async createAccountLink(
    accountId: string,
    _refreshUrl: string,
    _returnUrl: string,
  ): Promise<string> {
    // No real onboarding in mock — hand back a placeholder the client can open
    // (or skip). getAccount reports the mock account as fully enabled.
    return `https://connect.stripe.test/onboard/${accountId}`;
  }

  async getAccount(_accountId: string): Promise<ConnectAccountStatus> {
    // Mock accounts are treated as fully onboarded so dev payouts flow.
    return { payoutsEnabled: true, detailsSubmitted: true, chargesEnabled: true };
  }

  async createTransfer(params: TransferParams): Promise<string> {
    this.assertAmount(params.amount);
    const id = `mock_tr_${randomUUID()}`;
    this.logger.log(
      `transfer ${params.currency} ${params.amount} → ${params.accountId} (${id})`,
    );
    return id;
  }

  private assertAmount(amount: number): void {
    if (!(amount > 0)) {
      throw new BadRequestException('Amount must be greater than zero');
    }
  }
}
