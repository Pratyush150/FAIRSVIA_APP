import { Logger, Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { BackgroundService } from './background.service';
import {
  BackgroundController,
  BackgroundAdminController,
} from './background.controller';
import { BACKGROUND_CHECK_PROVIDER } from './background-check.interface';
import { MockBackgroundProvider } from './mock-background.provider';
import { CheckrBackgroundProvider } from './checkr-background.provider';

@Module({
  controllers: [BackgroundController, BackgroundAdminController],
  providers: [
    BackgroundService,
    {
      // Real Checkr when CHECKR_API_KEY is set; otherwise the in-memory mock.
      provide: BACKGROUND_CHECK_PROVIDER,
      useFactory: (config: ConfigService) => {
        const c = config.get<{
          apiKey: string;
          packageSlug: string;
          baseUrl: string;
        }>('checkr')!;
        if (c.apiKey && c.apiKey.length > 0) {
          Logger.log('Using Checkr background-check provider', 'BackgroundModule');
          return new CheckrBackgroundProvider(c.apiKey, c.packageSlug, c.baseUrl);
        }
        return new MockBackgroundProvider();
      },
      inject: [ConfigService],
    },
  ],
  exports: [BackgroundService],
})
export class BackgroundModule {}
