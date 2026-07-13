import {
  Body,
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
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

  @Post(':tripId/tip')
  @HttpCode(HttpStatus.OK)
  tip(
    @CurrentUser() user: AuthUser,
    @Param('tripId') tripId: string,
    @Body() dto: TipDto,
  ) {
    return this.payments.addTip(user.userId, tripId, dto.amount);
  }

  @Get(':tripId/receipt')
  receipt(@CurrentUser() user: AuthUser, @Param('tripId') tripId: string) {
    return this.payments.getReceipt(user.userId, tripId);
  }
}
