import { BadRequestException, Injectable, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { isSerializationFailure } from '../common/prisma/serialization';
import { formatMoney } from '../common/money';
import { CURRENCY } from '../pricing/fare-config';

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

  /** Append a signed movement to a driver's ledger. Pass `tx` to make it part
   *  of the caller's transaction (money state and ledger commit together). */
  async record(
    driverId: string,
    type: LedgerType,
    amount: number,
    opts: { tripId?: string; note?: string } = {},
    tx?: Prisma.TransactionClient,
  ) {
    if (!Number.isFinite(amount) || amount === 0) return null;
    return (tx ?? this.prisma).ledgerEntry.create({
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
      currency: CURRENCY,
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
   * Debit available balance for a withdrawal. Guards against over-withdrawal
   * and records a negative `withdrawal` movement. For a real bank transfer the
   * caller does this FIRST (reserve), keys the transfer on the returned entry
   * id, and calls `reverseWithdrawal` if the transfer fails — so two
   * concurrent payouts can never both pass the balance check.
   */
  async withdraw(
    driverId: string,
    amount: number,
    note = 'Withdrawal to bank (mock)',
  ): Promise<{ withdrawn: number; balance: number; entryId: string }> {
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
              `You can withdraw up to ${formatMoney(balance, CURRENCY)}.`,
            );
          }
          const entry = await tx.ledgerEntry.create({
            data: {
              driverId,
              type: 'withdrawal',
              amount: round2(-requested),
              note,
            },
          });
          return {
            withdrawn: requested,
            balance: round2(balance - requested),
            entryId: entry.id,
          };
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
      this.logger.log(`driver ${driverId} withdrew ${requested}`);
      return result;
    } catch (e) {
      if (e instanceof BadRequestException) throw e;
      // Serialization conflict — a concurrent withdrawal won the race.
      if (isSerializationFailure(e)) {
        throw new BadRequestException('Please try again.');
      }
      throw e;
    }
  }

  /** Give back a reserved withdrawal whose bank transfer failed. */
  async reverseWithdrawal(driverId: string, amount: number, reason: string) {
    return this.record(driverId, 'adjustment', round2(amount), {
      note: `Payout reversed: ${reason}`.slice(0, 250),
    });
  }
}
