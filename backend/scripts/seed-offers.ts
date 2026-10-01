/**
 * Seeds the three demo Offers (listed promo codes) — idempotent: upserts by
 * code, refreshes the rider-facing copy and terms, never touches usedCount or
 * redemptions. Amounts are in the market currency (MARKET_CURRENCY); the copy
 * says "off" without a symbol so it reads right in any market.
 *
 *   docker exec fairsvia_backend npx ts-node scripts/seed-offers.ts
 */
import { PrismaClient } from '@prisma/client';

const OFFERS = [
  {
    code: 'WELCOME50',
    kind: 'percent',
    value: 50,
    maxDiscount: 100,
    minSubtotal: 0,
    perUserLimit: 1,
    title: 'Welcome offer',
    description: 'Half price on a ride — one use per rider.',
  },
  {
    code: 'AIRPORT100',
    kind: 'flat',
    value: 100,
    maxDiscount: null,
    minSubtotal: 400,
    perUserLimit: 2,
    title: 'Airport run',
    description: 'Flat 100 off longer trips, like the airport run. Fare must be 400 or more.',
  },
  {
    code: 'WEEKEND20',
    kind: 'percent',
    value: 20,
    maxDiscount: 60,
    minSubtotal: 0,
    perUserLimit: 4,
    title: 'Weekend saver',
    description: '20% off your rides, up to 4 times.',
  },
] as const;

async function main() {
  const prisma = new PrismaClient();
  try {
    for (const o of OFFERS) {
      const terms = {
        kind: o.kind,
        value: o.value,
        maxDiscount: o.maxDiscount,
        minSubtotal: o.minSubtotal,
        perUserLimit: o.perUserLimit,
        title: o.title,
        description: o.description,
        listed: true,
        active: true,
      };
      await prisma.promoCode.upsert({
        where: { code: o.code },
        create: { code: o.code, ...terms },
        update: terms,
      });
      console.log(`offer ${o.code} ready`);
    }
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
