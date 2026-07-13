import { NestFactory } from '@nestjs/core';
import { ValidationPipe, Logger, RequestMethod } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Logger as PinoLogger } from 'nestjs-pino';
import { AppModule } from './app.module';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });

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

  // Permissive CORS for local dev (rider/driver/admin apps on various origins).
  app.enableCors({ origin: true, credentials: true });

  const config = app.get(ConfigService);
  const port = config.get<number>('port') ?? 3000;
  await app.listen(port, '0.0.0.0');
  Logger.log(`UberNav backend listening on http://0.0.0.0:${port}/api/v1`, 'Bootstrap');
}

void bootstrap();
