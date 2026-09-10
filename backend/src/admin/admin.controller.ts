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
import { DiagnosticsService } from './diagnostics.service';
import { SetActiveDto } from './dto/set-active.dto';
import { VerifyDriverDto } from './dto/verify-driver.dto';

@Controller('admin')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class AdminController {
  constructor(
    private readonly admin: AdminService,
    private readonly diagnostics: DiagnosticsService,
  ) {}

  /** Provider readiness "checkpoints": which external APIs are real vs mock. */
  @Get('diagnostics')
  providerDiagnostics() {
    return this.diagnostics.snapshot();
  }

  /** LIVE probe: actually pings each configured API and reports OK or the
   *  exact error (read-only — sends no SMS/email, charges nothing). */
  @Get('diagnostics/probe')
  providerProbe() {
    return this.diagnostics.probe();
  }

  @Get('stats')
  stats() {
    return this.admin.stats();
  }

  @Get('metrics')
  metrics() {
    return this.admin.opsMetrics();
  }

  @Get('live')
  live() {
    return this.admin.live();
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
  drivers(@Query('limit') limit?: string, @Query('pending') pending?: string) {
    return this.admin.drivers({
      limit: limit ? parseInt(limit, 10) : undefined,
      pending: pending === 'true',
    });
  }

  @Patch('drivers/:id/verify')
  verifyDriver(@Param('id') id: string, @Body() dto: VerifyDriverDto) {
    return this.admin.verifyDriver(id, dto.docsVerified);
  }

  @Patch('users/:id/active')
  setActive(@Param('id') id: string, @Body() dto: SetActiveDto) {
    return this.admin.setActive(id, dto.isActive);
  }
}
