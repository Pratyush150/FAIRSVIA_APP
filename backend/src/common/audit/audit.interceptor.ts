import {
  CallHandler,
  ExecutionContext,
  Injectable,
  Logger,
  NestInterceptor,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import { Observable, tap } from 'rxjs';
import { ROLES_KEY } from '../../auth/decorators/roles.decorator';
import { PrismaService } from '../prisma/prisma.service';
import { redact } from './audit.redact';

/** Methods that change something. A GET is a read; we do not log reads. */
const WRITE_METHODS = new Set(['POST', 'PATCH', 'PUT', 'DELETE']);

/**
 * Route params that name the thing being acted on, in the order we prefer
 * them. `PATCH /admin/drivers/:id/verify` → target `drivers` / `<id>`.
 */
const TARGET_PARAMS = ['tripId', 'userId', 'id', 'code', 'tier'];

/**
 * The global API prefix, which Express reports as part of `req.route.path`.
 * Left in, every row's target came out as `api` — technically true and
 * completely useless for asking "what happened to this driver".
 */
const API_PREFIX = /^\/api\/v\d+/;

/**
 * Records every privileged write to `audit_log`.
 *
 * Coverage is derived from the `@Roles(admin)` metadata the route already
 * carries, **not** from a per-route `@Audited()` decorator. That is deliberate:
 * a decorator is something a future endpoint can forget, and the endpoints
 * worth auditing — refunds, fare edits, driver verification — are exactly the
 * ones nobody notices are unlogged until they need the log.
 *
 * Failures are recorded too. "Someone tried to refund this trip and got a 403"
 * is often the more interesting row.
 *
 * Writing the row must never break the request: a dead database on the audit
 * insert should not turn a successful refund into a 500. Failures here are
 * logged and swallowed.
 */
@Injectable()
export class AuditInterceptor implements NestInterceptor {
  private readonly logger = new Logger(AuditInterceptor.name);

  constructor(
    private readonly reflector: Reflector,
    private readonly prisma: PrismaService,
  ) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();

    const req = context.switchToHttp().getRequest();
    if (!WRITE_METHODS.has(req.method)) return next.handle();
    if (!this.isAdminRoute(context)) return next.handle();

    const rawRoute: string =
      req.route?.path ?? (req.url ?? '').split('?')[0] ?? '';
    const route = rawRoute.replace(API_PREFIX, '') || '/';
    const user = req.user as { id?: string; role?: string } | undefined;
    const { targetType, targetId } = this.target(route, req.params ?? {});

    const base = {
      actorId: user?.id ?? null,
      actorRole: user?.role ?? null,
      action: `${req.method} ${route}`,
      method: req.method as string,
      targetType,
      targetId,
      payload: (redact(req.body) ?? null) as never,
      ip: (req.ip as string | undefined)?.slice(0, 64) ?? null,
      userAgent:
        (req.headers?.['user-agent'] as string | undefined)?.slice(0, 255) ??
        null,
    };

    return next.handle().pipe(
      tap({
        next: (body) => {
          const status =
            context.switchToHttp().getResponse()?.statusCode ?? 200;
          void this.write({
            ...base,
            statusCode: status,
            result: (redact(body) ?? null) as never,
          });
        },
        error: (err: { status?: number; message?: string }) => {
          void this.write({
            ...base,
            statusCode: err?.status ?? 500,
            result: { error: err?.message ?? 'unknown error' } as never,
          });
        },
      }),
    );
  }

  /** True when this route (or its controller) is restricted to admins. */
  private isAdminRoute(context: ExecutionContext): boolean {
    const roles = this.reflector.getAllAndOverride<UserRole[]>(ROLES_KEY, [
      context.getHandler(),
      context.getClass(),
    ]);
    return Array.isArray(roles) && roles.includes(UserRole.admin);
  }

  /**
   * The resource a route acts on: the first segment after the `/admin` prefix
   * (or the first segment at all), plus whichever id param the route carries.
   */
  private target(
    route: string,
    params: Record<string, string>,
  ): { targetType: string | null; targetId: string | null } {
    const segments = route
      .replace(API_PREFIX, '')
      .split('/')
      .filter((s) => s.length > 0 && !s.startsWith(':'));
    const afterAdmin = segments[0] === 'admin' ? segments[1] : segments[0];
    const key = TARGET_PARAMS.find((p) => typeof params[p] === 'string');
    return {
      targetType: afterAdmin ?? null,
      targetId: key ? String(params[key]).slice(0, 64) : null,
    };
  }

  private async write(row: {
    actorId: string | null;
    actorRole: string | null;
    action: string;
    method: string;
    targetType: string | null;
    targetId: string | null;
    payload: never;
    result: never;
    statusCode: number;
    ip: string | null;
    userAgent: string | null;
  }): Promise<void> {
    try {
      await this.prisma.auditLog.create({ data: row });
    } catch (e) {
      // Never fail the request over the audit row — a successful refund that
      // 500s because its log entry didn't write is strictly worse than a
      // refund with a missing row (which this WARN still records somewhere).
      this.logger.warn(
        `audit write failed for ${row.action}: ${String(e)} ` +
          `(actor=${row.actorId ?? 'unknown'} target=${row.targetId ?? '-'})`,
      );
    }
  }
}
