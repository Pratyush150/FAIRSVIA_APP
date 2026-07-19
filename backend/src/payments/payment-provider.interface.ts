export const PAYMENT_PROVIDER = 'PAYMENT_PROVIDER';

export interface AuthorizeParams {
  amount: number;
  currency: string;
  customerRef?: string;
  methodRef?: string;
  description?: string;
  /** Stripe Idempotency-Key so a retried request never double-charges. */
  idempotencyKey?: string;
}

export interface PaymentIntentResult {
  intentId: string;
  status: 'authorized' | 'captured' | 'failed';
}

/** Details for lazily creating a Stripe Customer for a rider. */
export interface CustomerParams {
  userId: string;
  email?: string;
  name?: string;
  phone?: string;
}

/** A SetupIntent + the secrets the client PaymentSheet needs to save a card. */
export interface SetupIntentResult {
  id: string;
  clientSecret: string;
  customerRef: string;
  /** Short-lived key that lets the mobile SDK read the customer's methods. */
  ephemeralKeySecret?: string;
}

/** A saved card as the provider sees it. */
export interface CardInfo {
  ref: string; // payment_method id (pm_...)
  brand?: string;
  last4?: string;
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
  capture(
    intentId: string,
    amount: number,
    idempotencyKey?: string,
  ): Promise<PaymentIntentResult>;

  /** Immediate charge (tips, cancellation fees). */
  charge(params: AuthorizeParams): Promise<PaymentIntentResult>;

  /** Void/refund an intent (optionally a partial amount). */
  refund(intentId: string, amount?: number): Promise<void>;

  /** Create a Customer for a rider; returns the provider customer ref. */
  createCustomer(params: CustomerParams): Promise<string>;

  /** Create a SetupIntent (+ ephemeral key) so the client can save a card. */
  createSetupIntent(customerRef: string): Promise<SetupIntentResult>;

  /** List the customer's saved cards (to sync into our local table). */
  listCards(customerRef: string): Promise<CardInfo[]>;
}
