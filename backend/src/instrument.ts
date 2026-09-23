// Must be the very first import in main.ts, before AppModule or anything
// that could throw during its own import — Sentry can't capture what happens
// before it's initialized. Reads process.env directly (not ConfigService):
// this runs before Nest, and therefore before ConfigModule, exists.
//
// Empty SENTRY_DSN is not an error: Sentry.init() with no dsn is a documented
// no-op, so this is "mock by default, real once you set a key" — the same
// pattern every other external provider in this backend follows.
import * as Sentry from '@sentry/nestjs';

Sentry.init({
  dsn: process.env.SENTRY_DSN || undefined,
  environment: process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV || 'development',
  tracesSampleRate: process.env.NODE_ENV === 'production' ? 0.2 : 0,
});
