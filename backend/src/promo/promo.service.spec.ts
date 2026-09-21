import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PromoService } from './promo.service';
import { PrismaService } from '../common/prisma/prisma.service';

/** Builds a promo row with sane defaults for the quote() path. */
function promoRow(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    id: 'p1',
    code: 'SAVE10',
    kind: 'flat',
    value: 10,
    maxDiscount: null,
    minSubtotal: 0,
    usageLimit: null,
    usedCount: 0,
    perUserLimit: 1,
    active: true,
    expiresAt: null,
    createdAt: new Date('2026-01-01'),
    ...overrides,
  };
}

function makeService(row: unknown, redemptionCount = 0) {
  const prisma = {
    promoCode: { findUnique: jest.fn().mockResolvedValue(row) },
    promoRedemption: { count: jest.fn().mockResolvedValue(redemptionCount) },
  } as unknown as PrismaService;
  return new PromoService(prisma);
}

describe('PromoService.quote', () => {
  it('applies a flat discount', async () => {
    const svc = makeService(promoRow({ kind: 'flat', value: 40 }));
    const q = await svc.quote('save10', 200, 'u1');
    expect(q.discount).toBe(40);
    expect(q.net).toBe(160);
  });

  it('applies a percentage discount', async () => {
    const svc = makeService(promoRow({ kind: 'percent', value: 25 }));
    const q = await svc.quote('save10', 200, 'u1');
    expect(q.discount).toBe(50);
    expect(q.net).toBe(150);
  });

  it('caps a percentage discount at maxDiscount', async () => {
    const svc = makeService(
      promoRow({ kind: 'percent', value: 50, maxDiscount: 60 }),
    );
    const q = await svc.quote('save10', 300, 'u1');
    expect(q.discount).toBe(60); // 50% of 300 = 150, capped to 60
  });

  it('never discounts below a zero fare (flat > subtotal)', async () => {
    const svc = makeService(promoRow({ kind: 'flat', value: 500 }));
    const q = await svc.quote('save10', 120, 'u1');
    expect(q.discount).toBe(120);
    expect(q.net).toBe(0);
  });

  it('rejects an unknown or inactive code', async () => {
    await expect(makeService(null).quote('nope', 200, 'u1')).rejects.toThrow(
      BadRequestException,
    );
    await expect(
      makeService(promoRow({ active: false })).quote('save10', 200, 'u1'),
    ).rejects.toThrow(BadRequestException);
  });

  it('rejects an expired code', async () => {
    const svc = makeService(
      promoRow({ expiresAt: new Date('2020-01-01') }),
    );
    await expect(svc.quote('save10', 200, 'u1')).rejects.toThrow(/expired/i);
  });

  it('rejects a fully-redeemed code', async () => {
    const svc = makeService(promoRow({ usageLimit: 5, usedCount: 5 }));
    await expect(svc.quote('save10', 200, 'u1')).rejects.toThrow(/redeemed/i);
  });

  it('enforces the minimum subtotal', async () => {
    const svc = makeService(promoRow({ minSubtotal: 150 }));
    await expect(svc.quote('save10', 100, 'u1')).rejects.toThrow(/at least/i);
  });

  it('enforces the per-user limit', async () => {
    const svc = makeService(promoRow({ perUserLimit: 1 }), 1);
    await expect(svc.quote('save10', 200, 'u1')).rejects.toThrow(
      /already used/i,
    );
  });
});

/**
 * redeem(): the per-user count, the guarded global decrement and the insert
 * run inside ONE serializable transaction (the old count-then-insert race let
 * two concurrent requests both pass the per-user limit).
 */
describe('PromoService.redeem', () => {
  function makeTxService(opts: {
    row?: unknown;
    countOutside?: number;
    countInside?: number;
    claimed?: { id: string }[];
    txError?: Error;
  } = {}) {
    // `row: null` must mean "no such code" — don't let ?? swallow it.
    const row = opts.row === undefined ? promoRow() : opts.row;
    const tx = {
      promoCode: { findUnique: jest.fn().mockResolvedValue(row) },
      promoRedemption: {
        count: jest.fn().mockResolvedValue(opts.countInside ?? 0),
        create: jest.fn().mockResolvedValue({}),
      },
      $queryRaw: jest.fn().mockResolvedValue(opts.claimed ?? [{ id: 'p1' }]),
    };
    const prisma = {
      promoCode: { findUnique: jest.fn().mockResolvedValue(row) },
      promoRedemption: { count: jest.fn().mockResolvedValue(opts.countOutside ?? 0) },
      $transaction: jest.fn(async (cb: (t: unknown) => Promise<unknown>) => {
        if (opts.txError) throw opts.txError;
        return cb(tx);
      }),
    };
    return { svc: new PromoService(prisma as unknown as PrismaService), prisma, tx };
  }

  it('claims the slot, inserts the redemption and returns the discount in one transaction', async () => {
    const { svc, prisma, tx } = makeTxService();
    const d = await svc.redeem('save10', 200, 'u1', 't1');
    expect(d).toBe(10);
    expect(prisma.$transaction).toHaveBeenCalledWith(
      expect.any(Function),
      { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
    );
    expect(tx.promoRedemption.count).toHaveBeenCalledWith({
      where: { promoId: 'p1', userId: 'u1' },
    });
    expect(tx.promoRedemption.create).toHaveBeenCalledWith({
      data: { promoId: 'p1', userId: 'u1', tripId: 't1', discount: 10 },
    });
  });

  it('grants nothing when the in-transaction per-user count is already at the limit', async () => {
    // The advisory quote() count said 0, but a concurrent redemption landed
    // before our transaction re-checked.
    const { svc, tx } = makeTxService({ countOutside: 0, countInside: 1 });
    expect(await svc.redeem('save10', 200, 'u1', 't1')).toBe(0);
    expect(tx.$queryRaw).not.toHaveBeenCalled();
    expect(tx.promoRedemption.create).not.toHaveBeenCalled();
  });

  it('grants nothing when the global slot claim finds no capacity', async () => {
    const { svc, tx } = makeTxService({ claimed: [] });
    expect(await svc.redeem('save10', 200, 'u1', 't1')).toBe(0);
    expect(tx.promoRedemption.create).not.toHaveBeenCalled();
  });

  it('grants nothing (never throws) when it loses a serialization race', async () => {
    const { svc } = makeTxService({
      txError: new Prisma.PrismaClientKnownRequestError('conflict', {
        code: 'P2034',
        clientVersion: 'x',
      }),
    });
    expect(await svc.redeem('save10', 200, 'u1', 't1')).toBe(0);
  });

  it('grants nothing for an invalid code without opening a transaction', async () => {
    const { svc, prisma } = makeTxService({ row: null });
    expect(await svc.redeem('nope', 200, 'u1', 't1')).toBe(0);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });
});

describe('PromoService.release', () => {
  function makeReleaseService(redemption: { id: string; promoId: string } | null) {
    const tx = {
      promoRedemption: {
        findFirst: jest.fn().mockResolvedValue(redemption),
        delete: jest.fn().mockResolvedValue({}),
      },
      $executeRaw: jest.fn().mockResolvedValue(1),
    };
    const prisma = {
      $transaction: jest.fn(async (cb: (t: unknown) => Promise<unknown>) => cb(tx)),
    };
    return { svc: new PromoService(prisma as unknown as PrismaService), tx };
  }

  it('deletes the trip redemption and hands the global slot back', async () => {
    const { svc, tx } = makeReleaseService({ id: 'red1', promoId: 'p1' });
    expect(await svc.release('t1')).toBe(true);
    expect(tx.promoRedemption.findFirst).toHaveBeenCalledWith({ where: { tripId: 't1' } });
    expect(tx.promoRedemption.delete).toHaveBeenCalledWith({ where: { id: 'red1' } });
    expect(tx.$executeRaw).toHaveBeenCalledTimes(1);
    // Guarded decrement on the promo the redemption belonged to.
    const sql = tx.$executeRaw.mock.calls[0][0] as Prisma.Sql;
    expect(sql.sql).toMatch(/used_count = used_count - 1/);
    expect(sql.sql).toMatch(/used_count > 0/);
    expect(sql.values).toEqual(['p1']);
  });

  it('is a no-op for a trip that never redeemed a code', async () => {
    const { svc, tx } = makeReleaseService(null);
    expect(await svc.release('t1')).toBe(false);
    expect(tx.promoRedemption.delete).not.toHaveBeenCalled();
    expect(tx.$executeRaw).not.toHaveBeenCalled();
  });
});
