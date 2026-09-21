import { ExecutionContext, Injectable } from '@nestjs/common';
import { ThrottlerGuard } from '@nestjs/throttler';
import { throttleConfig } from './throttle.config';

/**
 * Global rate-limit guard. Keys on the client IP (`req.ip`, which honours
 * `trust proxy` in production so the nginx/Cloudflare hop isn't counted as the
 * client). Skips non-HTTP contexts (Socket.IO has its own per-user limits) and
 * is fully disabled under jest / THROTTLE_DISABLED.
 */
@Injectable()
export class AppThrottlerGuard extends ThrottlerGuard {
  private readonly disabled = throttleConfig().disabled;

  protected async shouldSkip(context: ExecutionContext): Promise<boolean> {
    return this.disabled || context.getType() !== 'http';
  }

  protected async getTracker(req: Record<string, any>): Promise<string> {
    return (req.ip as string | undefined) ?? 'unknown';
  }
}
