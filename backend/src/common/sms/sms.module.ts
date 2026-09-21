import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { SMS_PROVIDER } from '../../auth/sms/sms-provider.interface';
import { MockSmsProvider } from '../../auth/sms/mock-sms.provider';
import { TwilioSmsProvider } from '../../auth/sms/twilio-sms.provider';
import { SnsSmsProvider } from '../../auth/sms/sns-sms.provider';
import { AwsCreds } from '../aws/aws-sigv4';

/**
 * The SMS gateway, shared. It started inside AuthModule because only login
 * OTPs needed it; it is now also how a passenger on somebody else's booking is
 * reached (they get the start code and the arrival nudge, and may never have
 * installed the app). Global, like Redis and the queue, so a feature module
 * can send a message without importing AuthModule and risking a cycle.
 *
 * Chosen by SMS_PROVIDER: the real providers make HTTP calls, the mock logs
 * (and is barred from production by the config guard).
 */
@Global()
@Module({
  providers: [
    {
      provide: SMS_PROVIDER,
      useFactory: (config: ConfigService) => {
        const provider = config.get<string>('smsProvider');
        switch (provider) {
          case 'twilio': {
            const t = config.get<{
              accountSid: string;
              authToken: string;
              fromNumber: string;
              baseUrl: string;
            }>('twilio')!;
            return new TwilioSmsProvider(
              t.accountSid,
              t.authToken,
              t.fromNumber,
              t.baseUrl,
            );
          }
          case 'sns': {
            const aws = config.get<AwsCreds>('aws')!;
            return new SnsSmsProvider(aws);
          }
          case 'mock':
          default:
            return new MockSmsProvider();
        }
      },
      inject: [ConfigService],
    },
  ],
  exports: [SMS_PROVIDER],
})
export class SmsModule {}
