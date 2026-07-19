import { Global, Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PaymentsService } from './payments.service';
import { PaymentsController } from './payments.controller';
import { PaymentsAdminController } from './payments-admin.controller';
import { ConnectController } from './connect.controller';
import { WebhookController } from './webhook.controller';
import { PAYMENT_PROVIDER } from './payment-provider.interface';
import { MockPaymentProvider } from './mock-payment.provider';
import { StripePaymentProvider } from './stripe-payment.provider';

@Global()
@Module({
  controllers: [
    PaymentsController,
    PaymentsAdminController,
    ConnectController,
    WebhookController,
  ],
  providers: [
    PaymentsService,
    {
      provide: PAYMENT_PROVIDER,
      useFactory: (config: ConfigService) => {
        const key = config.get<string>('stripeSecretKey');
        if (key && key.length > 0) {
          Logger.log('Using Stripe payment provider', 'PaymentsModule');
          const base = config.get<string>('stripeApiBaseUrl');
          return new StripePaymentProvider(key, base);
        }
        return new MockPaymentProvider();
      },
      inject: [ConfigService],
    },
  ],
  exports: [PaymentsService],
})
export class PaymentsModule {}
