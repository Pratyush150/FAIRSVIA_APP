export const PAYMENT_PROVIDER = 'PAYMENT_PROVIDER';

export interface AuthorizeParams {
  amount: number;
  currency: string;
  customerRef?: string;
  methodRef?: string;
  description?: string;
}

export interface PaymentIntentResult {
  intentId: string;
  status: 'authorized' | 'captured' | 'failed';
}

/**
 * Abstraction over the payment gateway. The mock simulates the marketplace
 * flow (auth-hold → capture → payout) with no real charges; a Stripe
 * implementation is selected when STRIPE_SECRET_KEY is set.
 */
export interface PaymentProvider {
  /** Place an authorization hold (manual capture). */
  authorize(params: AuthorizeParams): Promise<PaymentIntentResult>;

  /** Capture a previously-authorized intent for the final amount. */
  capture(intentId: string, amount: number): Promise<PaymentIntentResult>;

  /** Immediate charge (tips, cancellation fees). */
  charge(params: AuthorizeParams): Promise<PaymentIntentResult>;

  /** Void/refund an intent (optionally a partial amount). */
  refund(intentId: string, amount?: number): Promise<void>;
}
