import { Body, Controller, Get, Param, Patch, UseGuards } from '@nestjs/common';
import { IsBoolean } from 'class-validator';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { DispatchService } from '../dispatch/dispatch.service';
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
  constructor(
    private readonly flags: OpsFlagsService,
    private readonly dispatch: DispatchService,
  ) {}

  /** Current state of every switch, with the label the console shows. */
  @Get()
  async list() {
    return this.view();
  }

  @Patch(':flag')
  async set(@Param('flag') flag: string, @Body() dto: SetFlagDto) {
    if (!OPS_FLAG_NAMES.includes(flag as OpsFlag)) {
      // Not a 404: the caller asked for something that is not a switch at all.
      throw new Error(`Unknown ops flag: ${flag}`);
    }
    await this.flags.set(flag as OpsFlag, dto.on);

    // Lifting the dispatch pause releases what it parked. Done here rather
    // than inside OpsFlagsService so the flag store stays a dumb key/value and
    // does not need to know what any particular switch means.
    let released: number | undefined;
    if (flag === 'dispatchPaused' && !dto.on) {
      released = await this.dispatch.resumeDeferred();
    }
    return { ...(await this.view()), ...(released !== undefined ? { released } : {}) };
  }

  /** The switches as the console renders them, plus what is waiting on them. */
  private async view() {
    const state = await this.flags.all();
    return {
      flags: OPS_FLAG_NAMES.map((name) => ({
        name,
        label: OPS_FLAGS[name],
        on: state[name],
      })),
      // Surfaced so an operator can see the cost of leaving the pause on.
      deferredTrips: await this.dispatch.deferredCount(),
    };
  }
}
