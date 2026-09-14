import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { PaymentsService } from './payments.service';
import { AddMethodDto } from './dto/add-method.dto';
import { TipDto } from './dto/tip.dto';

@Controller('payments')
@UseGuards(JwtAuthGuard)
export class PaymentsController {
  constructor(private readonly payments: PaymentsService) {}

  @Get('methods')
  methods(@CurrentUser() user: AuthUser) {
    return this.payments.listMethods(user.userId);
  }

  @Post('methods')
  addMethod(@CurrentUser() user: AuthUser, @Body() dto: AddMethodDto) {
    return this.payments.addMethod(user.userId, dto);
  }

  /** Start a card-save: returns the PaymentSheet secrets + publishable key. */
  @Post('setup-intent')
  @HttpCode(HttpStatus.OK)
  setupIntent(@CurrentUser() user: AuthUser) {
    return this.payments.createSetupIntent(user.userId);
  }

  /** Sync saved cards from the provider after the PaymentSheet saves one. */
  @Post('methods/sync')
  @HttpCode(HttpStatus.OK)
  syncMethods(@CurrentUser() user: AuthUser) {
    return this.payments.syncMethods(user.userId);
  }

  @Post(':tripId/tip')
  @HttpCode(HttpStatus.OK)
  tip(
    @CurrentUser() user: AuthUser,
    @Param('tripId', ParseUUIDPipe) tripId: string,
    @Body() dto: TipDto,
  ) {
    return this.payments.addTip(user.userId, tripId, dto.amount);
  }

  @Get(':tripId/receipt')
  receipt(@CurrentUser() user: AuthUser, @Param('tripId', ParseUUIDPipe) tripId: string) {
    return this.payments.getReceipt(user.userId, tripId);
  }
}
