import { BadGatewayException, Logger } from '@nestjs/common';
import { SmsProvider } from './sms-provider.interface';

/**
 * Real Twilio SMS provider via the REST API (no SDK dependency), mirroring the
 * hand-rolled `fetch` style of the Stripe/Google providers. Selected when
 * SMS_PROVIDER=twilio. `baseUrl` defaults to the live Twilio host but can be
 * pointed at a local mock endpoint (TWILIO_API_BASE_URL) so the integration
 * path is exercised end-to-end without real credentials or per-message cost.
 */
export class TwilioSmsProvider implements SmsProvider {
  private readonly logger = new Logger('TwilioSMS');

  constructor(
    private readonly accountSid: string,
    private readonly authToken: string,
    private readonly fromNumber: string,
    private readonly baseUrl: string,
  ) {
    if (!accountSid || !authToken || !fromNumber) {
      throw new Error(
        'TwilioSmsProvider requires TWILIO_ACCOUNT_SID, TWILIO_AUTH_TOKEN and TWILIO_FROM_NUMBER',
      );
    }
    this.logger.log(`Using Twilio SMS provider (${baseUrl})`);
  }

  async sendOtp(phone: string, code: string): Promise<void> {
    const path = `/2010-04-01/Accounts/${this.accountSid}/Messages.json`;
    const body = new URLSearchParams({
      To: phone,
      From: this.fromNumber,
      Body: `Your UberNav verification code is ${code}. It expires shortly. Do not share it.`,
    });

    let res: Response;
    try {
      res = await fetch(`${this.baseUrl}${path}`, {
        method: 'POST',
        headers: {
          // Twilio uses HTTP Basic auth: AccountSID:AuthToken.
          Authorization: `Basic ${Buffer.from(
            `${this.accountSid}:${this.authToken}`,
          ).toString('base64')}`,
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: body.toString(),
      });
    } catch (e) {
      throw new BadGatewayException(
        `Twilio unreachable: ${(e as Error).message}`,
      );
    }

    const data = (await res.json().catch(() => ({}))) as {
      sid?: string;
      status?: string;
      message?: string;
    };
    if (!res.ok) {
      // Never log the OTP itself; log Twilio's error only.
      this.logger.error(`Twilio error (${res.status}): ${data.message ?? '?'}`);
      throw new BadGatewayException(data.message ?? 'Twilio send failed');
    }
    this.logger.log(`OTP SMS queued to ${phone} (sid=${data.sid ?? '?'})`);
  }
}
