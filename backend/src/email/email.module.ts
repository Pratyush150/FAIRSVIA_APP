import { Global, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { EMAIL_PROVIDER } from './email-provider.interface';
import { MockEmailProvider } from './mock-email.provider';
import { SesEmailProvider } from './ses-email.provider';
import { EmailService } from './email.service';
import { AwsCreds } from '../common/aws/aws-sigv4';

/**
 * Global so EmailService can be injected anywhere (e.g. receipts on trip
 * completion) without importing this module everywhere. Chosen by
 * EMAIL_PROVIDER: `ses` uses Amazon SES when AWS creds + SES_FROM are set;
 * anything else falls back to the mock.
 */
@Global()
@Module({
  providers: [
    EmailService,
    {
      provide: EMAIL_PROVIDER,
      useFactory: (config: ConfigService) => {
        const provider = config.get<string>('emailProvider');
        if (provider === 'ses') {
          const aws = config.get<AwsCreds>('aws')!;
          const from = config.get<string>('sesFrom')!;
          return new SesEmailProvider(aws, from);
        }
        return new MockEmailProvider();
      },
      inject: [ConfigService],
    },
  ],
  exports: [EmailService],
})
export class EmailModule {}
