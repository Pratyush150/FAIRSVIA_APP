import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
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
    // Check balance and record the debit in ONE serializable transaction so two
    // concurrent withdrawals can't both pass the guard and overdraw the driver.
    // Postgres SSI raises a serialization failure on the losing writer.
    try {
      const result = await this.prisma.$transaction(
        async (tx) => {
          const agg = await tx.ledgerEntry.aggregate({
            where: { driverId },
            _sum: { amount: true },
          });
          const balance = round2(Number(agg._sum.amount ?? 0));
          if (requested > balance) {
            throw new BadRequestException(
              `You can withdraw up to $${balance.toFixed(2)}.`,
            );
          }
          await tx.ledgerEntry.create({
            data: {
              driverId,
              type: 'withdrawal',
              amount: round2(-requested),
              note: 'Withdrawal to bank (mock)',
            },
          });
          return { withdrawn: requested, balance: round2(balance - requested) };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
      this.logger.log(`driver ${driverId} withdrew ${requested}`);
      return result;
    } catch (e) {
      if (e instanceof BadRequestException) throw e;
      // Serialization conflict — a concurrent withdrawal won the race.
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2034') {
        throw new BadRequestException('Please try again.');
      }
      throw e;
    }
  }
}
