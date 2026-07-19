import { Controller, Get, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { PaymentsService } from './payments.service';

/**
 * Driver Stripe Connect Express onboarding + payout readiness. Auth-only (like
 * the rest of the drivers API — the JWT role can still be `rider` right after
 * onboarding); the connected account is keyed to the driver's own profile.
 */
@Controller('drivers/connect')
@UseGuards(JwtAuthGuard)
export class ConnectController {
  constructor(private readonly payments: PaymentsService) {}

  /** Create (or resume) the connected account and return a hosted onboarding link. */
  @Post('onboard')
  @HttpCode(HttpStatus.OK)
  onboard(@CurrentUser() user: AuthUser) {
    return this.payments.connectOnboard(user.userId);
  }

  /** Current payout readiness (polled by the app after onboarding returns). */
  @Get('status')
  status(@CurrentUser() user: AuthUser) {
    return this.payments.connectStatus(user.userId);
  }
}
