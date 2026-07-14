import { Module } from '@nestjs/common';
import { ChatService } from './chat.service';
import { ChatController } from './chat.controller';

/// In-trip chat. Uses the global Prisma/Redis/Realtime providers; exports
/// ChatService so the Socket.IO gateway can post messages sent over the socket.
@Module({
  controllers: [ChatController],
  providers: [ChatService],
  exports: [ChatService],
})
export class ChatModule {}
