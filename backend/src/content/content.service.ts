import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { RideCard } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { CreateRideCardDto, CtaType, UpdateRideCardDto } from './dto/ride-card.dto';

/** At most this many cards are shown under a ride. */
export const MAX_RIDE_CARDS = 3;

/**
 * Admin-managed promotional / recommendation cards shown under the ride
 * details while the rider waits. A card is live when active and inside its
 * optional time window. Invalid cards are refused at write time so riders
 * never get a dead button: a promo_code card must name a real code, a url
 * card an https link, and any action needs a label.
 */
@Injectable()
export class ContentService {
  constructor(private readonly prisma: PrismaService) {}

  async liveRideCards(now = new Date()) {
    const rows = await this.prisma.rideCard.findMany({
      where: {
        active: true,
        AND: [
          { OR: [{ startsAt: null }, { startsAt: { lte: now } }] },
          { OR: [{ endsAt: null }, { endsAt: { gt: now } }] },
        ],
      },
      orderBy: [{ sortOrder: 'asc' }, { createdAt: 'desc' }],
      take: MAX_RIDE_CARDS,
    });
    return rows.map(ContentService.publicCard);
  }

  static publicCard(c: RideCard) {
    return {
      id: c.id,
      title: c.title,
      body: c.body,
      ctaType: c.ctaType,
      ctaLabel: c.ctaLabel,
      ctaValue: c.ctaValue,
    };
  }

  listAll() {
    return this.prisma.rideCard.findMany({
      orderBy: [{ active: 'desc' }, { sortOrder: 'asc' }, { createdAt: 'desc' }],
    });
  }

  async create(dto: CreateRideCardDto) {
    await this.validate({
      ctaType: dto.ctaType,
      ctaLabel: dto.ctaLabel,
      ctaValue: dto.ctaValue,
      startsAt: dto.startsAt,
      endsAt: dto.endsAt,
    });
    return this.prisma.rideCard.create({
      data: {
        title: dto.title.trim(),
        body: dto.body.trim(),
        ctaType: dto.ctaType,
        ctaLabel: dto.ctaType === 'none' ? null : dto.ctaLabel?.trim(),
        ctaValue: dto.ctaType === 'none' ? null : this.normalise(dto.ctaType, dto.ctaValue),
        active: dto.active ?? true,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : null,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : null,
        sortOrder: dto.sortOrder ?? 0,
      },
    });
  }

  async update(id: string, dto: UpdateRideCardDto) {
    const existing = await this.prisma.rideCard.findUnique({ where: { id } });
    if (!existing) throw new NotFoundException('Card not found');
    const ctaType = (dto.ctaType ?? existing.ctaType) as CtaType;
    const merged = {
      ctaType,
      ctaLabel: dto.ctaLabel ?? existing.ctaLabel ?? undefined,
      ctaValue: dto.ctaValue ?? existing.ctaValue ?? undefined,
      startsAt: dto.startsAt ?? existing.startsAt?.toISOString(),
      endsAt: dto.endsAt ?? existing.endsAt?.toISOString(),
    };
    await this.validate(merged);
    return this.prisma.rideCard.update({
      where: { id },
      data: {
        title: dto.title?.trim(),
        body: dto.body?.trim(),
        ctaType,
        ctaLabel: ctaType === 'none' ? null : merged.ctaLabel?.trim(),
        ctaValue: ctaType === 'none' ? null : this.normalise(ctaType, merged.ctaValue),
        active: dto.active,
        startsAt: dto.startsAt ? new Date(dto.startsAt) : undefined,
        endsAt: dto.endsAt ? new Date(dto.endsAt) : undefined,
        sortOrder: dto.sortOrder,
      },
    });
  }

  async remove(id: string) {
    const res = await this.prisma.rideCard.deleteMany({ where: { id } });
    if (res.count === 0) throw new NotFoundException('Card not found');
    return { removed: true };
  }

  private normalise(type: CtaType, value?: string) {
    const v = value?.trim();
    return type === 'promo_code' ? v?.toUpperCase() : v;
  }

  private async validate(c: {
    ctaType: CtaType;
    ctaLabel?: string;
    ctaValue?: string;
    startsAt?: string;
    endsAt?: string;
  }) {
    if (c.startsAt && c.endsAt && new Date(c.endsAt) <= new Date(c.startsAt)) {
      throw new BadRequestException('The card must end after it starts.');
    }
    if (c.ctaType === 'none') return;
    if (!c.ctaLabel?.trim()) {
      throw new BadRequestException('A card with an action needs a button label.');
    }
    const value = c.ctaValue?.trim();
    if (!value) throw new BadRequestException('A card with an action needs its code or link.');
    if (c.ctaType === 'url') {
      let url: URL;
      try {
        url = new URL(value);
      } catch {
        throw new BadRequestException('The link is not a valid URL.');
      }
      if (url.protocol !== 'https:') {
        throw new BadRequestException('Links must use https.');
      }
    }
    if (c.ctaType === 'promo_code') {
      const promo = await this.prisma.promoCode.findUnique({
        where: { code: value.toUpperCase() },
      });
      if (!promo || !promo.active) {
        throw new BadRequestException(`There is no active promo code "${value.toUpperCase()}".`);
      }
    }
  }
}
