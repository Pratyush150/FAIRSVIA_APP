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
