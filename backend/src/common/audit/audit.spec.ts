import { ExecutionContext } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { UserRole } from '@prisma/client';
import { lastValueFrom, of, throwError } from 'rxjs';
import { AuditInterceptor } from './audit.interceptor';
import { redact, REDACTED } from './audit.redact';
import { PrismaService } from '../prisma/prisma.service';

describe('redact', () => {
  it('replaces anything secret-looking, at any depth', () => {
    const out = redact({
      amount: 25,
      stripeSecretKey: 'sk_live_abc',
      nested: { apiKey: 'k', authorization: 'Bearer x', keep: 'me' },
    }) as Record<string, never>;

    expect(out.amount).toBe(25);
    expect(out.stripeSecretKey).toBe(REDACTED);
    expect(out.nested).toEqual({
      apiKey: REDACTED,
      authorization: REDACTED,
      keep: 'me',
    });
  });

  it('redacts start codes and OTPs, which are credentials for a ride', () => {
    const out = redact({ startOtp: '4266', promoCode: 'SAVE10' }) as Record<
      string,
      never
    >;
    expect(out.startOtp).toBe(REDACTED);
    expect(out.promoCode).toBe(REDACTED);
  });

  it('truncates a long string instead of storing it whole', () => {
    const out = redact({ note: 'x'.repeat(2000) }) as { note: string };
    expect(out.note.length).toBeLessThan(600);
    expect(out.note).toContain('truncated');
  });

  it('caps arrays and depth rather than walking forever', () => {
    const wide = redact({ xs: Array.from({ length: 200 }, (_, i) => i) }) as {
      xs: unknown[];
    };
    expect(wide.xs.length).toBe(51); // 50 kept + the marker
    expect(String(wide.xs[50])).toContain('truncated');

    let deep: unknown = 'bottom';
    for (let i = 0; i < 12; i++) deep = { deep };
    expect(JSON.stringify(redact(deep))).toContain('too deep');
  });

  it('leaves an empty body as nothing, not as {}', () => {
    expect(redact({})).toBeUndefined();
    expect(redact(undefined)).toBeUndefined();
  });
});

describe('AuditInterceptor', () => {
  function setup(opts: {
    roles?: UserRole[];
    method?: string;
    route?: string;
    params?: Record<string, string>;
    body?: unknown;
    createImpl?: jest.Mock;
  }) {
    const create = opts.createImpl ?? jest.fn().mockResolvedValue({});
    const prisma = { auditLog: { create } } as unknown as PrismaService;
    const reflector = {
      getAllAndOverride: jest.fn().mockReturnValue(opts.roles),
    } as unknown as Reflector;

    const req = {
      method: opts.method ?? 'PATCH',
      route: { path: opts.route ?? '/admin/drivers/:id/verify' },
      params: opts.params ?? { id: 'driver-1' },
      body: opts.body ?? { verified: true },
      ip: '10.0.0.9',
      headers: { 'user-agent': 'AdminApp/1.0' },
      user: { id: 'admin-1', role: 'admin' },
    };
    const context = {
      getType: () => 'http',
      getHandler: () => undefined,
      getClass: () => undefined,
      switchToHttp: () => ({
        getRequest: () => req,
        getResponse: () => ({ statusCode: 200 }),
      }),
    } as unknown as ExecutionContext;

    return { create, interceptor: new AuditInterceptor(reflector, prisma), context };
  }

  it('records an admin write with actor, target and origin', async () => {
    const { create, interceptor, context } = setup({ roles: [UserRole.admin] });

    await lastValueFrom(
      interceptor.intercept(context, { handle: () => of({ ok: true }) }),
    );

    expect(create).toHaveBeenCalledTimes(1);
    expect(create.mock.calls[0][0].data).toMatchObject({
      actorId: 'admin-1',
      actorRole: 'admin',
      action: 'PATCH /admin/drivers/:id/verify',
      targetType: 'drivers',
      targetId: 'driver-1',
      statusCode: 200,
      ip: '10.0.0.9',
      userAgent: 'AdminApp/1.0',
    });
  });

  it('records the attempt when the handler fails', async () => {
    // "Someone tried to refund this trip and got a 403" is often the row that
    // matters most.
    const { create, interceptor, context } = setup({ roles: [UserRole.admin] });

    await expect(
      lastValueFrom(
        interceptor.intercept(context, {
          handle: () =>
            throwError(() => ({ status: 403, message: 'Insufficient role' })),
        }),
      ),
    ).rejects.toBeDefined();

    expect(create.mock.calls[0][0].data).toMatchObject({
      statusCode: 403,
      result: { error: 'Insufficient role' },
    });
  });

  it('ignores reads — a GET is not a change', async () => {
    const { create, interceptor, context } = setup({
      roles: [UserRole.admin],
      method: 'GET',
    });
    await lastValueFrom(
      interceptor.intercept(context, { handle: () => of([]) }),
    );
    expect(create).not.toHaveBeenCalled();
  });

  it('ignores writes on routes that are not admin-only', async () => {
    // A rider booking a trip is not an admin action.
    const { create, interceptor, context } = setup({ roles: undefined });
    await lastValueFrom(
      interceptor.intercept(context, { handle: () => of({}) }),
    );
    expect(create).not.toHaveBeenCalled();

    const driverOnly = setup({ roles: [UserRole.driver] });
    await lastValueFrom(
      driverOnly.interceptor.intercept(driverOnly.context, {
        handle: () => of({}),
      }),
    );
    expect(driverOnly.create).not.toHaveBeenCalled();
  });

  it('redacts the request body it stores', async () => {
    const { create, interceptor, context } = setup({
      roles: [UserRole.admin],
      body: { amount: 12.5, adminToken: 'super-secret' },
    });
    await lastValueFrom(
      interceptor.intercept(context, { handle: () => of({}) }),
    );
    expect(create.mock.calls[0][0].data.payload).toEqual({
      amount: 12.5,
      adminToken: REDACTED,
    });
  });

  it('never fails the request when the audit write itself fails', async () => {
    // A refund that succeeds but 500s because its log row didn't write is
    // strictly worse than a refund with a missing row.
    const { interceptor, context } = setup({
      roles: [UserRole.admin],
      createImpl: jest.fn().mockRejectedValue(new Error('db down')),
    });

    await expect(
      lastValueFrom(
        interceptor.intercept(context, { handle: () => of({ refunded: true }) }),
      ),
    ).resolves.toEqual({ refunded: true });
  });

  it('strips the global /api/vN prefix Express reports', async () => {
    // Left in, every row's target came out as `api` — true, and useless for
    // asking "what has anyone done to this driver".
    const { create, interceptor, context } = setup({
      roles: [UserRole.admin],
      route: '/api/v1/admin/drivers/:id/verify',
    });
    await lastValueFrom(
      interceptor.intercept(context, { handle: () => of({}) }),
    );
    expect(create.mock.calls[0][0].data).toMatchObject({
      action: 'PATCH /admin/drivers/:id/verify',
      targetType: 'drivers',
      targetId: 'driver-1',
    });
  });

  it('names the target from whichever id param the route carries', async () => {
    const trip = setup({
      roles: [UserRole.admin],
      method: 'POST',
      route: '/payments/:tripId/refund',
      params: { tripId: 'trip-9' },
    });
    await lastValueFrom(
      trip.interceptor.intercept(trip.context, { handle: () => of({}) }),
    );
    expect(trip.create.mock.calls[0][0].data).toMatchObject({
      targetType: 'payments',
      targetId: 'trip-9',
    });

    // A route with no id at all still records what was touched.
    const surge = setup({
      roles: [UserRole.admin],
      route: '/admin/surge',
      params: {},
    });
    await lastValueFrom(
      surge.interceptor.intercept(surge.context, { handle: () => of({}) }),
    );
    expect(surge.create.mock.calls[0][0].data).toMatchObject({
      targetType: 'surge',
      targetId: null,
    });
  });
});
