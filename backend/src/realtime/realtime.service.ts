import { Injectable, Logger } from '@nestjs/common';
import { Server } from 'socket.io';

/**
 * Holds the Socket.IO server and exposes room-targeted emit helpers. Other
 * modules depend on this (not the gateway) to avoid circular dependencies.
 */
@Injectable()
export class RealtimeService {
  private readonly logger = new Logger('Realtime');
  private server?: Server;

  setServer(server: Server): void {
    this.server = server;
  }

  /** Emit to a specific user's personal room (`user:{id}`). */
  emitToUser(userId: string, event: string, payload: unknown = {}): void {
    if (!this.server) return;
    this.server.to(`user:${userId}`).emit(event, payload);
  }

  /** Emit to everyone in a trip room (`trip:{id}`). */
  emitToTrip(tripId: string, event: string, payload: unknown = {}): void {
    if (!this.server) return;
    this.server.to(`trip:${tripId}`).emit(event, payload);
  }
}
