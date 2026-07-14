import { Body, Controller, HttpCode, HttpStatus, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { PromoService } from './promo.service';
import { QuotePromoDto } from './dto/quote-promo.dto';

/** Rider-facing: price a promo code against a fare before requesting a ride. */
@Controller('promos')
@UseGuards(JwtAuthGuard)
export class PromoController {
  constructor(private readonly promo: PromoService) {}

  @Post('quote')
  @HttpCode(HttpStatus.OK)
  quote(@CurrentUser() user: AuthUser, @Body() dto: QuotePromoDto) {
    return this.promo.quote(dto.code, dto.subtotal, user.userId);
  }
}
