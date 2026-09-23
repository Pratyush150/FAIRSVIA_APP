import { Global, Module } from '@nestjs/common';
import { ActivityService } from './activity.service';

/** Daily-active tracking, available to auth (HTTP) and the socket gateway. */
@Global()
@Module({
  providers: [ActivityService],
  exports: [ActivityService],
})
export class ActivityModule {}
