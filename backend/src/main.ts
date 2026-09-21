import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger, RequestMethod } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Logger as PinoLogger } from 'nestjs-pino';
import type { Request, Response, NextFunction } from 'express';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  // rawBody: keep the unparsed request buffer available (req.rawBody) so the
  // Stripe webhook can verify the signature over the exact bytes Stripe signed.
  const app = await NestFactory.create(AppModule, {
    bufferLogs: true,
    rawBody: true,
  });

  // Route all Nest logging through pino.
  app.useLogger(app.get(PinoLogger));

  // All routes are under /api/v1 per the API contract (spec §7.9), except the
  // Prometheus scrape endpoint which stays at the conventional /metrics.
  app.setGlobalPrefix('api/v1', {
    exclude: [{ path: 'metrics', method: RequestMethod.GET }],
  });

  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  // Baseline security headers (dependency-free — the app also sits behind nginx
  // in prod, which adds transport-level headers/HSTS).
  app.use((_req: Request, res: Response, next: NextFunction) => {
    res.setHeader('X-Content-Type-Options', 'nosniff');
    res.setHeader('X-Frame-Options', 'DENY');
    res.setHeader('Referrer-Policy', 'no-referrer');
    res.setHeader('X-DNS-Prefetch-Control', 'off');
    next();
  });

  const config = app.get(ConfigService);
  const isProd = config.get<string>('nodeEnv') === 'production';

  // Behind nginx/Cloudflare the socket peer is the proxy; trust exactly one hop
  // so req.ip (rate-limit key, logs) is the real client. Never in dev, where a
  // spoofed X-Forwarded-For would let anyone pick their own limiter bucket.
  if (isProd || process.env.TRUST_PROXY === '1') {
    app.getHttpAdapter().getInstance().set('trust proxy', 1);
  }

  // CORS: reflect any origin only in dev. In production require an explicit
  // allow-list (CORS_ORIGINS) so a hostile site can't make credentialed calls.
  const corsOrigins = config.get<string[]>('corsOrigins') ?? [];
  app.enableCors({
    origin: isProd ? (corsOrigins.length > 0 ? corsOrigins : false) : true,
    credentials: true,
  });

  // Arm SIGTERM/SIGINT handling. PrismaService, RedisService and all four
  // queue processors implement onModuleDestroy, but without this Nest never
  // calls them: the process is hard-killed with in-flight dispatch jobs and
  // open WebSockets still attached. Invisible on a box that never restarts,
  // fatal under any rolling deploy.
  app.enableShutdownHooks();

  const port = config.get<number>('port') ?? 3000;
  await app.listen(port, '0.0.0.0');
  Logger.log(`RideVela backend listening on http://0.0.0.0:${port}/api/v1`, 'Bootstrap');
}

void bootstrap();
