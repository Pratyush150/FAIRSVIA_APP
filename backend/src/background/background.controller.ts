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
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { BackgroundService } from './background.service';
import { InitiateBgcDto } from './dto/initiate-bgc.dto';

/** Driver-facing background-check endpoints (own check only). */
@Controller('drivers/background')
@UseGuards(JwtAuthGuard)
export class BackgroundController {
  constructor(private readonly background: BackgroundService) {}

  @Post()
  @HttpCode(HttpStatus.OK)
  initiate(@CurrentUser() user: AuthUser, @Body() dto: InitiateBgcDto) {
    return this.background.initiate(user.userId, dto.email);
  }

  @Get()
  status(@CurrentUser() user: AuthUser) {
    return this.background.status(user.userId);
  }

  /** Poll the vendor for the latest result (a clear result verifies the driver). */
  @Post('refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@CurrentUser() user: AuthUser) {
    return this.background.refresh(user.userId);
  }
}

/** Admin ops: refresh any driver's background check. */
@Controller('admin/drivers')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class BackgroundAdminController {
  constructor(private readonly background: BackgroundService) {}

  @Post(':userId/background/refresh')
  @HttpCode(HttpStatus.OK)
  refresh(@Param('userId') userId: string) {
    return this.background.refresh(userId);
  }
}
