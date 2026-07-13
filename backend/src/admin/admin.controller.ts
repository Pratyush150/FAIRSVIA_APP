import {
  Body,
  Controller,
  Get,
  Param,
  Patch,
  Query,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { AdminService } from './admin.service';
import { SetActiveDto } from './dto/set-active.dto';

@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class AdminController {
  constructor(private readonly admin: AdminService) {}

  @Get('stats')
  stats() {
    return this.admin.stats();
  }

  @Get('metrics')
  metrics() {
    return this.admin.opsMetrics();
  }

  @Get('trips')
  trips(@Query('status') status?: string, @Query('limit') limit?: string) {
    return this.admin.trips({
      status,
      limit: limit ? parseInt(limit, 10) : undefined,
    });
  }

  @Get('users')
  users(@Query('q') q?: string, @Query('limit') limit?: string) {
    return this.admin.users({ q, limit: limit ? parseInt(limit, 10) : undefined });
  }

  @Get('drivers')
  drivers(@Query('limit') limit?: string) {
    return this.admin.drivers({ limit: limit ? parseInt(limit, 10) : undefined });
  }

  @Patch('users/:id/active')
  setActive(@Param('id') id: string, @Body() dto: SetActiveDto) {
    return this.admin.setActive(id, dto.isActive);
  }
}
