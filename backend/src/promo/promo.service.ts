import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';
import { isSerializationFailure } from '../common/prisma/serialization';

/** A promo as the rider's Offers page shows it. */
export interface AvailablePromo {
  code: string;
  title: string;
  description: string | null;
  kind: string;
  value: number;
  maxDiscount: number | null;
  minFare: number;
  expiresAt: string | null;
  /** How many more times THIS rider can use it (>= 1 — spent ones are omitted). */
  usesLeftForMe: number;
}

/** Outcome of pricing a promo code against a fare subtotal. */
export interface PromoQuote {
  code: string;
  kind: string;
  discount: number;
  subtotal: number;
  net: number;
}

@Injectable()
export class PromoService {
  constructor(private readonly prisma: PrismaService) {}

  /**
   * Prices a code against a subtotal for a given rider without redeeming it.
   * Throws BadRequestException with a rider-friendly reason when the code is
   * invalid, exhausted, expired, or the subtotal is below the minimum.
   */
  async quote(
    codeRaw: string,
    subtotal: number,
    userId: string,
  ): Promise<PromoQuote> {
    const code = codeRaw.trim().toUpperCase();
    const promo = await this.prisma.promoCode.findUnique({ where: { code } });
    if (!promo || !promo.active) {
      throw new BadRequestException('That promo code is not valid.');
    }
    if (promo.expiresAt && promo.expiresAt.getTime() < Date.now()) {
      throw new BadRequestException('That promo code has expired.');
    }
    if (promo.usageLimit != null && promo.usedCount >= promo.usageLimit) {
      throw new BadRequestException('That promo code has been fully redeemed.');
    }
    const minSubtotal = Number(promo.minSubtotal);
    if (subtotal < minSubtotal) {
      throw new BadRequestException(
        `Spend at least ${minSubtotal.toFixed(0)} to use this code.`,
      );
    }
    const used = await this.prisma.promoRedemption.count({
      where: { promoId: promo.id, userId },
    });
    if (used >= promo.perUserLimit) {
      throw new BadRequestException(
        'You have already used this promo code.',
      );
    }

    const discount = this.discountFor(promo, subtotal);
    if (discount <= 0) {
      throw new BadRequestException('This code gives no discount on this fare.');
    }
    return {
      code: promo.code,
      kind: promo.kind,
      discount,
      subtotal: round2(subtotal),
      net: round2(Math.max(subtotal - discount, 0)),
    };
  }

  /**
   * Atomically redeems a code for a rider. The per-user count, the guarded
   * global-slot decrement and the redemption insert all run in ONE serializable
   * transaction, so two concurrent requests from the same rider can't both pass
   * the per-user check (count-then-insert race). Returns the discount, or 0 if
   * the code is invalid, lost the race for its last slot, or the transaction
   * had to be aborted (the loser of a serialization conflict charges full fare
   * rather than failing trip creation).
   */
  async redeem(
    codeRaw: string,
    subtotal: number,
    userId: string,
    tripId?: string,
  ): Promise<number> {
    let quote: PromoQuote;
    try {
      quote = await this.quote(codeRaw, subtotal, userId);
    } catch {
      // Never fail trip creation on a bad promo — just grant no discount.
      return 0;
    }
    const code = quote.code;
    try {
      return await this.prisma.$transaction(
        async (tx) => {
          const promo = await tx.promoCode.findUnique({ where: { code } });
          if (!promo) return 0;
          // Re-check the per-user limit inside the transaction: the quote()
          // count above is only advisory.
          const used = await tx.promoRedemption.count({
            where: { promoId: promo.id, userId },
          });
          if (used >= promo.perUserLimit) return 0;
          // Atomic guarded decrement of the remaining global slots.
          const claimed = await tx.$queryRaw<{ id: string }[]>(Prisma.sql`
            UPDATE promo_codes
               SET used_count = used_count + 1
             WHERE code = ${code}
               AND active = true
               AND (usage_limit IS NULL OR used_count < usage_limit)
             RETURNING id`);
          if (claimed.length === 0) return 0;
          await tx.promoRedemption.create({
            data: {
              promoId: claimed[0].id,
              userId,
              tripId: tripId ?? null,
              discount: quote.discount,
            },
          });
          return quote.discount;
        },
        { isolationLevel: Prisma.TransactionIsolationLevel.Serializable },
      );
    } catch (e) {
      if (
        isSerializationFailure(e)
      ) {
        return 0; // lost a serialization race — no discount, ride proceeds
      }
      throw e;
    }
  }

  /**
   * Releases the redemption tied to a trip that was cancelled before
   * completion: deletes the redemption row (so the rider's per-user allowance
   * is restored) and hands the global slot back. Idempotent — a trip with no
   * redemption is a no-op. Never throws into the cancel path.
   */
  async release(tripId: string): Promise<boolean> {
    return this.prisma.$transaction(async (tx) => {
      const redemption = await tx.promoRedemption.findFirst({
        where: { tripId },
      });
      if (!redemption) return false;
      await tx.promoRedemption.delete({ where: { id: redemption.id } });
      await tx.$executeRaw(Prisma.sql`
        UPDATE promo_codes
           SET used_count = used_count - 1
         WHERE id = ${redemption.promoId}::uuid
           AND used_count > 0`);
      return true;
    });
  }

  private discountFor(
    promo: { kind: string; value: Prisma.Decimal; maxDiscount: Prisma.Decimal | null },
    subtotal: number,
  ): number {
    const value = Number(promo.value);
    let discount: number;
    if (promo.kind === 'percent') {
      discount = (subtotal * value) / 100;
      if (promo.maxDiscount != null) {
        discount = Math.min(discount, Number(promo.maxDiscount));
      }
    } else {
      discount = value;
    }
    // Never discount below zero fare.
    return round2(Math.min(discount, subtotal));
  }

  /**
   * Rider-facing Offers list: promos that are listed, active, unexpired, not
   * globally exhausted, and that this rider still has uses left on. Soonest
   * expiry first (open-ended last), then newest.
   */
  async available(userId: string): Promise<AvailablePromo[]> {
    const now = new Date();
    const promos = await this.prisma.promoCode.findMany({
      where: {
        listed: true,
        active: true,
        OR: [{ expiresAt: null }, { expiresAt: { gt: now } }],
      },
      orderBy: [{ expiresAt: { sort: 'asc', nulls: 'last' } }, { createdAt: 'desc' }],
      take: 50,
    });
    const open = promos.filter(
      (p) => p.usageLimit == null || p.usedCount < p.usageLimit,
    );
    if (open.length === 0) return [];
    const mine = await this.prisma.promoRedemption.groupBy({
      by: ['promoId'],
      where: { userId, promoId: { in: open.map((p) => p.id) } },
      _count: { _all: true },
    });
    const used = new Map(mine.map((m) => [m.promoId, m._count._all]));
    return open
      .map((p) => ({
        code: p.code,
        title: p.title ?? p.code,
        description: p.description ?? null,
        kind: p.kind,
        value: Number(p.value),
        maxDiscount: p.maxDiscount == null ? null : Number(p.maxDiscount),
        minFare: Number(p.minSubtotal),
        expiresAt: p.expiresAt ? p.expiresAt.toISOString() : null,
        usesLeftForMe: p.perUserLimit - (used.get(p.id) ?? 0),
      }))
      .filter((p) => p.usesLeftForMe > 0);
  }

  // --- Admin management ---

  list() {
    return this.prisma.promoCode.findMany({ orderBy: { createdAt: 'desc' } });
  }

  async create(dto: CreatePromoDto) {
    return this.prisma.promoCode.create({
      data: {
        code: dto.code.trim().toUpperCase(),
        kind: dto.kind,
        value: dto.value,
        maxDiscount: dto.maxDiscount ?? null,
        minSubtotal: dto.minSubtotal ?? 0,
        usageLimit: dto.usageLimit ?? null,
        perUserLimit: dto.perUserLimit ?? 1,
        active: dto.active ?? true,
        expiresAt: dto.expiresAt ? new Date(dto.expiresAt) : null,
        listed: dto.listed ?? false,
        title: dto.title?.trim() || null,
        description: dto.description?.trim() || null,
      },
    });
  }

  async update(code: string, dto: UpdatePromoDto) {
    const data: Prisma.PromoCodeUpdateInput = {};
    if (dto.active != null) data.active = dto.active;
    if (dto.usageLimit !== undefined) data.usageLimit = dto.usageLimit;
    if (dto.perUserLimit != null) data.perUserLimit = dto.perUserLimit;
    if (dto.expiresAt !== undefined) {
      data.expiresAt = dto.expiresAt ? new Date(dto.expiresAt) : null;
    }
    if (dto.listed != null) data.listed = dto.listed;
    if (dto.title !== undefined) data.title = dto.title?.trim() || null;
    if (dto.description !== undefined) {
      data.description = dto.description?.trim() || null;
    }
    return this.prisma.promoCode.update({
      where: { code: code.trim().toUpperCase() },
      data,
    });
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
