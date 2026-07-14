import { Body, Controller, Get, Param, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { PricingService } from './pricing.service';
import { UpdateFareDto } from './dto/update-fare.dto';

@Controller('admin/fares')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class PricingController {
  constructor(private readonly pricing: PricingService) {}

  @Get()
  list() {
    return this.pricing.listConfig();
  }

  @Patch(':tier')
  update(@Param('tier') tier: string, @Body() dto: UpdateFareDto) {
    return this.pricing.updateTier(tier, dto);
  }
}
