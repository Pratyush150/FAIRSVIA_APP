import {
  Controller,
  Delete,
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
import { FavoritesService } from './favorites.service';

/** Rider-facing favourite-driver management. */
@Controller()
@UseGuards(JwtAuthGuard)
export class FavoritesController {
  constructor(private readonly favorites: FavoritesService) {}

  @Get('me/favorites')
  list(@CurrentUser() user: AuthUser) {
    return this.favorites.list(user.userId);
  }

  @Post('drivers/:driverId/favorite')
  @HttpCode(HttpStatus.OK)
  add(@CurrentUser() user: AuthUser, @Param('driverId', ParseUUIDPipe) driverId: string) {
    return this.favorites.add(user.userId, driverId);
  }

  @Delete('drivers/:driverId/favorite')
  @HttpCode(HttpStatus.OK)
  remove(@CurrentUser() user: AuthUser, @Param('driverId', ParseUUIDPipe) driverId: string) {
    return this.favorites.remove(user.userId, driverId);
  }
}
