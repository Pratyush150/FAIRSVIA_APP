import { BadRequestException, Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreatePromoDto } from './dto/create-promo.dto';
import { UpdatePromoDto } from './dto/update-promo.dto';

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
   * Atomically redeems a code for a rider: guards the global usage limit with a
   * conditional UPDATE, then records the redemption. Returns the discount, or
   * null if the code lost a race for its last slot (caller charges full fare).
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
    // Atomic guarded decrement of the remaining global slots.
    const claimed = await this.prisma.$queryRaw<{ id: string }[]>(Prisma.sql`
      UPDATE promo_codes
         SET used_count = used_count + 1
       WHERE code = ${code}
         AND active = true
         AND (usage_limit IS NULL OR used_count < usage_limit)
       RETURNING id`);
    if (claimed.length === 0) return 0;
    await this.prisma.promoRedemption.create({
      data: {
        promoId: claimed[0].id,
        userId,
        tripId: tripId ?? null,
        discount: quote.discount,
      },
    });
    return quote.discount;
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
    return this.prisma.promoCode.update({
      where: { code: code.trim().toUpperCase() },
      data,
    });
  }
}

function round2(n: number): number {
  return Math.round(n * 100) / 100;
}
