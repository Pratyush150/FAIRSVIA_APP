import { Module } from '@nestjs/common';
import { ShareService } from './share.service';
import { PublicTrackController, ShareLinkController } from './share.controller';

/// Live trip tracking links: a rider mints an unguessable, expiring link and
/// anyone holding it can watch the car on a small public page (no login).
/// Tokens live in Redis only (ephemeral, die with the trip).
@Module({
  controllers: [ShareLinkController, PublicTrackController],
  providers: [ShareService],
})
export class ShareModule {}
