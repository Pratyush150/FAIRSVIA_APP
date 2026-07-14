import { BadRequestException } from '@nestjs/common';
import { LedgerService } from './ledger.service';
import { PrismaService } from '../common/prisma/prisma.service';

function makeService(sum: number) {
  const create = jest.fn().mockResolvedValue({});
  const prisma = {
    ledgerEntry: {
      create,
      aggregate: jest.fn().mockResolvedValue({ _sum: { amount: sum } }),
      findMany: jest.fn().mockResolvedValue([]),
    },
  } as unknown as PrismaService;
  return { svc: new LedgerService(prisma), create };
}

describe('LedgerService', () => {
  it('sums movements into the balance', async () => {
    const { svc } = makeService(275.5);
    expect(await svc.balance('d1')).toBe(275.5);
  });

  it('records a signed movement (rounded), skips zero', async () => {
    const { svc, create } = makeService(0);
    await svc.record('d1', 'earning', 114.377);
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ type: 'earning', amount: 114.38 }),
      }),
    );
    create.mockClear();
    await svc.record('d1', 'tip', 0);
    expect(create).not.toHaveBeenCalled();
  });

  it('withdraws up to the balance and debits it', async () => {
    const { svc, create } = makeService(500);
    const res = await svc.withdraw('d1', 200);
    expect(res).toEqual({ withdrawn: 200, balance: 300 });
    expect(create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({ type: 'withdrawal', amount: -200 }),
      }),
    );
  });

  it('rejects over-withdrawal and non-positive amounts', async () => {
    const { svc } = makeService(50);
    await expect(svc.withdraw('d1', 100)).rejects.toThrow(BadRequestException);
    await expect(svc.withdraw('d1', 0)).rejects.toThrow(BadRequestException);
  });
});
