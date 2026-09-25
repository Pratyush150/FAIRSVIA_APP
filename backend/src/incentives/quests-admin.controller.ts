import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, UseGuards } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { RolesGuard } from '../auth/guards/roles.guard';
import { Roles } from '../auth/decorators/roles.decorator';
import { QuestsService } from './quests.service';
import { CreateQuestDto, UpdateQuestDto } from './dto/quest.dto';

@Controller('admin/quests')
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles(UserRole.admin)
export class QuestsAdminController {
  constructor(private readonly quests: QuestsService) {}

  @Get()
  list() {
    return this.quests.list();
  }

  @Post()
  create(@Body() dto: CreateQuestDto) {
    return this.quests.create(dto);
  }

  @Patch(':id')
  update(@Param('id', ParseUUIDPipe) id: string, @Body() dto: UpdateQuestDto) {
    return this.quests.update(id, dto);
  }
}
