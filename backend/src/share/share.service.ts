import { formatPlate } from '../drivers/plates';
import {
  ConflictException,
  ForbiddenException,
  HttpException,
  HttpStatus,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { TripStatus } from '@prisma/client';
import { randomBytes } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { LocationService, NavContext } from '../location/location.service';

/**
 * Live trip tracking links ("Track my ride live").
 *
 * A rider asks for a link for their active trip; anyone holding it can watch
 * the car without logging in. The token is 192 random bits (base64url, 32
 * chars) and lives only in Redis — it is ephemeral by nature and must die with
 * the trip, so there is no table. Hard cap on the key's TTL at creation;
 * once the trip ends the TTL is pulled in to end + 1 h on the next read.
 *
 * Privacy: the public payload carries the driver's FIRST name, the car and
 * plate (what the rider's contact needs to recognise the car), the place
 * labels (first segment of the address, never the full street address), the
 * live position while the trip is live, and nothing else — no phones, no rider
 * name, no fare, no start code.
 */

/** Redis keys owned by this module. */
export const ShareKeys = {
  token: (t: string) => `share:tok:${t}`,
  trip: (tripId: string) => `share:trip:${tripId}`,
  rateIp: (ip: string) => `share:rate:ip:${ip}`,
  rateTok: (t: string) => `share:rate:tok:${t}`,
};

/** Upper bound on a link's life while the trip is still running. */
export const SHARE_MAX_TTL_S = 12 * 60 * 60;
/** After the trip ends the link keeps answering ("Trip ended") for this long. */
export const SHARE_AFTER_END_S = 60 * 60;
/** Public poll limits per 60 s window. The page polls every 3 s (20/min), so
 *  one viewer uses a third of the per-IP budget; the per-token cap bounds the
 *  total load one leaked link can generate. Always on (unlike the global
 *  throttler, which is off under NODE_ENV=test). */
export const SHARE_RATE_PER_IP = Number(process.env.SHARE_RATE_PER_IP ?? 60);
export const SHARE_RATE_PER_TOKEN = Number(process.env.SHARE_RATE_PER_TOKEN ?? 300);

export const TOKEN_RE = /^[A-Za-z0-9_-]{32}$/;

const SHAREABLE: TripStatus[] = [
  TripStatus.requested,
  TripStatus.matching,
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
];
const LIVE_POSITION: TripStatus[] = [
  TripStatus.accepted,
  TripStatus.arrived,
  TripStatus.in_progress,
];

export type PublicStatus =
  | 'finding_driver'
  | 'driver_on_the_way'
  | 'driver_arrived'
  | 'on_trip'
  | 'completed'
  | 'ended';

export interface PublicTrack {
  status: PublicStatus;
  ended: boolean;
  driverFirstName: string | null;
  vehicleLabel: string | null;
  plate: string | null;
  lat: number | null;
  lng: number | null;
  heading: number | null;
  pickup: { label: string | null; lat: number; lng: number };
  dropoff: { label: string | null; lat: number; lng: number };
  etaSec: number | null;
  updatedAt: string;
}

export function publicStatus(s: TripStatus): PublicStatus {
  switch (s) {
    case TripStatus.requested:
    case TripStatus.matching:
    case TripStatus.scheduled:
      return 'finding_driver';
    case TripStatus.accepted:
      return 'driver_on_the_way';
    case TripStatus.arrived:
      return 'driver_arrived';
    case TripStatus.in_progress:
      return 'on_trip';
    case TripStatus.completed:
      return 'completed';
    default:
      return 'ended';
  }
}

/** "Chorsu Bazaar, Tashkent, Uzbekistan" → "Chorsu Bazaar". A house number
 *  on its own ("12, Navoi St") is not a place name, so it keeps two parts. */
export function placeLabel(addr: string | null | undefined): string | null {
  if (!addr) return null;
  const parts = addr.split(',').map((p) => p.trim()).filter(Boolean);
  if (parts.length === 0) return null;
  let label = parts[0];
  if (/^\d+[A-Za-z]?$/.test(label) && parts[1]) label = `${label}, ${parts[1]}`;
  return label.slice(0, 60);
}

export function firstName(full: string | null | undefined): string | null {
  const f = (full ?? '').trim().split(/\s+/)[0];
  return f ? f.slice(0, 30) : null;
}

@Injectable()
export class ShareService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly config: ConfigService,
  ) {}

  /** Create (or return the existing) link for the rider's active trip. */
  async createLink(
    userId: string,
    tripId: string,
    requestBase: string,
  ): Promise<{ url: string; token: string; expiresInSec: number }> {
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      select: { riderId: true, status: true },
    });
    if (!trip) throw new NotFoundException('Trip not found');
    if (trip.riderId !== userId) {
      throw new ForbiddenException('Only the rider can share this trip');
    }
    if (!SHAREABLE.includes(trip.status)) {
      throw new ConflictException('This trip is no longer active');
    }

    let token = await this.redis.get(ShareKeys.trip(tripId));
    if (token && !(await this.redis.get(ShareKeys.token(token)))) token = null;
    if (!token) {
      token = randomBytes(24).toString('base64url');
      await this.redis.client
        .multi()
        .set(ShareKeys.token(token), tripId, 'EX', SHARE_MAX_TTL_S)
        .set(ShareKeys.trip(tripId), token, 'EX', SHARE_MAX_TTL_S)
        .exec();
    }
    const ttl = await this.redis.client.ttl(ShareKeys.token(token));
    return {
      url: `${this.baseUrl(requestBase)}/api/v1/public/t/${token}`,
      token,
      expiresInSec: ttl > 0 ? ttl : SHARE_MAX_TTL_S,
    };
  }

  /** PUBLIC_BASE_URL when configured (prod / a fixed domain); otherwise the
   *  origin the request came in on (the quick tunnel's host changes on every
   *  restart, so deriving it keeps links working without a config edit). */
  baseUrl(requestBase: string): string {
    const fixed = (this.config.get<string>('PUBLIC_BASE_URL') ?? '').trim();
    return (fixed || requestBase).replace(/\/+$/, '');
  }

  /** Per-IP and per-token poll limits. Throws 429 when exceeded. */
  async rateLimit(token: string, ip: string): Promise<void> {
    const [byIp, byTok] = await Promise.all([
      this.redis.incrWithTtl(ShareKeys.rateIp(ip), 60),
      this.redis.incrWithTtl(ShareKeys.rateTok(token), 60),
    ]);
    if (byIp > SHARE_RATE_PER_IP || byTok > SHARE_RATE_PER_TOKEN) {
      throw new HttpException('Too many requests', HttpStatus.TOO_MANY_REQUESTS);
    }
  }

  /** Resolve a token to its trip id, or null when unknown / expired. */
  async resolve(token: string): Promise<string | null> {
    if (!TOKEN_RE.test(token)) return null;
    return this.redis.get(ShareKeys.token(token));
  }

  /** The public, privacy-trimmed view of the trip. 404 when the token is
   *  unknown, expired, or the trip ended more than an hour ago. */
  async track(token: string): Promise<PublicTrack> {
    const tripId = await this.resolve(token);
    if (!tripId) throw new NotFoundException('This link has expired');
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      select: {
        status: true,
        driverId: true,
        pickupAddr: true,
        pickupLat: true,
        pickupLng: true,
        dropoffAddr: true,
        dropoffLat: true,
        dropoffLng: true,
        completedAt: true,
        driver: {
          select: {
            fullName: true,
            driverProfile: {
              select: {
                vehicleMake: true,
                vehicleModel: true,
                vehicleColor: true,
                plateNumber: true,
              },
            },
          },
        },
      },
    });
    if (!trip) {
      await this.redis.del(ShareKeys.token(token));
      throw new NotFoundException('This link has expired');
    }

    const ended = !SHAREABLE.includes(trip.status);
    if (ended) {
      // Shrink the link's life to end + 1 h. Cancelled trips have no end
      // timestamp, so the first read after the end starts that hour.
      const endMs = trip.completedAt?.getTime() ?? Date.now();
      const left = Math.floor((endMs + SHARE_AFTER_END_S * 1000 - Date.now()) / 1000);
      if (left <= 0) {
        await this.redis.del(ShareKeys.token(token));
        throw new NotFoundException('This link has expired');
      }
      const ttl = await this.redis.client.ttl(ShareKeys.token(token));
      if (ttl < 0 || ttl > left) {
        await this.redis.client.expire(ShareKeys.token(token), left);
      }
    }

    const p = trip.driver?.driverProfile;
    const vehicleLabel =
      [p?.vehicleColor, p?.vehicleMake, p?.vehicleModel].filter(Boolean).join(' ') || null;

    let lat: number | null = null;
    let lng: number | null = null;
    let heading: number | null = null;
    let etaSec: number | null = null;
    let updatedAt = new Date().toISOString();
    if (trip.driverId && LIVE_POSITION.includes(trip.status)) {
      const loc = await this.redis.client.hgetall(RedisKeys.driverLoc(trip.driverId));
      const la = Number(loc?.lat);
      const ln = Number(loc?.lng);
      if (loc?.lat && Number.isFinite(la) && Number.isFinite(ln)) {
        lat = la;
        lng = ln;
        const h = Number(loc.heading);
        heading = loc.heading && Number.isFinite(h) ? h : null;
        const ts = Number(loc.ts);
        if (Number.isFinite(ts) && ts > 0) updatedAt = new Date(ts).toISOString();
        if (trip.status !== TripStatus.arrived) {
          etaSec = await this.eta(tripId, { lat, lng }, trip.status === TripStatus.in_progress
            ? { lat: trip.dropoffLat, lng: trip.dropoffLng }
            : { lat: trip.pickupLat, lng: trip.pickupLng });
        }
      }
    }

    return {
      status: publicStatus(trip.status),
      ended,
      driverFirstName: trip.driverId ? firstName(trip.driver?.fullName) : null,
      vehicleLabel: trip.driverId ? vehicleLabel : null,
      plate: trip.driverId && p?.plateNumber ? formatPlate(p.plateNumber) : null,
      lat,
      lng,
      heading,
      pickup: { label: placeLabel(trip.pickupAddr), lat: trip.pickupLat, lng: trip.pickupLng },
      dropoff: { label: placeLabel(trip.dropoffAddr), lat: trip.dropoffLat, lng: trip.dropoffLng },
      etaSec,
      updatedAt,
    };
  }

  /** Same estimate the rider app gets on each ping: along the leg's stored
   *  route when there is one, else straight-line at the fallback pace. */
  private async eta(
    tripId: string,
    pos: { lat: number; lng: number },
    fallbackTarget: { lat: number; lng: number },
  ): Promise<number> {
    const h = await this.redis.client.hgetall(RedisKeys.tripNav(tripId));
    const tLat = Number(h?.targetLat);
    const tLng = Number(h?.targetLng);
    const speed = Number(h?.avgSpeedMps);
    const nav: NavContext = {
      phase: h?.phase === 'trip' ? 'trip' : 'approach',
      target:
        h?.targetLat && Number.isFinite(tLat) && Number.isFinite(tLng)
          ? { lat: tLat, lng: tLng }
          : fallbackTarget,
      polyline: h?.polyline ?? '',
      avgSpeedMps: Number.isFinite(speed) && speed > 0 ? speed : undefined,
    };
    return LocationService.estimate(pos, nav).etaSec;
  }
}
