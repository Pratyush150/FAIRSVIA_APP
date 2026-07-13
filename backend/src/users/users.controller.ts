import { Body, Controller, Get, Patch, Post, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../auth/guards/jwt-auth.guard';
import { CurrentUser } from '../auth/decorators/current-user.decorator';
import { AuthUser } from '../auth/strategies/jwt.strategy';
import { UsersService } from './users.service';
import { UpdateUserDto } from './dto/update-user.dto';
import { CreatePlaceDto } from './dto/create-place.dto';

@Controller('users')
@UseGuards(JwtAuthGuard)
export class UsersController {
  constructor(private readonly users: UsersService) {}

  @Get('me')
  me(@CurrentUser() user: AuthUser) {
    return this.users.findById(user.userId);
  }

  @Patch('me')
  updateMe(@CurrentUser() user: AuthUser, @Body() dto: UpdateUserDto) {
    return this.users.update(user.userId, dto);
  }

  @Get('me/places')
  places(@CurrentUser() user: AuthUser) {
    return this.users.listPlaces(user.userId);
  }

  @Post('me/places')
  addPlace(@CurrentUser() user: AuthUser, @Body() dto: CreatePlaceDto) {
    return this.users.addPlace(user.userId, dto);
  }
}
