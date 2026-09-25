import { BadRequestException, Injectable, Logger, NotFoundException } from '@nestjs/common';
import { Prisma, Quest, RideTier, TripStatus } from '@prisma/client';
import { PrismaService } from '../common/prisma/prisma.service';
import { LedgerService } from '../ledger/ledger.service';
import { RealtimeService } from '../realtime/realtime.service';
import { CURRENCY } from '../pricing/fare-config';
import { formatMoney } from '../common/money';
import { questProgress } from './quest-math';
import { CreateQuestDto, UpdateQuestDto } from './dto/quest.dto';

/** How long a finished quest stays on the driver's list. */
const SHOW_ENDED_FOR_MS = 24 * 3600_000;

@Injectable()
export class QuestsService {
  private readonly logger = new Logger('Quests');

  constructor(
    private readonly prisma: PrismaService,
    private readonly ledger: LedgerService,
    private readonly realtime: RealtimeService,
  ) {}

  // ---------------------------------------------------------------- admin

  list() {
    return this.prisma.quest
      .findMany({
        orderBy: { startsAt: 'desc' },
        take: 200,
        include: { _count: { select: { awards: true } } },
      })
      .then((qs) => qs.map((q) => ({ ...this.view(q), awards: q._count.awards })));
  }

  async create(dto: CreateQuestDto) {
    const startsAt = new Date(dto.startsAt);
    const endsAt = new Date(dto.endsAt);
    this.assertWindow(startsAt, endsAt);
    const q = await this.prisma.quest.create({
      data: {
        title: dto.title.trim(),
        tiers: (dto.tiers ?? []) as RideTier[],
        targetTrips: dto.targetTrips,
        startsAt,
        endsAt,
        bonusAmount: dto.bonusAmount,
        currency: CURRENCY,
        active: dto.active ?? true,
      },
    });
    return this.view(q);
  }

  async update(id: string, dto: UpdateQuestDto) {
    const prev = await this.prisma.quest.findUnique({ where: { id } });
    if (!prev) throw new NotFoundException('Quest not found');
    const startsAt = dto.startsAt ? new Date(dto.startsAt) : prev.startsAt;
    const endsAt = dto.endsAt ? new Date(dto.endsAt) : prev.endsAt;
    this.assertWindow(startsAt, endsAt);
    const q = await this.prisma.quest.update({
      where: { id },
      data: {
        ...(dto.title !== undefined ? { title: dto.title.trim() } : {}),
        ...(dto.tiers !== undefined ? { tiers: dto.tiers as RideTier[] } : {}),
        ...(dto.targetTrips !== undefined ? { targetTrips: dto.targetTrips } : {}),
        ...(dto.bonusAmount !== undefined ? { bonusAmount: dto.bonusAmount } : {}),
        ...(dto.active !== undefined ? { active: dto.active } : {}),
        startsAt,
        endsAt,
      },
    });
    return this.view(q);
  }

  private assertWindow(startsAt: Date, endsAt: Date) {
    if (!(endsAt.getTime() > startsAt.getTime())) {
      throw new BadRequestException('endsAt must be after startsAt');
    }
  }

  private view(q: Quest) {
    return {
      id: q.id,
      title: q.title,
      tiers: q.tiers,
      targetTrips: q.targetTrips,
      startsAt: q.startsAt,
      endsAt: q.endsAt,
      bonusAmount: Number(q.bonusAmount),
      currency: q.currency,
      active: q.active,
    };
  }

  // --------------------------------------------------------------- driver

  /** Trips this driver completed inside the quest window, [startsAt, endsAt). */
  private countTrips(driverId: string, q: Quest): Promise<number> {
    return this.prisma.trip.count({
      where: {
        driverId,
        status: TripStatus.completed,
        completedAt: { gte: q.startsAt, lt: q.endsAt },
        ...(q.tiers.length ? { tier: { in: q.tiers } } : {}),
      },
    });
  }

  /**
   * The driver's quests: running now, starting within a day, or ended in the
   * last day (so a finished one is still visible). Awards anything reached
   * but not yet paid on the way (the completion hook normally got there first).
   */
  async forDriver(driverId: string, now = new Date()) {
    const quests = await this.prisma.quest.findMany({
      where: {
        active: true,
        startsAt: { lte: new Date(now.getTime() + SHOW_ENDED_FOR_MS) },
        endsAt: { gte: new Date(now.getTime() - SHOW_ENDED_FOR_MS) },
      },
      orderBy: { endsAt: 'asc' },
    });
    const out = [];
    for (const q of quests) {
      const n = await this.countTrips(driverId, q);
      const p = questProgress(q, n);
      let paid = !!(await this.prisma.questAward.findUnique({
        where: { questId_driverId: { questId: q.id, driverId } },
        select: { id: true },
      }));
      if (p.completed && !paid) paid = await this.award(driverId, q);
      out.push({
        id: q.id,
        title: q.title,
        tiers: q.tiers,
        progress: p.progress,
        target: p.target,
        bonus: Number(q.bonusAmount),
        currency: q.currency,
        startsAt: q.startsAt,
        endsAt: q.endsAt,
        completed: p.completed,
        paid,
        status: now < q.startsAt ? 'upcoming' : now >= q.endsAt ? 'ended' : 'active',
      });
    }
    return out;
  }

  /**
   * Called after every completed trip (best-effort, never throws): pays any
   * quest this trip just finished. The trip itself decides which quests are
   * in play — its completion time and tier — so a late hook still pays right.
   */
  async onTripCompleted(driverId: string, tripId: string): Promise<void> {
    try {
      const trip = await this.prisma.trip.findUnique({
        where: { id: tripId },
        select: { completedAt: true, tier: true },
      });
      if (!trip?.completedAt) return;
      const quests = await this.prisma.quest.findMany({
        where: {
          active: true,
          startsAt: { lte: trip.completedAt },
          endsAt: { gt: trip.completedAt },
        },
      });
      for (const q of quests) {
        if (q.tiers.length && !q.tiers.includes(trip.tier)) continue;
        const n = await this.countTrips(driverId, q);
        if (questProgress(q, n).completed) await this.award(driverId, q);
      }
    } catch (e) {
      this.logger.warn(`quest check for trip ${tripId} failed: ${String(e)}`);
    }
  }

  /**
   * Pay a quest bonus exactly once. The award row and the ledger credit are
   * one transaction and the (quest, driver) unique key rejects a second
   * award, so concurrent completions / list reads can never pay twice.
   * Returns true when the quest is (now or already) paid.
   */
  async award(driverId: string, q: Quest): Promise<boolean> {
    const amount = Number(q.bonusAmount);
    try {
      await this.prisma.$transaction(async (tx) => {
        const award = await tx.questAward.create({
          data: { questId: q.id, driverId, amount },
        });
        const entry = await this.ledger.record(
          driverId,
          'bonus',
          amount,
          { note: `Quest bonus: ${q.title}` },
          tx,
        );
        if (entry) {
          await tx.questAward.update({
            where: { id: award.id },
            data: { ledgerEntryId: entry.id },
          });
        }
      });
    } catch (e) {
      if (e instanceof Prisma.PrismaClientKnownRequestError && e.code === 'P2002') {
        return true; // already paid
      }
      throw e;
    }
    this.logger.log(`quest ${q.id} bonus ${amount} paid to ${driverId}`);
    this.realtime.emitToUser(driverId, 'quest:completed', {
      questId: q.id,
      title: q.title,
      bonus: amount,
      currency: q.currency,
      message: `Quest complete — ${formatMoney(amount, q.currency)} bonus added`,
    });
    return true;
  }
}
