import { Injectable, Logger } from '@nestjs/common';
import {
  PushMessage,
  PushProvider,
  PushTarget,
} from './push-provider.interface';

/**
 * Dev push provider: logs the notification instead of hitting FCM/APNs. Swap
 * for a real provider by setting FCM_SERVER_KEY.
 */
@Injectable()
export class MockPushProvider implements PushProvider {
  private readonly logger = new Logger('MockPush');

  constructor() {
    this.logger.warn('Using MOCK push provider (no FCM_SERVER_KEY set).');
  }

  async send(target: PushTarget, message: PushMessage): Promise<void> {
    this.logger.log(
      `→ [${target.platform}] ${message.title} — ${message.body} ` +
        `(token ${target.token.slice(0, 8)}…)`,
    );
  }
}
