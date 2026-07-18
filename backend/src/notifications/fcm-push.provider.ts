import { createSign } from 'node:crypto';
import { Injectable, Logger } from '@nestjs/common';
import {
  PushMessage,
  PushProvider,
  PushTarget,
} from './push-provider.interface';

/** The three fields we need out of a Google service-account JSON. */
export interface FcmServiceAccount {
  projectId: string;
  clientEmail: string;
  privateKey: string;
}

const OAUTH_TOKEN_URL = 'https://oauth2.googleapis.com/token';
const FCM_SCOPE = 'https://www.googleapis.com/auth/firebase.messaging';

/**
 * Real Firebase Cloud Messaging provider using the **HTTP v1** API (the legacy
 * `key=` server-key API was shut down in 2024). Authenticates with a Google
 * service account: signs a JWT with the account's private key, exchanges it for
 * a short-lived OAuth access token (cached until it expires), and POSTs the
 * message to `/v1/projects/{projectId}/messages:send`.
 *
 * Selected by NotificationsModule when `FCM_SERVICE_ACCOUNT_JSON` is set;
 * otherwise the mock provider is used.
 */
@Injectable()
export class FcmPushProvider implements PushProvider {
  private readonly logger = new Logger('FcmPush');
  private token: { value: string; expiresAt: number } | null = null;

  constructor(private readonly account: FcmServiceAccount) {
    this.logger.log(
      `Using FCM HTTP v1 push provider (project ${account.projectId}).`,
    );
  }

  /** Parse a service-account JSON string; returns null if it's not usable. */
  static parse(json: string): FcmServiceAccount | null {
    try {
      const o = JSON.parse(json) as Record<string, string>;
      const projectId = o.project_id;
      const clientEmail = o.client_email;
      const privateKey = (o.private_key ?? '').replace(/\\n/g, '\n');
      if (!projectId || !clientEmail || !privateKey) return null;
      return { projectId, clientEmail, privateKey };
    } catch {
      return null;
    }
  }

  async send(target: PushTarget, message: PushMessage): Promise<void> {
    const accessToken = await this.accessToken();
    const url = `https://fcm.googleapis.com/v1/projects/${this.account.projectId}/messages:send`;
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        message: {
          token: target.token,
          notification: { title: message.title, body: message.body },
          ...(message.data ? { data: message.data } : {}),
        },
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      // A 404/UNREGISTERED means the device token is stale — surface it so the
      // caller can prune it, but don't crash the notification pipeline.
      throw new Error(`FCM send failed (${res.status}): ${detail.slice(0, 200)}`);
    }
  }

  /** A valid OAuth access token, minted (and cached) via the service account. */
  private async accessToken(): Promise<string> {
    const now = Date.now();
    if (this.token && this.token.expiresAt > now + 60_000) {
      return this.token.value;
    }
    const jwt = this.signJwt(now);
    const res = await fetch(OAUTH_TOKEN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        assertion: jwt,
      }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) {
      const detail = await res.text().catch(() => '');
      throw new Error(`FCM OAuth failed (${res.status}): ${detail.slice(0, 200)}`);
    }
    const body = (await res.json()) as {
      access_token: string;
      expires_in: number;
    };
    this.token = {
      value: body.access_token,
      expiresAt: now + body.expires_in * 1000,
    };
    return body.access_token;
  }

  /** Build + RS256-sign the service-account JWT for the token exchange. */
  private signJwt(now: number): string {
    const iat = Math.floor(now / 1000);
    const header = { alg: 'RS256', typ: 'JWT' };
    const claims = {
      iss: this.account.clientEmail,
      scope: FCM_SCOPE,
      aud: OAUTH_TOKEN_URL,
      iat,
      exp: iat + 3600,
    };
    const encode = (o: unknown) =>
      Buffer.from(JSON.stringify(o)).toString('base64url');
    const signingInput = `${encode(header)}.${encode(claims)}`;
    const signature = createSign('RSA-SHA256')
      .update(signingInput)
      .sign(this.account.privateKey)
      .toString('base64url');
    return `${signingInput}.${signature}`;
  }
}
