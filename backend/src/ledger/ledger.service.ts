import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';

export type LedgerType =
  | 'earning'
  | 'tip'
  | 'commission'
  | 'withdrawal'
  | 'adjustment';

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}

@Injectable()
export class LedgerService {
  private readonly logger = new Logger('LedgerService');

  constructor(private readonly prisma: PrismaService) {}

  /** Append a signed movement to a driver's ledger. */
  async record(
    driverId: string,
    type: LedgerType,
    amount: number,
    opts: { tripId?: string; note?: string } = {},
  ) {
    if (!Number.isFinite(amount) || amount === 0) return null;
    return this.prisma.ledgerEntry.create({
      data: {
        driverId,
        type,
        amount: round2(amount),
        tripId: opts.tripId ?? null,
        note: opts.note ?? null,
      },
    });
  }

  /** Current balance = sum of all ledger movements. */
  async balance(driverId: string): Promise<number> {
    const agg = await this.prisma.ledgerEntry.aggregate({
      where: { driverId },
      _sum: { amount: true },
    });
    return round2(Number(agg._sum.amount ?? 0));
  }

  /** Balance plus the most recent movements, newest first. */
  async summary(driverId: string, take = 50) {
    const [balance, entries] = await Promise.all([
      this.balance(driverId),
      this.prisma.ledgerEntry.findMany({
        where: { driverId },
        orderBy: { createdAt: 'desc' },
        take,
      }),
    ]);
    return {
      balance,
      currency: 'USD',
      entries: entries.map((e) => ({
        id: e.id,
        type: e.type,
        amount: Number(e.amount),
        tripId: e.tripId,
        note: e.note,
        createdAt: e.createdAt,
      })),
    };
  }

  /**
   * Withdraw available balance to the driver's (mock) payout account. Guards
   * against over-withdrawal and records a negative `withdrawal` movement.
   */
  async withdraw(driverId: string, amount: number) {
    const requested = round2(amount);
    if (requested <= 0) {
      throw new BadRequestException('Enter an amount greater than zero.');
    }
    const balance = await this.balance(driverId);
    if (requested > balance) {
      throw new BadRequestException(
        `You can withdraw up to $${balance.toFixed(2)}.`,
      );
    }
    await this.record(driverId, 'withdrawal', -requested, {
      note: 'Withdrawal to bank (mock)',
    });
    this.logger.log(`driver ${driverId} withdrew ${requested}`);
    return { withdrawn: requested, balance: round2(balance - requested) };
  }
}
