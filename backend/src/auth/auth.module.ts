import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthService } from './auth.service';
import { AuthController } from './auth.controller';
import { JwtStrategy } from './strategies/jwt.strategy';
import { SMS_PROVIDER } from './sms/sms-provider.interface';
import { MockSmsProvider } from './sms/mock-sms.provider';

@Module({
  imports: [
    PassportModule,
    // Secrets are passed per-sign/verify call in AuthService, so register empty.
    JwtModule.register({}),
  ],
  controllers: [AuthController],
  providers: [
    AuthService,
    JwtStrategy,
    {
      // Chosen by config; today always the mock. Swap to Twilio later.
      provide: SMS_PROVIDER,
      useFactory: (config: ConfigService) => {
        const provider = config.get<string>('smsProvider');
        switch (provider) {
          case 'mock':
          default:
            return new MockSmsProvider();
        }
      },
      inject: [ConfigService],
    },
  ],
  exports: [AuthService],
})
export class AuthModule {}
