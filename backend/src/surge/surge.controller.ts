import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { SurgeService } from './surge.service';
import { SurgeOverrideDto } from './dto/surge-override.dto';

@Controller('admin/surge')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class SurgeController {
  constructor(private readonly surge: SurgeService) {}

  @Get()
  snapshot() {
    return this.surge.snapshot();
  }

  @Patch()
  setOverride(@Body() dto: SurgeOverrideDto) {
    return this.surge.setOverride(dto.multiplier);
  }
}
