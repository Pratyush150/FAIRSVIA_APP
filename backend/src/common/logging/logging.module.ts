import { randomUUID } from 'crypto';
import { Module } from '@nestjs/common';
import { LoggerModule } from 'nestjs-pino';

const isProd = process.env.NODE_ENV === 'production';

/**
 * Structured JSON logging via pino. Every request gets a correlation id
 * (x-request-id, echoed back) so a single request/trip can be traced across log
 * lines. Pretty, colourised output in dev; raw JSON (for log shippers) in prod.
 */
@Module({
  imports: [
    LoggerModule.forRoot({
      pinoHttp: {
        level: process.env.LOG_LEVEL ?? 'info',
        // Don't log health checks / metrics scrapes — pure noise.
        autoLogging: {
          ignore: (req) => {
            const url = (req.url ?? '').split('?')[0];
            return url === '/metrics' || url.endsWith('/health');
          },
        },
        genReqId: (req, res) => {
          const existing =
            (req.headers['x-request-id'] as string | undefined) ?? randomUUID();
          res.setHeader('x-request-id', existing);
          return existing;
        },
        redact: ['req.headers.authorization', 'req.headers.cookie'],
        // Dev pretty output drops `req`/`res`, so put the route + status in
        // the message itself; that is what a human tailing the log needs.
        customSuccessMessage: (req, res) =>
          `${req.method} ${req.url} -> ${res.statusCode}`,
        customErrorMessage: (req, res, err) =>
          `${req.method} ${req.url} -> ${res.statusCode} ${err.message}`,
        transport: isProd
          ? undefined
          : {
              target: 'pino-pretty',
              options: {
                singleLine: true,
                colorize: true,
                translateTime: 'SYS:HH:MM:ss',
                ignore: 'pid,hostname,req,res',
              },
            },
      },
    }),
  ],
})
export class LoggingModule {}
