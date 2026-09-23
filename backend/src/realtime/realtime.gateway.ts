import { Logger, UseFilters, UsePipes, ValidationPipe } from '@nestjs/common';
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
import {
  DriverStatusDto,
  LocationPingDto,
  TripIdDto,
  TripMessageDto,
} from './dto/ws-messages.dto';
import { createAdapter } from '@socket.io/redis-adapter';
import { Server, Socket } from 'socket.io';
import { PrismaService } from '../common/prisma/prisma.service';
import { RedisService } from '../common/redis/redis.service';
import { RedisKeys } from '../common/redis/redis.keys';
import { DispatchService } from '../dispatch/dispatch.service';
import { DriversService } from '../drivers/drivers.service';
import { LocationService } from '../location/location.service';
import { TripsService } from '../trips/trips.service';
import { ChatService } from '../chat/chat.service';
import { RealtimeService } from './realtime.service';
import { gatewayCors } from './gateway-cors';
import { WsExceptionsFilter } from './ws-exceptions.filter';
import { ActivityService } from '../common/activity/activity.service';

interface AuthedSocket extends Socket {
  data: { userId?: string; role?: string };
}

/**
 * Socket.IO gateway. Authenticates each connection with the access JWT, joins
 * a personal room, and routes client events to the feature services. Uses the
 * Redis adapter so any node can emit to any room.
 */
@WebSocketGateway({ cors: gatewayCors() })
// The global HTTP ValidationPipe does not cover WS payloads, so validate them
// here. Lenient (strips unknown fields rather than erroring) to stay tolerant of
// client version drift, but enforces types + geographic/length bounds.
@UsePipes(new ValidationPipe({ whitelist: true, transform: true }))
// Forward HttpException messages to the client instead of Nest's default
// "Internal server error" masking (see WsExceptionsFilter).
@UseFilters(new WsExceptionsFilter())
export class RealtimeGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  private readonly logger = new Logger('Gateway');

  @WebSocketServer() server!: Server;

  // Per-socket "authentication finished" promise. handleConnection is async
  // (JWT verify + DB lookup) while Socket.IO dispatches messages as soon as
  // the transport is up, so a client that emits right after `connect` (the
  // driver app's "go online" does) could reach a handler before
  // client.data.userId was set — and be dropped silently. Handlers await
  // this instead of reading the raw field.
  private readonly authReady = new WeakMap<Socket, Promise<void>>();

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
    private readonly prisma: PrismaService,
    private readonly activity: ActivityService,
  ) {}

  afterInit(server: Server): void {
    const pubClient = this.redis.client.duplicate();
    const subClient = this.redis.client.duplicate();
    server.adapter(createAdapter(pubClient, subClient));
    this.realtime.setServer(server);
    this.logger.log('Socket.IO gateway ready (Redis adapter)');
  }

  async handleConnection(client: AuthedSocket): Promise<void> {
    const pending = this.authenticate(client);
    this.authReady.set(client, pending);
    await pending;
  }

  /** The user id of an authenticated socket, once handleConnection is done. */
  private async userIdOf(client: AuthedSocket): Promise<string | undefined> {
    const pending = this.authReady.get(client);
    if (pending) await pending;
    return client.data.userId;
  }

  private async authenticate(client: AuthedSocket): Promise<void> {
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
      // A valid signature isn't enough: the account must still exist and be
      // active (mirrors JwtStrategy for HTTP). Role is read fresh from the DB —
      // the token claim can be up to 15 min stale.
      const user = await this.prisma.user.findUnique({
        where: { id: payload.sub },
        select: { id: true, role: true, isActive: true },
      });
      if (!user || !user.isActive) throw new Error('user inactive');
      client.data.userId = user.id;
      client.data.role = user.role;
      this.activity.touch(user.id);
      await client.join(`user:${user.id}`);
      this.logger.log(`Connected user ${user.id} (${user.role})`);
      if (user.role === 'driver') {
        await this.syncDriverPresence(client, user.id).catch((e) =>
          this.logger.warn(`presence sync failed for ${user.id}: ${String(e)}`),
        );
      }
    } catch {
      client.emit('error', { message: 'unauthorized' });
      client.disconnect(true);
    }
  }

  /**
   * On every driver (re)connect, tell the app the server's view of its
   * presence. The failure mode this closes: the socket dropped, the server
   * took the driver offline (handleDisconnect), the app reconnected still
   * showing "Online" and kept pinging — but a ping only re-adds a driver
   * whose Redis status is 'online', so riders saw no_drivers while the driver
   * sat "online". We deliberately do NOT re-register presence from the DB:
   * only the driver's own Go Online request (setStatus) re-validates
   * documents/tier and carries a fresh position; silently re-adding could
   * also resurrect a driver the server evicted for a reason. Instead the app
   * is told `driver:status_changed` and the DB row is corrected if it drifted.
   */
  private async syncDriverPresence(
    client: AuthedSocket,
    userId: string,
  ): Promise<void> {
    const profile = await this.prisma.driverProfile.findUnique({
      where: { userId },
      select: { status: true },
    });
    if (!profile) return;
    const live = await this.redis.client.get(RedisKeys.driverStatus(userId));
    if (live === 'online' || live === 'on_trip') {
      client.emit('driver:status_changed', { status: live, reason: 'sync' });
      return;
    }
    if (profile.status === 'online') {
      await this.prisma.driverProfile.updateMany({
        where: { userId, status: 'online' },
        data: { status: 'offline' },
      });
    }
    client.emit('driver:status_changed', {
      status: 'offline',
      reason: profile.status === 'online' ? 'presence_lost' : 'sync',
    });
  }

  async handleDisconnect(client: AuthedSocket): Promise<void> {
    const userId = client.data.userId;
    if (!userId) return;
    // Key off live driver state, NOT the JWT role: a driver's token is minted at
    // login and still says 'rider' after onboarding, so a role check here would
    // never fire and dead sockets would linger in the matchable pool — dispatch
    // would then waste a full offer TTL per ghost. `driverTier` exists only while
    // a driver is online, so it's the reliable "is an active driver" signal.
    const tier = await this.redis.client.get(RedisKeys.driverTier(userId));
    if (!tier) return; // not an online driver
    // Mid-trip: keep them in place so a brief drop can reconnect and resume
    // (forceOffline re-checks this). Also syncs the DB status and queues the
    // `driver:status_changed` event for the app when it comes back.
    await this.drivers.forceOffline(userId, tier, 'disconnect');
  }

  @SubscribeMessage('driver:location')
  async onLocation(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: LocationPingDto,
  ): Promise<void> {
    const userId = await this.userIdOf(client);
    if (!userId) return;
    void this.location.ingest(userId, body).catch(() => undefined);
  }

  @SubscribeMessage('driver:status')
  async onStatus(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: DriverStatusDto,
  ): Promise<{ status: string } | void> {
    const userId = await this.userIdOf(client);
    if (!userId) return;
    return this.drivers.setStatus(userId, body.status);
  }

  @SubscribeMessage('trip:accept')
  async onAccept(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: TripIdDto,
  ): Promise<void> {
    const userId = await this.userIdOf(client);
    if (!userId) return;
    await this.dispatch.respondToOffer(userId, body.tripId, true);
  }

  @SubscribeMessage('trip:decline')
  async onDecline(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: TripIdDto,
  ): Promise<void> {
    const userId = await this.userIdOf(client);
    if (!userId) return;
    await this.dispatch.respondToOffer(userId, body.tripId, false);
  }

  @SubscribeMessage('trip:message')
  async onMessage(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: TripMessageDto,
  ): Promise<void> {
    const userId = await this.userIdOf(client);
    if (!userId) return;
    // ChatService validates participation and broadcasts to both parties.
    await this.chat.postMessage(userId, body.tripId, body.text).catch(() => {
      // Never surface the raw error (could leak internals); a generic cue is
      // enough for the client to show "couldn't send".
      client.emit('trip:message_error', { message: 'Message could not be sent' });
    });
  }

  @SubscribeMessage('trip:sync')
  async onSync(
    @ConnectedSocket() client: AuthedSocket,
    @MessageBody() body: TripIdDto,
  ): Promise<void> {
    const userId = await this.userIdOf(client);
    if (!userId) return;
    const trip = await this.trips.getTrip(userId, body.tripId);
    client.emit('trip:sync', trip);
  }
}
