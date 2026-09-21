import { Injectable, Logger } from '@nestjs/common';
import { SmsProvider } from './sms-provider.interface';

/**
 * Dev SMS provider: prints the OTP to the backend console instead of
 * sending a real text. Read the code from `docker compose logs backend`.
 */
@Injectable()
export class MockSmsProvider implements SmsProvider {
  private readonly logger = new Logger('MockSMS');

  async sendOtp(phone: string, code: string): Promise<void> {
    // Only ever reveal the code outside production (this provider is barred from
    // production by the config guard, but never print a live OTP just in case a
    // staging/aggregated log pipeline is watching). Use debug level so default
    // production log levels wouldn't capture it even if it slipped through.
    if (process.env.NODE_ENV !== 'production') {
      this.logger.debug(
        `📱  OTP for ${phone} is ${code}  (dev mock — no real SMS sent)`,
      );
    } else {
      this.logger.log(`OTP dispatched to ${phone} (mock provider)`);
    }
  }

  async sendMessage(phone: string, message: string): Promise<void> {
    // Message bodies are not secrets the way an OTP is, but they can name a
    // passenger and a pickup, so keep them off default production levels too.
    if (process.env.NODE_ENV !== 'production') {
      this.logger.debug(`📱  SMS to ${phone}: ${message}  (dev mock)`);
    } else {
      this.logger.log(`SMS dispatched to ${phone} (mock provider)`);
    }
  }
}
