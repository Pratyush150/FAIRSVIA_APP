import { Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { createAdapter } from '@socket.io/redis-adapter';
import { Server, Socket } from 'socket.io';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { DispatchService } from '../dispatch/dispatch.service';
import { DriversService } from '../drivers/drivers.service';
import { LocationService } from '../location/location.service';
import { TripsService } from '../trips/trips.service';
import { ChatService } from '../chat/chat.service';
import { RealtimeService } from './realtime.service';

interface AuthedSocket extends Socket {
  data: { userId?: string; role?: string };
}

/**
 * Socket.IO gateway. Authenticates each connection with the access JWT, joins
 * a personal room, and routes client events to the feature services. Uses the
 * Redis adapter so any node can emit to any room.
 */
@WebSocketGateway({ cors: { origin: true } })
export class RealtimeGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  private readonly logger = new Logger('Gateway');

  @WebSocketServer() server!: Server;

  constructor(
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    private readonly realtime: RealtimeService,
    private readonly redis: RedisService,
    private readonly location: LocationService,
    private readonly dispatch: DispatchService,
    private readonly trips: TripsService,
    private readonly drivers: DriversService,
    private readonly chat: ChatService,
  ) {}

  afterInit(server: Server): void {
    const pubClient = this.redis.client.duplicate();
    const subClient = this.redis.client.duplicate();
    server.adapter(createAdapter(pubClient, subClient));
    this.realtime.setServer(server);
    this.logger.log('Socket.IO gateway ready (Redis adapter)');
  }

  async handleConnection(client: AuthedSocket): Promise<void> {
    try {
      const raw =
        (client.handshake.auth?.token as string | undefined) ??
        client.handshake.headers?.authorization?.replace('Bearer ', '');
      if (!raw) throw new Error('no token');
      const secret = this.config.get<{ accessSecret: string }>('jwt')!.accessSecret;
      const payload = await this.jwt.verifyAsync<{ sub: string; role: string }>(
        raw,
        { secret },
      );
      client.data.userId = payload.sub;
      client.data.role = payload.role;
      await client.join(`user:${payload.sub}`);
      this.logger.log(`Connected user ${payload.sub} (${payload.role})`);
    } catch {
      client.emit('error', { message: 'unauthorized' });
      client.disconnect(true);
    }
  }

  async handleDisconnect(client: AuthedSocket): Promise<void> {
    const userId = client.data.userId;
    if (!userId || client.data.role !== 'driver') return;
    // Best-effort: take a disconnecting driver out of the pool (unless on a trip).
    const onTrip = await this.redis.client.get(RedisKeys.driverActiveTrip(userId));
    if (onTrip) return;
    const tier = await this.redis.client.get(RedisKeys.driverTier(userId));
    if (tier) await this.drivers.goOffline(userId, tier);
  }

  @SubscribeMessage('driver:location')
  onLocation(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: { lat: number; lng: number; heading?: number; speed?: number },
  ): void {
    const userId = client.data.userId;
    if (!userId) return;
    void this.location.ingest(userId, body).catch(() => undefined);
  }

  @SubscribeMessage('driver:status')
  async onStatus(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: { status: 'online' | 'offline' },
  ): Promise<{ status: string } | void> {
    const userId = client.data.userId;
    if (!userId) return;
    return this.drivers.setStatus(userId, body.status);
  }

  @SubscribeMessage('trip:accept')
  async onAccept(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: { tripId: string },
  ): Promise<void> {
    const userId = client.data.userId;
    if (!userId) return;
    await this.dispatch.respondToOffer(userId, body.tripId, true);
  }

  @SubscribeMessage('trip:decline')
  async onDecline(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: { tripId: string },
  ): Promise<void> {
    const userId = client.data.userId;
    if (!userId) return;
    await this.dispatch.respondToOffer(userId, body.tripId, false);
  }

  @SubscribeMessage('trip:message')
  async onMessage(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: { tripId: string; text: string },
  ): Promise<void> {
    const userId = client.data.userId;
    if (!userId) return;
    // ChatService validates participation and broadcasts to both parties.
    await this.chat.postMessage(userId, body.tripId, body.text).catch((e) => {
      client.emit('trip:message_error', { message: String(e?.message ?? e) });
    });
  }

  @SubscribeMessage('trip:sync')
  async onSync(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: { tripId: string },
  ): Promise<void> {
    const userId = client.data.userId;
    if (!userId) return;
    const trip = await this.trips.getTrip(userId, body.tripId);
    client.emit('trip:sync', trip);
  }
}
