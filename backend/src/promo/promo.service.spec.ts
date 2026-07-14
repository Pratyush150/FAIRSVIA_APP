import { BadRequestException } from '@nestjs/common';
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
