import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { LedgerService } from './ledger.service';
import { WithdrawDto } from './dto/withdraw.dto';

/**
 * Driver-facing payout balance + ledger + withdrawals. Guarded by auth only
 * (like the rest of the drivers API) since the JWT role stays `rider` until a
 * re-login after onboarding; the ledger is keyed per-user, so a non-driver
 * simply has an empty balance.
 */
@Controller('drivers/balance')
@UseGuards(JwtAuthGuard)
export class LedgerController {
  constructor(private readonly ledger: LedgerService) {}

  @Get()
  summary(@CurrentUser() user: AuthUser) {
    return this.ledger.summary(user.userId);
  }

  @Post('withdraw')
  @HttpCode(HttpStatus.OK)
  withdraw(@CurrentUser() user: AuthUser, @Body() dto: WithdrawDto) {
    return this.ledger.withdraw(user.userId, dto.amount);
  }
}
