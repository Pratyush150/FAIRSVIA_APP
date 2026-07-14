import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { PromoService } from './promo.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';

/** Admin-facing: create, list, and toggle promo codes. */
@Controller('admin/promos')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class PromoAdminController {
  constructor(private readonly promo: PromoService) {}

  @Get()
  list() {
    return this.promo.list();
  }

  @Post()
  create(@Body() dto: CreatePromoDto) {
    return this.promo.create(dto);
  }

  @Patch(':code')
  update(@Param('code') code: string, @Body() dto: UpdatePromoDto) {
    return this.promo.update(code, dto);
  }
}
