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
import { RatingsService } from './ratings.service';
import { CreateRatingDto } from './dto/create-rating.dto';

@Controller('trips/:tripId/rating')
@UseGuards(JwtAuthGuard)
export class RatingsController {
  constructor(private readonly ratings: RatingsService) {}

  @Post()
  rate(
    @CurrentUser() user: AuthUser,
    @Param('tripId') tripId: string,
    @Body() dto: CreateRatingDto,
  ) {
    return this.ratings.rateTrip(user.userId, tripId, dto);
  }

  @Get()
  mine(@CurrentUser() user: AuthUser, @Param('tripId') tripId: string) {
    return this.ratings.getMyRating(user.userId, tripId);
  }
}
