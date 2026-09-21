import { ArgumentsHost, Catch, HttpException, Logger } from '@nestjs/common';
import { BaseWsExceptionFilter, WsException } from '@nestjs/websockets';
import { Socket } from 'socket.io';

/** Shape every WS handler error reaches the client in (`exception` event). */
export interface WsErrorPayload {
  status: 'error';
  /** HTTP-style status code (400, 403, 404, 409, 500, ...). */
  code: number;
  /** Human-readable, safe to show in the app. */
  message: string;
  /** The event the failing message was sent on, when known. */
  event?: string;
}

/**
 * Nest's default WS filter turns any non-WsException (i.e. every
 * HttpException our services throw — "Finish your current trip before going
 * offline.", validation errors, 403s) into a bare `{ message: 'Internal server
 * error' }`. That masked real, actionable messages from the driver app (API
 * audit). This filter forwards HttpException/WsException details verbatim and
 * keeps the generic message only for genuinely unexpected errors.
 */
@Catch()
export class WsExceptionsFilter extends BaseWsExceptionFilter {
  private readonly logger = new Logger('WsExceptions');

  catch(exception: unknown, host: ArgumentsHost): void {
    const client = host.switchToWs().getClient<Socket>();
    const pattern = host.switchToWs().getPattern?.() as string | undefined;
    const payload = WsExceptionsFilter.toPayload(exception, pattern);
    if (payload.code >= 500) {
      this.logger.error(
        `unhandled WS error on ${pattern ?? '?'}: ${String(
          (exception as Error)?.stack ?? exception,
        )}`,
      );
    }
    client.emit('exception', payload);
  }

  static toPayload(exception: unknown, event?: string): WsErrorPayload {
    const base = event ? { event } : {};
    if (exception instanceof HttpException) {
      return {
        status: 'error',
        code: exception.getStatus(),
        message: WsExceptionsFilter.messageOf(exception.getResponse(), exception.message),
        ...base,
      };
    }
    if (exception instanceof WsException) {
      return {
        status: 'error',
        code: 400,
        message: WsExceptionsFilter.messageOf(exception.getError(), exception.message),
        ...base,
      };
    }
    return { status: 'error', code: 500, message: 'Internal server error', ...base };
  }

  /** Extract a readable message from an HttpException/WsException body. */
  private static messageOf(body: unknown, fallback: string): string {
    if (typeof body === 'string') return body;
    if (body && typeof body === 'object') {
      const m = (body as { message?: unknown }).message;
      if (Array.isArray(m)) return m.map(String).join('; ');
      if (typeof m === 'string') return m;
    }
    return fallback;
  }
}
