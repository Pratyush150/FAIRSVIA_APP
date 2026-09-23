import {
  BadRequestException,
  ConflictException,
  ForbiddenException,
  Inject,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { Trip, TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { RealtimeService } from '../realtime/realtime.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { PricingService } from '../pricing/pricing.service';
import { GEO_PROVIDER, GeoProvider } from '../geo/geo-provider.interface';
import { MAX_STOPS, StopDto } from './dto/stop.dto';
import { routeThrough } from './route-through';
import { PRICE_LOCK_TOLERANCE } from './trips.service';

/** Statuses in which a rider may add a stop to their ride. */
const EDITABLE: TripStatus[] = [
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
];

export interface StopQuote {
  fareEstimate: number;
  previousFare: number;
  distanceM: number;
  durationS: number;
  currency: string;
}

/**
 * Adding a stop to a ride already under way. Two steps so the fare never
 * jumps silently: quote (new route and price), then add with the quoted fare
 * — refused if the price has since moved beyond the booking tolerance. The
 * stop goes before the destination; the stored estimate (which also bounds
 * the metered final fare) is re-priced at the ride's locked surge, and both
 * the driver and the rider are told.
 */
@Injectable()
export class TripStopsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly realtime: RealtimeService,
    private readonly pricing: PricingService,
    private readonly redis: RedisService,
    @Inject(GEO_PROVIDER) private readonly geo: GeoProvider,
  ) {}

  private async editableTrip(riderId: string, tripId: string): Promise<Trip> {
    const trip = await this.prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== riderId) throw new ForbiddenException('Not your trip');
    if (!EDITABLE.includes(trip.status)) {
      throw new BadRequestException('Stops can only be added once a driver is on the way.');
    }
    const stops = ((trip.stops as unknown as StopDto[] | null) ?? []);
    if (stops.length >= MAX_STOPS) {
      throw new BadRequestException(`A ride can have up to ${MAX_STOPS} stops.`);
    }
    return trip;
  }

  private async price(trip: Trip, stops: StopDto[]) {
    const route = await routeThrough(this.geo, [
      { lat: trip.pickupLat, lng: trip.pickupLng },
      ...stops.map((s) => ({ lat: s.lat, lng: s.lng })),
      { lat: trip.dropoffLat, lng: trip.dropoffLng },
    ]);
    const surge = trip.surgeMultiplier ? Number(trip.surgeMultiplier) : 1;
    const est = this.pricing.estimateForTier(
      trip.tier,
      route.distanceM,
      route.durationS,
      surge,
    );
    return { route, fare: est.fare };
  }

  async quote(riderId: string, tripId: string, stop: StopDto): Promise<StopQuote> {
    const trip = await this.editableTrip(riderId, tripId);
    const stops = [...((trip.stops as unknown as StopDto[] | null) ?? []), stop];
    const { route, fare } = await this.price(trip, stops);
    return {
      fareEstimate: fare,
      previousFare: Number(trip.fareEstimate ?? 0),
      distanceM: route.distanceM,
      durationS: route.durationS,
      currency: trip.currency,
    };
  }

  async add(
    riderId: string,
    tripId: string,
    stop: StopDto,
    quotedFare?: number,
  ) {
    const trip = await this.editableTrip(riderId, tripId);
    const clean: StopDto = { lat: stop.lat, lng: stop.lng, addr: stop.addr };
    const stops = [...((trip.stops as unknown as StopDto[] | null) ?? []), clean];
    const { route, fare } = await this.price(trip, stops);
    if (quotedFare !== undefined) {
      const base = Math.max(quotedFare, 0.01);
      if (Math.abs(fare - quotedFare) / base > PRICE_LOCK_TOLERANCE) {
        throw new ConflictException({
          code: 'PRICE_CHANGED',
          message: 'The price for this stop has changed. Please check it again.',
          fareEstimate: fare,
        });
      }
    }
    const fareEstimate = quotedFare ?? fare;
    const updated = await this.prisma.trip.update({
      where: { id: tripId },
      data: {
        stops: stops as object[],
        routePolyline: route.polyline,
        distanceM: route.distanceM,
        durationS: route.durationS,
        fareEstimate,
      },
    });
    await this.prisma.tripEvent.create({
      data: {
        tripId,
        fromStatus: trip.status,
        toStatus: trip.status,
        actor: 'rider',
        meta: {
          event: 'stop_added',
          stop: { ...clean },
          previousFare: Number(trip.fareEstimate ?? 0),
          fareEstimate,
        },
      },
    });
    // A ride under way: its live navigation (ETA, off-route watch, re-route)
    // must follow the new route and pass through the new stop too.
    if (trip.status === TripStatus.in_progress) {
      const key = RedisKeys.tripNav(tripId);
      const current = await this.redis.client.hget(key, 'waypoints');
      let ahead: { lat: number; lng: number }[] = [];
      try {
        ahead = JSON.parse(current ?? '[]');
      } catch {
        ahead = [];
      }
      await this.redis.client.hset(key, {
        waypoints: JSON.stringify([...ahead, { lat: clean.lat, lng: clean.lng }]),
        polyline: route.polyline,
        avgSpeedMps: route.durationS > 0 ? route.distanceM / route.durationS : '',
      });
    }
    const payload = {
      tripId,
      stops,
      routePolyline: route.polyline,
      distanceM: route.distanceM,
      durationS: route.durationS,
      fareEstimate,
    };
    this.realtime.emitToUser(trip.riderId, 'trip:stops_updated', payload);
    if (trip.driverId) {
      this.realtime.emitToUser(trip.driverId, 'trip:stops_updated', payload);
    }
    return { ...payload, status: updated.status };
  }
}
