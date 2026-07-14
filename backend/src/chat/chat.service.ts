import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { RealtimeService } from '../realtime/realtime.service';

const MAX_LEN = 500;
const HISTORY_CAP = 200;
const TTL_SECONDS = 24 * 60 * 60;

export interface ChatMessage {
  id: string;
  tripId: string;
  from: string;
  text: string;
  ts: number;
}

/**
 * In-trip chat between the rider and their driver. Messages are ephemeral —
 * stored in a capped, TTL'd Redis list per trip (hot path, no Postgres) — and
 * broadcast to both participants over Socket.IO.
 */
@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly realtime: RealtimeService,
  ) {}

  async postMessage(
    senderId: string,
    tripId: string,
    text: string,
  ): Promise<ChatMessage> {
    const clean = (text ?? '').trim().slice(0, MAX_LEN);
    if (!clean) throw new BadRequestException('Message cannot be empty');

    const trip = await this.participantTrip(senderId, tripId);

    const msg: ChatMessage = {
      id: randomUUID(),
      tripId,
      from: senderId,
      text: clean,
      ts: Date.now(),
    };

    const key = RedisKeys.tripChat(tripId);
    await this.redis.client.rpush(key, JSON.stringify(msg));
    await this.redis.client.ltrim(key, -HISTORY_CAP, -1);
    await this.redis.client.expire(key, TTL_SECONDS);

    // Deliver to both parties (the sender's echo confirms delivery).
    this.realtime.emitToUser(trip.riderId, 'trip:message', msg);
    if (trip.driverId) this.realtime.emitToUser(trip.driverId, 'trip:message', msg);

    return msg;
  }

  async history(userId: string, tripId: string): Promise<ChatMessage[]> {
    await this.participantTrip(userId, tripId);
    const raw = await this.redis.client.lrange(RedisKeys.tripChat(tripId), 0, -1);
    return raw.map((r) => JSON.parse(r) as ChatMessage);
  }

  /** Loads the trip and asserts the user is its rider or driver. */
  private async participantTrip(userId: string, tripId: string) {
    const trip = await this.prisma.trip.findUnique({
      where: { id: tripId },
      select: { riderId: true, driverId: true },
    });
    if (!trip) throw new NotFoundException('Trip not found');
    if (userId !== trip.riderId && userId !== trip.driverId) {
      throw new ForbiddenException('Not a participant of this trip');
    }
    return trip;
  }
}
