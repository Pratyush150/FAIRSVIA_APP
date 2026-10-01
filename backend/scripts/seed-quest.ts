/**
 * Seeds one demo quest for TODAY (business day in BUSINESS_TZ): "Complete 10
 * trips today → bonus 150" in the market currency, all tiers. Idempotent:
 * keyed on title + start, so re-running refreshes it instead of adding one.
 *
 *   docker exec fairsvia_backend npx ts-node scripts/seed-quest.ts
 */
import { PrismaClient } from '@prisma/client';
import { startOfBusinessDay } from '../src/common/time/business-day';

const TITLE = 'Daily quest: complete 10 trips today';

async function main() {
  const prisma = new PrismaClient();
  const tz = process.env.BUSINESS_TZ ?? 'Asia/Tashkent';
  const currency = (process.env.MARKET_CURRENCY ?? 'USD').trim().toUpperCase();
  const startsAt = startOfBusinessDay(new Date(), tz);
  const endsAt = startOfBusinessDay(new Date(startsAt.getTime() + 36 * 3600_000), tz);
  const data = {
    title: TITLE,
    tiers: [],
    targetTrips: 10,
    startsAt,
    endsAt,
    bonusAmount: 150,
    currency,
    active: true,
  };
  const existing = await prisma.quest.findFirst({ where: { title: TITLE, startsAt } });
  const q = existing
    ? await prisma.quest.update({ where: { id: existing.id }, data })
    : await prisma.quest.create({ data });
  console.log(
    `${existing ? 'refreshed' : 'created'} quest ${q.id}: ${q.title} ` +
      `(${q.startsAt.toISOString()} → ${q.endsAt.toISOString()}, bonus ${q.bonusAmount} ${q.currency})`,
  );
  await prisma.$disconnect();
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
