import {
  Body,
  Controller,
  Get,
  Param,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { SupportService } from './support.service';
import { CreateTicketDto } from './dto/create-ticket.dto';
import { PostMessageDto } from './dto/post-message.dto';

/** User-facing support tickets (rider or driver). */
@Controller('support/tickets')
@UseGuards(JwtAuthGuard)
export class SupportController {
  constructor(private readonly support: SupportService) {}

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateTicketDto) {
    return this.support.create(user.userId, dto);
  }

  @Get()
  listMine(@CurrentUser() user: AuthUser) {
    return this.support.listMine(user.userId);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id') id: string) {
    return this.support.get(user.userId, id, user.role === 'admin');
  }

  @Post(':id/messages')
  post(
    @CurrentUser() user: AuthUser,
    @Param('id') id: string,
    @Body() dto: PostMessageDto,
  ) {
    return this.support.postMessage(
      user.userId,
      id,
      dto,
      user.role === 'admin',
    );
  }
}
