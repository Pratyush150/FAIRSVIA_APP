import { BadGatewayException, Logger } from '@nestjs/common';
import { EmailMessage, EmailProvider } from './email-provider.interface';
import { AwsCreds, signAwsRequest } from '../common/aws/aws-sigv4';

/**
 * Amazon SES v2 email provider via the SendEmail REST endpoint + hand-rolled
 * SigV4 (no SDK). Selected when EMAIL_PROVIDER=ses. In the SES sandbox both the
 * sender and every recipient must be verified — fine for receipt testing before
 * production access is granted.
 */
export class SesEmailProvider implements EmailProvider {
  private readonly logger = new Logger('SesEmail');

  constructor(
    private readonly creds: AwsCreds,
    private readonly from: string,
  ) {
    if (!creds.region || !creds.accessKeyId || !creds.secretAccessKey) {
      throw new Error(
        'SesEmailProvider requires AWS_REGION, AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY',
      );
    }
    if (!from) throw new Error('SesEmailProvider requires SES_FROM');
    this.logger.log(
      `Using Amazon SES email provider (region ${creds.region}, from ${from})`,
    );
  }

  async send(msg: EmailMessage): Promise<void> {
    const payload = {
      FromEmailAddress: this.from,
      Destination: { ToAddresses: [msg.to] },
      Content: {
        Simple: {
          Subject: { Data: msg.subject, Charset: 'UTF-8' },
          Body: {
            Html: { Data: msg.html, Charset: 'UTF-8' },
            ...(msg.text
              ? { Text: { Data: msg.text, Charset: 'UTF-8' } }
              : {}),
          },
        },
      },
    };
    const body = JSON.stringify(payload);
    const signed = signAwsRequest({
      creds: this.creds,
      service: 'ses',
      method: 'POST',
      path: '/v2/email/outbound-emails',
      body,
      contentType: 'application/json',
    });

    let res: Response;
    try {
      res = await fetch(signed.url, {
        method: 'POST',
        headers: signed.headers,
        body: signed.body,
      });
    } catch (e) {
      throw new BadGatewayException(`SES unreachable: ${(e as Error).message}`);
    }

    if (!res.ok) {
      const text = await res.text().catch(() => '');
      this.logger.error(`SES error (${res.status}): ${text.slice(0, 200)}`);
      throw new BadGatewayException(`SES send failed (${res.status})`);
    }
    this.logger.log(`Email queued to ${msg.to} via SES`);
  }
}
