import { BadGatewayException, Logger } from '@nestjs/common';
import { SmsProvider } from './sms-provider.interface';
import { AwsCreds, signAwsRequest } from '../../common/aws/aws-sigv4';

/**
 * Amazon SNS SMS provider via the SNS query API + hand-rolled SigV4 (no SDK),
 * mirroring the fetch style of the Twilio/Stripe providers. Selected when
 * SMS_PROVIDER=sns. Sends the OTP as a Transactional SMS.
 *
 * While the AWS account is in the SMS sandbox, only phone numbers you've
 * verified in the SNS console receive messages — exactly what you want for
 * real-device testing before A2P 10DLC production access is granted.
 */
export class SnsSmsProvider implements SmsProvider {
  private readonly logger = new Logger('SnsSMS');

  constructor(private readonly creds: AwsCreds) {
    if (!creds.region || !creds.accessKeyId || !creds.secretAccessKey) {
      throw new Error(
        'SnsSmsProvider requires AWS_REGION, AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY',
      );
    }
    this.logger.log(`Using Amazon SNS SMS provider (region ${creds.region})`);
  }

  async sendOtp(phone: string, code: string): Promise<void> {
    const message = `Your FairsVia verification code is ${code}. It expires shortly. Do not share it.`;
    const body = new URLSearchParams({
      Action: 'Publish',
      Version: '2010-03-31',
      PhoneNumber: phone,
      Message: message,
      // Transactional SMS = highest delivery priority (OTP use case).
      'MessageAttributes.entry.1.Name': 'AWS.SNS.SMS.SMSType',
      'MessageAttributes.entry.1.Value.DataType': 'String',
      'MessageAttributes.entry.1.Value.StringValue': 'Transactional',
    }).toString();

    const signed = signAwsRequest({
      creds: this.creds,
      service: 'sns',
      method: 'POST',
      path: '/',
      body,
      contentType: 'application/x-www-form-urlencoded',
    });

    let res: Response;
    try {
      res = await fetch(signed.url, {
        method: 'POST',
        headers: signed.headers,
        body: signed.body,
      });
    } catch (e) {
      throw new BadGatewayException(`SNS unreachable: ${(e as Error).message}`);
    }

    if (!res.ok) {
      // SNS returns an XML error body; log a truncated form, never the OTP.
      const text = await res.text().catch(() => '');
      this.logger.error(`SNS error (${res.status}): ${text.slice(0, 200)}`);
      throw new BadGatewayException(`SNS send failed (${res.status})`);
    }
    this.logger.log(`OTP SMS queued to ${phone} via SNS`);
  }
}
