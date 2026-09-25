import {
  BadRequestException,
  Body,
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
import { DispatchService } from '../dispatch/dispatch.service';
import { TripsService } from './trips.service';
import { EstimateDto } from './dto/estimate.dto';
import { CreateTripDto } from './dto/create-trip.dto';
import { CompleteTripDto, EndTripEarlyDto } from './dto/complete-trip.dto';
import { CancelTripDto } from './dto/cancel-trip.dto';
import { DriverCancelTripDto } from './dto/driver-cancel-trip.dto';
import { StartTripDto } from './dto/start-trip.dto';
import { RiderComingService } from './rider-coming.service';
import { TripStopsService } from './trip-stops.service';
import { AddStopDto } from './dto/add-stop.dto';
import { StopDto } from './dto/stop.dto';

@Controller('trips')
@UseGuards(JwtAuthGuard)
export class TripsController {
  constructor(
    private readonly trips: TripsService,
    private readonly dispatch: DispatchService,
    private readonly riderComing: RiderComingService,
    private readonly stops: TripStopsService,
  ) {}

  @Post('estimate')
  @HttpCode(HttpStatus.OK)
  estimate(@Body() dto: EstimateDto) {
    return this.trips.estimate(dto);
  }

  @Post()
  create(@CurrentUser() user: AuthUser, @Body() dto: CreateTripDto) {
    return this.trips.createTrip(user.userId, dto);
  }

  @Get('history')
  history(@CurrentUser() user: AuthUser) {
    return this.trips.history(user.userId);
  }

  // Must precede the `:id` route so "scheduled" isn't parsed as a trip id.
  @Get('scheduled')
  scheduled(@CurrentUser() user: AuthUser) {
    return this.trips.listScheduled(user.userId);
  }

  // Must also precede `:id`. Returns the caller's active trip, or null.
  @Get('active')
  active(@CurrentUser() user: AuthUser) {
    return this.trips.getActiveTrip(user.userId);
  }

  @Get(':id')
  get(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.trips.getTrip(user.userId, id);
  }

  @Post(':id/cancel')
  @HttpCode(HttpStatus.OK)
  cancel(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CancelTripDto,
  ) {
    return this.trips.cancelTrip(user.userId, id, dto.reason);
  }

  // --- Driver actions (also available over WebSocket) ---

  @Post(':id/accept')
  @HttpCode(HttpStatus.OK)
  async accept(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    if (!(await this.dispatch.respondToOffer(user.userId, id, true))) {
      throw new BadRequestException('Offer expired or not found');
    }
    return { ok: true };
  }

  @Post(':id/decline')
  @HttpCode(HttpStatus.OK)
  async decline(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    await this.dispatch.respondToOffer(user.userId, id, false);
    return { ok: true };
  }

  /** Price of the ride with one more stop, before the rider commits. */
  @Post(':id/stops/quote')
  @HttpCode(HttpStatus.OK)
  quoteStop(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: StopDto,
  ) {
    return this.stops.quote(user.userId, id, dto);
  }

  /** Add a stop (before the destination) to a ride under way. */
  @Post(':id/stops')
  addStop(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: AddStopDto,
  ) {
    const { quotedFare, ...stop } = dto;
    return this.stops.add(user.userId, id, stop, quotedFare);
  }

  /** Rider → driver: "I'm on my way out". */
  @Post(':id/on-my-way')
  @HttpCode(HttpStatus.OK)
  onMyWay(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.riderComing.notify(user.userId, id);
  }

  @Post(':id/arrived')
  @HttpCode(HttpStatus.OK)
  arrived(@CurrentUser() user: AuthUser, @Param('id', ParseUUIDPipe) id: string) {
    return this.trips.driverArrived(user.userId, id);
  }

  @Post(':id/start')
  @HttpCode(HttpStatus.OK)
  start(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: StartTripDto,
  ) {
    return this.trips.startTrip(user.userId, id, dto.otp);
  }

  @Post(':id/complete')
  @HttpCode(HttpStatus.OK)
  complete(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: CompleteTripDto,
  ) {
    return this.trips.completeTrip(user.userId, id, {
      endEarly: dto?.endEarly === true,
      reason: dto?.reason,
    });
  }

  /** Rider or driver ends an in-progress ride here: metered fare, minimum
   *  floor, never the up-front estimate. Reason optional. */
  @Post(':id/end-early')
  @HttpCode(HttpStatus.OK)
  endEarly(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: EndTripEarlyDto,
  ) {
    return this.trips.endTripEarly(user.userId, id, dto?.reason);
  }

  /** Assigned driver walks away before the ride starts (e.g. rider no-show). */
  @Post(':id/driver-cancel')
  @HttpCode(HttpStatus.OK)
  driverCancel(
    @CurrentUser() user: AuthUser,
    @Param('id', ParseUUIDPipe) id: string,
    @Body() dto: DriverCancelTripDto,
  ) {
    return this.trips.driverCancelTrip(
      user.userId,
      id,
      dto.reason,
      dto.noShow === true,
    );
  }
}
