import type { ExecutionContext } from '@nestjs/common';

/**
 * Rate-limit policy. Three named buckets, each per client IP per 60 s:
 *  - `default`  every HTTP route (sane ceiling against a single abusive client)
 *  - `tight`    credential endpoints: OTP request, refresh
 *  - `moderate` compute/vendor-cost endpoints: fare estimates, Places
 *               (autocomplete / details / reverse), chat send, support tickets
 *
 * Limits are read from the environment here (not `configuration.ts`, which is
 * owned by another change in flight) and are tunable for load tests:
 *   THROTTLE_LIMIT / THROTTLE_TIGHT_LIMIT / THROTTLE_MODERATE_LIMIT (req/min)
 *   THROTTLE_DISABLED=true  — turn it off entirely (automatic under NODE_ENV=test
 *   so jest/e2e suites that hammer one endpoint don't flake).
 */
export type ThrottleBucket = 'tight' | 'moderate';

export interface ThrottleConfig {
  disabled: boolean;
  ttlMs: number;
  defaultLimit: number;
  tightLimit: number;
  moderateLimit: number;
}

export const THROTTLE_TTL_MS = 60_000;

function intEnv(v: string | undefined, fallback: number): number {
  const n = parseInt(v ?? '', 10);
  return Number.isFinite(n) && n > 0 ? n : fallback;
}

export function throttleConfig(env: NodeJS.ProcessEnv = process.env): ThrottleConfig {
  const flag = (env.THROTTLE_DISABLED ?? '').toLowerCase();
  const disabled = flag === 'true' || flag === '1' || env.NODE_ENV === 'test';
  return {
    disabled,
    ttlMs: THROTTLE_TTL_MS,
    defaultLimit: intEnv(env.THROTTLE_LIMIT, 120),
    tightLimit: intEnv(env.THROTTLE_TIGHT_LIMIT, 5),
    moderateLimit: intEnv(env.THROTTLE_MODERATE_LIMIT, 30),
  };
}

/** Route patterns matched against `METHOD /path` with the `/api/vN` prefix
 *  stripped. Paths are Express route *patterns* (so `:tripId` stays literal),
 *  which lets us throttle routes owned by other modules without decorating
 *  each controller. */
const TIGHT_ROUTES: RegExp[] = [
  /^POST \/auth\/otp\/request$/,
  /^POST \/auth\/refresh$/,
];

const MODERATE_ROUTES: RegExp[] = [
  /^POST \/trips\/estimate$/,
  /^POST \/comparison\/estimate$/,
  /^GET \/places(\/|$)/,
  /^POST \/trips\/:tripId\/messages$/,
  /^POST \/support\/tickets$/,
];

const PREFIX = /^\/api\/v\d+/;

export function normalizeRoute(method: string, routePath: string): string {
  const stripped = routePath.replace(PREFIX, '') || '/';
  return `${method.toUpperCase()} ${stripped}`;
}

export function classifyRoute(method: string, routePath: string): ThrottleBucket | null {
  const key = normalizeRoute(method, routePath);
  if (TIGHT_ROUTES.some((r) => r.test(key))) return 'tight';
  if (MODERATE_ROUTES.some((r) => r.test(key))) return 'moderate';
  return null;
}

/** Bucket for the request in an HTTP execution context (null = default only). */
export function bucketFor(context: ExecutionContext): ThrottleBucket | null {
  if (context.getType() !== 'http') return null;
  const req = context.switchToHttp().getRequest<{
    method?: string;
    route?: { path?: string };
    path?: string;
  }>();
  const path = req.route?.path ?? req.path ?? '';
  return classifyRoute(req.method ?? 'GET', path);
}
