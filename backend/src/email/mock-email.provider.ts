import { Logger } from '@nestjs/common';
import { EmailMessage, EmailProvider } from './email-provider.interface';

/**
 * Mock email provider — logs the message instead of sending it. The default
 * when EMAIL_PROVIDER is unset/`mock`, so receipts and email flows are exercised
 * end-to-end in dev without SES credentials or per-message cost.
 */
export class MockEmailProvider implements EmailProvider {
  private readonly logger = new Logger('MockEmail');

  async send(msg: EmailMessage): Promise<void> {
    this.logger.log(
      `[mock email] to=${msg.to} subject="${msg.subject}" (not delivered)`,
    );
  }
}
