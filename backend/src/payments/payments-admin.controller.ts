import {
  Body,
  Controller,
  HttpCode,
  HttpStatus,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { PaymentsService } from './payments.service';
import { RefundDto } from './dto/refund.dto';

/** Admin-facing payment operations (refunds). */
@Controller('admin/payments')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class PaymentsAdminController {
  constructor(private readonly payments: PaymentsService) {}

  @Post(':tripId/refund')
  @HttpCode(HttpStatus.OK)
  refund(@Param('tripId') tripId: string, @Body() dto: RefundDto) {
    return this.payments.refundTrip(tripId, dto.amount, dto.reason);
  }
}
