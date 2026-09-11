import {
  Controller,
  Get,
  HttpCode,
  HttpStatus,
  Param,
  ParseUUIDPipe,
  Post,
  UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { NotificationsService } from './notifications.service';

/** The in-app notification inbox for the signed-in user. */
@Controller('me/notifications')
@UseGuards(JwtAuthGuard)
export class InboxController {
  constructor(private readonly notifications: NotificationsService) {}

  @Get()
  list(@CurrentUser() user: AuthUser) {
    return this.notifications.listInbox(user.userId);
  }

  @Get('unread-count')
  unread(@CurrentUser() user: AuthUser) {
    return this.notifications.unreadCount(user.userId);
  }

  @Post('read-all')
  @HttpCode(HttpStatus.OK)
  readAll(@CurrentUser() user: AuthUser) {
    return this.notifications.markAllRead(user.userId);
  }

  @Post(':id/read')
  @HttpCode(HttpStatus.OK)
  read(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.notifications.markRead(user.userId, id);
  }
}
