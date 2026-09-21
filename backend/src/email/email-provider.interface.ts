export const EMAIL_PROVIDER = 'EMAIL_PROVIDER';

export interface EmailMessage {
  to: string;
  subject: string;
  html: string;
  /** Optional plain-text alternative. */
  text?: string;
}

/**
 * Abstraction over transactional email delivery. Swap the mock for Amazon SES
 * (or any gateway) via EMAIL_PROVIDER without touching callers.
 */
export interface EmailProvider {
  send(msg: EmailMessage): Promise<void>;
}
