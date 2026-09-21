import { Body, Controller, Get, Param, Patch, UseGuards } from '@nestjs/common';
import { IsBoolean } from 'class-validator';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import {
  OPS_FLAGS,
  OPS_FLAG_NAMES,
  OpsFlag,
  OpsFlagsService,
} from './ops-flags.service';

class SetFlagDto {
  @IsBoolean()
  on!: boolean;
}

/**
 * The operational kill switches.
 *
 * Every write here is recorded by the global audit interceptor, which selects
 * routes by their `@Roles(admin)` metadata — so "who paused dispatch, when,
 * and from where" is answerable without this controller doing anything.
 */
@Controller('admin/ops-flags')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class OpsController {
  constructor(private readonly flags: OpsFlagsService) {}

  /** Current state of every switch, with the label the console shows. */
  @Get()
  async list() {
    const state = await this.flags.all();
    return {
      flags: OPS_FLAG_NAMES.map((name) => ({
        name,
        label: OPS_FLAGS[name],
        on: state[name],
      })),
    };
  }

  @Patch(':flag')
  async set(@Param('flag') flag: string, @Body() dto: SetFlagDto) {
    if (!OPS_FLAG_NAMES.includes(flag as OpsFlag)) {
      // Not a 404: the caller asked for something that is not a switch at all.
      throw new Error(`Unknown ops flag: ${flag}`);
    }
    const state = await this.flags.set(flag as OpsFlag, dto.on);
    return {
      flags: OPS_FLAG_NAMES.map((name) => ({
        name,
        label: OPS_FLAGS[name],
        on: state[name],
      })),
    };
  }
}
