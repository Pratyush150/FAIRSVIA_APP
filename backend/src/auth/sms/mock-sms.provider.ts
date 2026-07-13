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
    this.logger.log(`📱  OTP for ${phone} is ${code}  (dev mock — no real SMS sent)`);
  }
}
