import { Injectable } from '@nestjs/common';
import { PrismaService } from '../common/prisma/prisma.service';
import { computeRates, tally } from './driver-rates';

/** The rates window: the last 7 days of offers. */
export const RATES_WINDOW_DAYS = 7;

@Injectable()
export class DriverStatsService {
  constructor(private readonly prisma: PrismaService) {}

  /** Acceptance and cancellation rates over the last 7 days. */
  async stats(driverId: string, now = new Date()) {
    const since = new Date(now.getTime() - RATES_WINDOW_DAYS * 86400_000);
    const rows = await this.prisma.driverOfferEvent.groupBy({
      by: ['outcome'],
      where: { driverId, createdAt: { gte: since } },
      _count: { _all: true },
    });
    const outcomes: string[] = [];
    for (const r of rows) {
      for (let i = 0; i < r._count._all; i++) outcomes.push(r.outcome);
    }
    return { window: `${RATES_WINDOW_DAYS}d`, since, ...computeRates(tally(outcomes)) };
  }
}
