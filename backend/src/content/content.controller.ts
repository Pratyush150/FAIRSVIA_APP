import {
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  UseGuards,
} from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { ContentService } from './content.service';
import { CreateRideCardDto, UpdateRideCardDto } from './dto/ride-card.dto';

@Controller()
@UseGuards(JwtAuthGuard)
export class ContentController {
  constructor(private readonly content: ContentService) {}

  /** Live cards for the ride screen. */
  @Get('content/ride-cards')
  live() {
    return this.content.liveRideCards();
  }

  @Get('admin/content/ride-cards')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  all() {
    return this.content.listAll();
  }

  @Post('admin/content/ride-cards')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  create(@Body() dto: CreateRideCardDto) {
    return this.content.create(dto);
  }

  @Patch('admin/content/ride-cards/:id')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateRideCardDto) {
    return this.content.update(id, dto);
  }

  @Delete('admin/content/ride-cards/:id')
  @UseGuards(RolesGuard)
  @Roles(UserRole.admin)
  remove(@Param('id', ParseUUIDPipe) id: string) {
    return this.content.remove(id);
  }
}
