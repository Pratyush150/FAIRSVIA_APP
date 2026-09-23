import { BadGatewayException } from '@nestjs/common';

/**
 * The provider answered and definitively refused (declined card, invalid
 * account, insufficient platform balance): nothing moved. Distinct from a
 * plain BadGatewayException, which means the outcome is UNKNOWN (timeout,
 * 5xx) — callers must not treat that as "failed" when money may have moved.
 */
export class ProviderRejectedException extends BadGatewayException {}

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

/** Details for opening a Connect Express account for a driver. */
export interface ConnectAccountParams {
  userId: string;
  email?: string;
}

/** A Connect account's onboarding/payout readiness. */
export interface ConnectAccountStatus {
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
  chargesEnabled: boolean;
}

/** A payout transfer to a connected account. */
export interface TransferParams {
  accountId: string;
  amount: number;
  currency: string;
  idempotencyKey?: string;
}

/**
 * Abstraction over the payment gateway. The mock simulates the marketplace
 * flow (auth-hold → capture → payout) with no real charges; a Stripe
 * implementation is selected when STRIPE_SECRET_KEY is set.
 */
export interface PaymentProvider {
  /**
   * Whether a card ride can only be charged against a card the rider saved.
   * True for a real processor. The mock simulates an always-present card, so
   * dev and test flows can book card rides without the add-card step.
   */
  readonly needsSavedCard: boolean;

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

  /** Void/refund an intent (optionally a partial amount). `idempotencyKey`
   *  is derived from our committed refund record so a retry never refunds
   *  twice; returns the provider's refund id when it has one. */
  refund(
    intentId: string,
    amount?: number,
    idempotencyKey?: string,
  ): Promise<string | void>;

  /** Create a Customer for a rider; returns the provider customer ref. */
  createCustomer(params: CustomerParams): Promise<string>;

  /** Create a SetupIntent (+ ephemeral key) so the client can save a card. */
  createSetupIntent(customerRef: string): Promise<SetupIntentResult>;

  /** List the customer's saved cards (to sync into our local table). */
  listCards(customerRef: string): Promise<CardInfo[]>;

  /** Open a Connect Express account for a driver; returns the account ref. */
  createConnectAccount(params: ConnectAccountParams): Promise<string>;

  /** Hosted onboarding link the driver completes KYC + bank details on. */
  createAccountLink(
    accountId: string,
    refreshUrl: string,
    returnUrl: string,
  ): Promise<string>;

  /** Read a connected account's onboarding/payout readiness. */
  getAccount(accountId: string): Promise<ConnectAccountStatus>;

  /** Transfer funds to a connected account (driver payout); returns its id. */
  createTransfer(params: TransferParams): Promise<string>;
}
