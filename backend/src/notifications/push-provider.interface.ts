export const PUSH_PROVIDER = 'PUSH_PROVIDER';

export interface PushMessage {
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushTarget {
  token: string;
  platform: string;
}

/**
 * Abstraction over the push gateway (FCM/APNs). The mock logs to the console;
 * a real implementation is selected when a provider key is configured.
 */
export interface PushProvider {
  send(target: PushTarget, message: PushMessage): Promise<void>;
}

/**
 * Thrown by a provider when the gateway says the device token is no longer
 * valid (FCM `UNREGISTERED` / HTTP 404). The sender prunes the token and does
 * not retry — the device must re-register.
 */
export class StalePushTokenError extends Error {
  readonly stale = true as const;
  constructor(message: string) {
    super(message);
    this.name = 'StalePushTokenError';
  }
}

export function isStalePushToken(e: unknown): boolean {
  return (
    typeof e === 'object' &&
    e !== null &&
    (e as { stale?: boolean }).stale === true
  );
}
