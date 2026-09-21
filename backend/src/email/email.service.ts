import { Inject, Injectable, Logger } from '@nestjs/common';
import {
  EMAIL_PROVIDER,
  EmailMessage,
  EmailProvider,
} from './email-provider.interface';

/**
 * Application-facing email API. Wraps the configured provider (SES or mock) and
 * is deliberately best-effort: a delivery failure is logged, never thrown into
 * the caller's flow — an unsendable receipt must not fail a completed ride.
 */
@Injectable()
export class EmailService {
  private readonly logger = new Logger('EmailService');

  constructor(@Inject(EMAIL_PROVIDER) private readonly provider: EmailProvider) {}

  async send(msg: EmailMessage): Promise<void> {
    try {
      await this.provider.send(msg);
    } catch (e) {
      this.logger.warn(`email send failed: ${(e as Error).message}`);
    }
  }

  /** Trip receipt email. No-op-safe if the rider has no email on file. */
  async sendReceipt(
    to: string | null | undefined,
    tripId: string,
    amount: number,
  ): Promise<void> {
    if (!to) return;
    const money = `$${amount.toFixed(2)}`;
    await this.send({
      to,
      subject: `Your FairsVia receipt — ${money}`,
      html:
        `<h2 style="font-family:sans-serif">Thanks for riding with FairsVia</h2>` +
        `<p style="font-family:sans-serif">Trip <strong>${tripId}</strong></p>` +
        `<p style="font-family:sans-serif">Total charged: <strong>${money}</strong></p>`,
      text: `Thanks for riding with FairsVia. Trip ${tripId}. Total charged: ${money}.`,
    });
  }
}
